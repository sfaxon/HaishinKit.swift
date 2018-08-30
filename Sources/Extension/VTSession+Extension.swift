import Foundation
import VideoToolbox

extension VTCompressionSession {
    func copySupportedPropertyDictionary() -> [AnyHashable: Any] {
        var support: CFDictionary? = nil
        guard VTSessionCopySupportedPropertyDictionary(self, &support) == noErr else {
            return [:]
        }
        guard let result: [AnyHashable: Any] = support as? [AnyHashable: Any] else {
            return [:]
        }
        return result
    }

    /// The maximum interval between key frames, also known as the key frame rate.
    ///
    /// Every `maxKeyFrameInterval` should be a keyframe. A value of 1 is every frame a keyframe,
    /// a value of 2 is every other frame a keyframe.
    var maxKeyFrameInterval: NSNumber {
        var result = NSNumber(value: Int(-1))
        VTSessionCopyProperty(self, kVTCompressionPropertyKey_MaxKeyFrameInterval, kCFAllocatorDefault, &result)
        return result
    }

    /// The maximum duration from one key frame to the next in seconds.
    var maxKeyFrameIntervalDuration: NSNumber {
        var result = NSNumber(value: Int(-1))
        VTSessionCopyProperty(self, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, kCFAllocatorDefault, &result)
        return result
    }

    /// read only
    var numberOfPendingFrames: NSNumber {
        var result = NSNumber(value: Int(-1))
        VTSessionCopyProperty(self, kVTCompressionPropertyKey_NumberOfPendingFrames, kCFAllocatorDefault, &result)
        return result
    }

    var videoEncoderPixelBufferAttributes: [AnyHashable: Any] {
        var properties: CFDictionary? = nil
        guard VTSessionCopyProperty(self, kVTCompressionPropertyKey_VideoEncoderPixelBufferAttributes, kCFAllocatorDefault, &properties) == noErr else {
            fatalError("error converting video encoder pixel buffer attributes")
        }
        guard let result: [AnyHashable: Any] = properties as? [AnyHashable: Any] else {
            fatalError("error converting video encoder properties to result")
        }
        return result
    }
}
