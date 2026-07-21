#import "VisionTextRequestPerformer.h"

static NSString *const TPOVisionTextRequestPerformerErrorDomain = @"TodoPilotVisionTextRequestPerformer";

@implementation TPOVisionTextRequestPerformer

+ (BOOL)performTextRequest:(VNRecognizeTextRequest *)request
                 withImage:(CGImageRef)image
                     error:(NSError **)error {
    @try {
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
        return [handler performRequests:@[request] error:error];
    } @catch (NSException *exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:TPOVisionTextRequestPerformerErrorDomain
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Vision OCR failed unexpectedly. Paste Text is still available as a fallback."
            }];
        }
        return NO;
    }
}

@end
