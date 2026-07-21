#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(VisionTextRequestPerformer)
@interface TPOVisionTextRequestPerformer : NSObject

+ (BOOL)performTextRequest:(VNRecognizeTextRequest *)request
                 withImage:(CGImageRef)image
                     error:(NSError **)error NS_SWIFT_NAME(perform(_:with:));

@end

NS_ASSUME_NONNULL_END
