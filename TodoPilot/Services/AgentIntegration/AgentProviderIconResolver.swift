import AppKit
import Foundation

struct AgentProviderIconDescriptor: Equatable {
    let bundleIdentifiers: [String]
    let applicationNames: [String]
    let fallbackAssetName: String

    static func descriptor(for provider: AgentProvider) -> AgentProviderIconDescriptor {
        switch provider {
        case .claudeCode:
            return AgentProviderIconDescriptor(
                bundleIdentifiers: ["com.anthropic.claudefordesktop"],
                applicationNames: ["Claude"],
                fallbackAssetName: "AgentIconClaudeCode"
            )
        case .codex:
            return AgentProviderIconDescriptor(
                bundleIdentifiers: ["com.openai.codex", "com.openai.chat"],
                applicationNames: ["Codex", "ChatGPT"],
                fallbackAssetName: "AgentIconCodex"
            )
        case .cursor:
            return AgentProviderIconDescriptor(
                bundleIdentifiers: ["com.todesktop.230313mzl4w4u92", "com.anysphere.cursor"],
                applicationNames: ["Cursor"],
                fallbackAssetName: "AgentIconCursor"
            )
        }
    }
}

final class AgentProviderIconResolver {
    typealias ApplicationURLLookup = (String) -> URL?
    typealias NamedApplicationURLLookup = (String) -> URL?
    typealias FileIconLookup = (URL) -> NSImage?
    typealias AssetImageLookup = (String) -> NSImage?

    static let shared = AgentProviderIconResolver()

    private let applicationURL: ApplicationURLLookup
    private let namedApplicationURL: NamedApplicationURLLookup
    private let fileIcon: FileIconLookup
    private let assetImage: AssetImageLookup
    private let lock = NSLock()
    private var cachedImages: [AgentProvider: NSImage] = [:]
    private var missingProviders: Set<AgentProvider> = []

    init(
        applicationURL: @escaping ApplicationURLLookup = { identifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        },
        namedApplicationURL: @escaping NamedApplicationURLLookup = AgentProviderIconResolver.findNamedApplication,
        fileIcon: @escaping FileIconLookup = { url in
            NSWorkspace.shared.icon(forFile: url.path)
        },
        assetImage: @escaping AssetImageLookup = { name in
            NSImage(named: NSImage.Name(name))
        }
    ) {
        self.applicationURL = applicationURL
        self.namedApplicationURL = namedApplicationURL
        self.fileIcon = fileIcon
        self.assetImage = assetImage
    }

    func image(for provider: AgentProvider) -> NSImage? {
        lock.lock()
        if let cached = cachedImages[provider] {
            lock.unlock()
            return cached
        }
        if missingProviders.contains(provider) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let descriptor = AgentProviderIconDescriptor.descriptor(for: provider)
        let application = firstResolvedValue(in: descriptor.bundleIdentifiers, using: applicationURL)
            ?? firstResolvedValue(in: descriptor.applicationNames, using: namedApplicationURL)
        let resolved = application.flatMap(fileIcon)
            ?? assetImage(descriptor.fallbackAssetName)

        lock.lock()
        if let resolved {
            cachedImages[provider] = resolved
        } else {
            missingProviders.insert(provider)
        }
        lock.unlock()
        return resolved
    }

    private func firstResolvedValue(
        in candidates: [String],
        using lookup: (String) -> URL?
    ) -> URL? {
        for candidate in candidates {
            if let resolved = lookup(candidate) {
                return resolved
            }
        }
        return nil
    }

    private static func findNamedApplication(_ name: String) -> URL? {
        let manager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        return roots
            .map { $0.appendingPathComponent("\(name).app", isDirectory: true) }
            .first(where: { manager.fileExists(atPath: $0.path) })
    }
}
