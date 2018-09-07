import Foundation
import VideoToolbox

extension VTCompressionSession {
    func copySupportedPropertyDictionary() -> [String: Any] {
        var support: CFDictionary? = nil
        guard VTSessionCopySupportedPropertyDictionary(self, &support) == noErr else {
            return [:]
        }
        guard let result: [String: Any] = support as? [String: Any] else {
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

    /// read only
    var allowFrameReordering: Bool {
        var result = kCFBooleanTrue
        let status = VTSessionCopyProperty(self, kVTCompressionPropertyKey_AllowFrameReordering, kCFAllocatorDefault, &result)
        if status == noErr {
            return Bool(truncating: result!)
        }
        fatalError("allow frame reording query failed.")
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

extension VTCompressionSession: CustomDebugStringConvertible {
    public var debugDescription: String {
        let options = self.copySupportedPropertyDictionary()
        var result: String = ""

        for (key, value) in options {
            guard let property = value as? [String: Any] else {
                print("key could not be converted: \(key)")
                continue
            }
            if let propertyType = property["PropertyType"] as? String {
                switch propertyType {
                case "Number":
                    var n = NSNumber(integerLiteral: -1)
                    let status = VTSessionCopyProperty(self, key as CFString, kCFAllocatorDefault, &n)
                    if status == noErr {
                        result.append(contentsOf: "\(key): (number) \(n) \n")
                    } else {
                        print("could not convert key to number: \(key)")
                    }
                case "Boolean":
                    var b = kCFBooleanTrue
                    let status = VTSessionCopyProperty(self, key as CFString, kCFAllocatorDefault, &b)
                    if status == noErr {
                        if b == kCFBooleanTrue {
                            result.append(contentsOf: "\(key): (boolean) true \n")
                        } else if b == kCFBooleanFalse {
                            result.append(contentsOf: "\(key): (boolean) true \n")
                        } else {
                            result.append(contentsOf: "\(key): (boolean) nil \n")
                        }
                    }
                case "Enumeration":
                    if let props: [String: Any] = value as? [String: Any] {
                        if props["SupportedValueList"] != nil {
                            var s = CFStringCreateMutable(kCFAllocatorDefault, 256)
                            let status = VTSessionCopyProperty(self, key as CFString, kCFAllocatorDefault, &s)
                            if status == noErr {
                                guard let st = s as String? else {
                                    continue
                                }
                                result.append(contentsOf: "\(key): (string) \(st)")
                            } else {
                                print("status faield")
                            }
                        } else {
                            print("key: \(key) is an Enum without a SupportedValueList")
                        }
                    } else {
                        print("something else: \(value)")
                    }
                default:
                    print("propertyType: \(propertyType) not yet switched")
                }
            } else {
//                print("last ditch for: \(key)")
                if key == "PoolPixelBufferAttributesSeed" {
                    continue
                }
                if key == "FigThreadPriority" {
                    continue
                }
                if key == "FieldDetail" {
                    continue
                }
                if key == "PixelBufferPoolIsShared" {
                    continue
                }
                if key == "AllowPixelTransfer" {
                    continue
                }
                if key == "EncoderID" {
                    continue
                }
                if key == kVTCompressionPropertyKey_NumberOfPendingFrames as String {
                    result.append(contentsOf: "\(key): (number) \(self.numberOfPendingFrames) \n")
                    continue
                }
                var dict: CFDictionary? = nil
                guard VTSessionCopyProperty(self, key as CFString, kCFAllocatorDefault, &dict) == noErr else {
                    print("key does not have PropertyType and is not another dictonary: \(key)")
                    continue
                }
                guard let r: [AnyHashable: Any] = dict as? [AnyHashable: Any] else {
                    print("key does not have PropertyType and is not another dictonary: \(key)")
                    continue
                }

                result.append(contentsOf: "\(key): (dictionary) \(r)")
            }
        }
        return result
    }
}
