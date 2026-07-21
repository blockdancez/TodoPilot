import CoreGraphics
import Foundation
import ImageIO
import Vision
import VisionKit

struct OCRTextBlock: Equatable {
    let text: String
    let confidence: Double
    let boundingBox: CGRect
}

struct OCRResult: Equatable {
    let text: String
    let blocks: [OCRTextBlock]
}

protocol OCRService {
    func recognizeText(in image: CGImage, language: AppLanguage) async throws -> OCRResult
}

extension OCRService {
    func recognizeText(in image: CGImage) async throws -> OCRResult {
        try await recognizeText(in: image, language: .english)
    }
}

struct VisionOCRService: OCRService {
    func recognizeText(in image: CGImage, language: AppLanguage) async throws -> OCRResult {
        let copy = AppCopy(language: language)
        if ImageAnalyzer.isSupported {
            return try await Self.recognizeTextWithImageAnalyzer(in: image, timeoutMessage: copy.ocrTimeout)
        }

        return try await Self.recognizeTextWithVisionRequest(in: image, timeoutMessage: copy.ocrTimeout)
    }

    private static func recognizeTextWithImageAnalyzer(in image: CGImage, timeoutMessage: String) async throws -> OCRResult {
        try await withTodoPilotTimeout(
            seconds: 8,
            message: timeoutMessage
        ) {
            var configuration = ImageAnalyzer.Configuration(.text)
            let supportedLanguages = Set(ImageAnalyzer.supportedTextRecognitionLanguages)
            let languages = ["zh-Hans", "en-US"].filter(supportedLanguages.contains)
            if !languages.isEmpty {
                configuration.locales = languages
            }

            let analysis = try await ImageAnalyzer().analyze(
                image,
                orientation: .up,
                configuration: configuration
            )
            let text = analysis.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            return OCRResult(text: text, blocks: [])
        }
    }

    private static func recognizeTextWithVisionRequest(in image: CGImage, timeoutMessage: String) async throws -> OCRResult {
        try await withTodoPilotTimeout(
            seconds: 8,
            message: timeoutMessage
        ) {
            try await Task.detached(priority: .userInitiated) {
                try Self.recognizeTextSynchronously(in: image)
            }.value
        }
    }

    private static func recognizeTextSynchronously(in image: CGImage) throws -> OCRResult {
        var lastError: Error?
        var emptyResult: OCRResult?
        for configuration in recognitionConfigurations() {
            do {
                let result = try performRecognition(in: image, configuration: configuration)
                if !result.text.isEmpty {
                    return result
                }
                if emptyResult == nil {
                    emptyResult = result
                }
            } catch {
                lastError = error
            }
        }

        if let emptyResult {
            return emptyResult
        }
        throw lastError ?? TodoPilotError.permissionRequired("TodoPilot could not recognize text in the selected region.")
    }

    private static func performRecognition(in image: CGImage, configuration: OCRRecognitionConfiguration) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.revision = configuration.revision
        request.recognitionLevel = configuration.level
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        request.automaticallyDetectsLanguage = configuration.automaticallyDetectsLanguage
        request.preferBackgroundProcessing = true
        request.minimumTextHeight = 0.01
        request.usesCPUOnly = true

        if !configuration.languages.isEmpty {
            let supportedLanguages = Set((try? request.supportedRecognitionLanguages()) ?? [])
            let languages = configuration.languages.filter(supportedLanguages.contains)
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }
        }

        try VisionTextRequestPerformer.perform(request, with: image)

        let observations = request.results ?? []
        let blocks = observations.compactMap { observation -> OCRTextBlock? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            return OCRTextBlock(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                boundingBox: observation.boundingBox
            )
        }

        let text = blocks
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return OCRResult(text: text, blocks: blocks)
    }

    private static func recognitionConfigurations() -> [OCRRecognitionConfiguration] {
        stableTextRecognitionRevisions().flatMap { revision in
            var configurations = [
                OCRRecognitionConfiguration(
                    level: .fast,
                    languages: [],
                    usesLanguageCorrection: false,
                    automaticallyDetectsLanguage: revision >= 3,
                    revision: revision
                ),
                OCRRecognitionConfiguration(
                    level: .accurate,
                    languages: [],
                    usesLanguageCorrection: false,
                    automaticallyDetectsLanguage: revision >= 3,
                    revision: revision
                )
            ]

            if revision >= 3 {
                configurations.append(contentsOf: [
                    OCRRecognitionConfiguration(
                        level: .accurate,
                        languages: ["zh-Hans", "en-US"],
                        usesLanguageCorrection: false,
                        automaticallyDetectsLanguage: false,
                        revision: revision
                    ),
                    OCRRecognitionConfiguration(
                        level: .accurate,
                        languages: ["en-US"],
                        usesLanguageCorrection: false,
                        automaticallyDetectsLanguage: false,
                        revision: revision
                    )
                ])
            } else {
                configurations.append(OCRRecognitionConfiguration(
                    level: .accurate,
                    languages: ["en-US"],
                    usesLanguageCorrection: false,
                    automaticallyDetectsLanguage: false,
                    revision: revision
                ))
            }

            return configurations
        }
    }

    private static func stableTextRecognitionRevisions() -> [Int] {
        var revisions: [Int] = []

        func appendIfSupported(_ revision: Int) {
            guard
                revision != 2,
                VNRecognizeTextRequest.supportedRevisions.contains(revision),
                !revisions.contains(revision)
            else {
                return
            }
            revisions.append(revision)
        }

        appendIfSupported(3)
        appendIfSupported(VNRecognizeTextRequest.defaultRevision)
        appendIfSupported(VNRecognizeTextRequest.currentRevision)
        appendIfSupported(1)

        if revisions.isEmpty {
            revisions.append(VNRecognizeTextRequest.defaultRevision)
        }

        return revisions
    }
}

private struct OCRRecognitionConfiguration {
    let level: VNRequestTextRecognitionLevel
    let languages: [String]
    let usesLanguageCorrection: Bool
    let automaticallyDetectsLanguage: Bool
    let revision: Int
}

extension OCRResult {
    var hasLowConfidenceBlocks: Bool {
        blocks.contains { $0.confidence < 0.55 }
    }
}
