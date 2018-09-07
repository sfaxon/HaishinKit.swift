import AVFoundation
import VideoToolbox
import CoreFoundation
import os.signpost

protocol VideoEncoderDelegate: class {
    func didSetFormatDescription(video formatDescription: CMFormatDescription?)
    func sampleOutput(video sampleBuffer: CMSampleBuffer)
}

// MARK: -
final class H264Encoder: NSObject {
    static let supportedSettingsKeys: [String] = [
        "muted",
        "width",
        "height",
        "bitrate",
        "profileLevel",
        "dataRateLimits",
        "enabledHardwareEncoder", // macOS only
        "maxKeyFrameIntervalDuration",
        "scalingMode"
    ]

    static let defaultWidth: Int32 = 480
    static let defaultHeight: Int32 = 272
    static let defaultBitrate: UInt32 = 160 * 1024
    static let defaultScalingMode: String = "Trim"

    #if os(iOS)
    static let defaultAttributes: [NSString: AnyObject] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as AnyObject
//        kCVPixelBufferOpenGLESCompatibilityKey: kCFBooleanTrue
    ]
    #else
    static let defaultAttributes: [NSString: AnyObject] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as AnyObject,
        kCVPixelBufferOpenGLCompatibilityKey: kCFBooleanTrue
    ]
    #endif
    static let defaultDataRateLimits: [Int] = [0, 0]

    var frameCount = Int(0)

    @objc var muted: Bool = false
    @objc var scalingMode: String = H264Encoder.defaultScalingMode {
        didSet {
            guard scalingMode != oldValue else {
                return
            }
            invalidateSession = true
        }
    }

    @objc var width: Int32 = H264Encoder.defaultWidth {
        didSet {
            guard width != oldValue else {
                return
            }
            invalidateSession = true
        }
    }
    @objc var height: Int32 = H264Encoder.defaultHeight {
        didSet {
            guard height != oldValue else {
                return
            }
            invalidateSession = true
        }
    }
    @objc var enabledHardwareEncoder: Bool = true {
        didSet {
            guard enabledHardwareEncoder != oldValue else {
                return
            }
            invalidateSession = true
        }
    }
    @objc var bitrate: UInt32 = H264Encoder.defaultBitrate {
        didSet {
            guard bitrate != oldValue else {
                return
            }
            setProperty(kVTCompressionPropertyKey_AverageBitRate, Int(bitrate) as CFTypeRef)
        }
    }

    @objc var dataRateLimits: [Int] = H264Encoder.defaultDataRateLimits {
        didSet {
            guard dataRateLimits != oldValue else {
                return
            }
            if dataRateLimits == H264Encoder.defaultDataRateLimits {
                invalidateSession = true
                return
            }
            setProperty(kVTCompressionPropertyKey_DataRateLimits, dataRateLimits as CFTypeRef)
        }
    }
    @objc var profileLevel: String = kVTProfileLevel_H264_Main_AutoLevel as String {
        didSet {
            guard profileLevel != oldValue else {
                return
            }
            invalidateSession = true
        }
    }
    @objc var maxKeyFrameIntervalDuration: Double = 2.0 {
        didSet {
            guard maxKeyFrameIntervalDuration != oldValue else {
                return
            }
            setProperty(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: maxKeyFrameIntervalDuration))
        }
    }

    var locked: UInt32 = 0
    var lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.H264Encoder.lock")
    var expectedFPS: Float64 = AVMixer.defaultFPS {
        didSet {
            guard expectedFPS != oldValue else {
                return
            }
            setProperty(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: expectedFPS))
        }
    }
    var formatDescription: CMFormatDescription? {
        didSet {
            guard !CMFormatDescriptionEqual(formatDescription, oldValue) else {
                return
            }
            delegate?.didSetFormatDescription(video: formatDescription)
        }
    }
    weak var delegate: VideoEncoderDelegate?

    internal(set) var running: Bool = false
    private var supportedProperty: [AnyHashable: Any]? = nil {
        didSet {
//            guard logger.isEnabledFor(level: .info) else {
//                return
//            }
            var keys: [String] = []
            for (key, _) in supportedProperty ?? [:] {
                keys.append(key.description)
            }
//            logger.info(keys.joined(separator: ", "))
        }
    }
    private(set) var status: OSStatus = noErr
    private var attributes: [NSString: AnyObject] {
        var attributes: [NSString: AnyObject] = [:] // H264Encoder.defaultAttributes
        attributes[kCVPixelBufferWidthKey] = NSNumber(value: width)
        attributes[kCVPixelBufferHeightKey] = NSNumber(value: height)
        attributes[kCVPixelBufferPixelFormatTypeKey] = NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) // NSNumber(value: 875704438)
        return attributes
    }
    private var invalidateSession: Bool = true
    private var lastImageBuffer: CVImageBuffer?

    // @see: https: //developer.apple.com/library/mac/releasenotes/General/APIDiffsMacOSX10_8/VideoToolbox.html
//    private var properties: [NSString: NSObject] {
//        let isBaseline: Bool = profileLevel.contains("Baseline")
//        var properties: [NSString: NSObject] = [
//            kVTCompressionPropertyKey_RealTime: kCFBooleanTrue,
////            kVTCompressionPropertyKey_ProfileLevel: profileLevel,
//            kVTCompressionPropertyKey_AverageBitRate: Int(bitrate) as NSObject,
//            kVTCompressionPropertyKey_ExpectedFrameRate: NSNumber(value: expectedFPS),
//            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: NSNumber(value: maxKeyFrameIntervalDuration),
//            kVTCompressionPropertyKey_MaxKeyFrameInterval: NSNumber(value: maxKeyFrameIntervalDuration),
//            kVTCompressionPropertyKey_AllowFrameReordering: kCFBooleanTrue, // !isBaseline as NSObject,
////            kVTCompressionPropertyKey_AllowFrameReordering: !isBaseline as NSObject,
////            kVTCompressionPropertyKey_FieldCount: NSNumber(value: 1),
////            kVTCompressionPropertyKey_MoreFramesBeforeStart: kCFBooleanTrue
////            kVTCompressionPropertyKey_PixelTransferProperties: [
////                "ScalingMode": scalingMode
////            ] as NSObject
//        ]
//
//#if os(OSX)
//        if enabledHardwareEncoder {
//            properties[kVTVideoEncoderSpecification_EncoderID] = "com.apple.videotoolbox.videoencoder.h264.gva" as NSObject
//            properties["EnableHardwareAcceleratedVideoEncoder"] = kCFBooleanTrue
//            properties["RequireHardwareAcceleratedVideoEncoder"] = kCFBooleanTrue
//        }
//#endif
//
////        if dataRateLimits != H264Encoder.defaultDataRateLimits {
////            properties[kVTCompressionPropertyKey_DataRateLimits] = dataRateLimits as NSObject
////        }
////        properties[kVTCompressionPropertyKey_DataRateLimits] = NSArray(array: [Double(bitrate) * 1.5/8, 1])
//////        if !isBaseline {
////            properties[kVTCompressionPropertyKey_H264EntropyMode] = kVTH264EntropyMode_CABAC
//////        }
//        return properties
//    }

    public var pixelBufferPoolAttributes: [NSString: NSObject] {
        var attributes: [NSString: NSObject] = [:]
        attributes[kCVPixelBufferWidthKey] = NSNumber(value: Float(width))
        attributes[kCVPixelBufferHeightKey] = NSNumber(value: Float(height))
        attributes[kCVPixelBufferBytesPerRowAlignmentKey] = NSNumber(value: Float(width * 4))
        attributes[kCVPixelBufferPoolMinimumBufferCountKey] = NSNumber(value: Int(12))
        return attributes
    }
    private var _pixelBufferPool: CVPixelBufferPool?
    private var pixelBufferPool: CVPixelBufferPool! {
        get {
            if _pixelBufferPool == nil {
                var pixelBufferPool: CVPixelBufferPool?
                CVPixelBufferPoolCreate(nil, nil, pixelBufferPoolAttributes as CFDictionary?, &pixelBufferPool)
                _pixelBufferPool = pixelBufferPool
            }
            return _pixelBufferPool!
        }
        set {
            _pixelBufferPool = newValue
        }
    }

    private var callback: VTCompressionOutputCallback = {(
        outputCallbackRefCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?) in
        os_signpost(.begin, log: SignpostLog.encoder, name: "callback")
        if status != noErr {
            print("H264Encoder.callabck bailing because status was error: \(status)")
            return
        }
        guard let refcon: UnsafeMutableRawPointer = outputCallbackRefCon else {
            print("H264Encoder.callback bailing because refcon was nil")
            return
        }
        guard let sampleBuffer: CMSampleBuffer = sampleBuffer else {
            print("H264Encoder.callback bailing because sampleBuffer was nil")
            return
        }
        
//        var newTiming = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: sampleBuffer.duration,
//                                                                           presentationTimeStamp: sampleBuffer.presentationTimeStamp,
//                                                                           decodeTimeStamp: sampleBuffer.presentationTimeStamp),
//                                             count: sampleBuffer.sampleTimingInfo.count)

//        for i in 0..<sampleBuffer.sampleTimingInfo.count {
//            newTiming[i].decodeTimeStamp = decodeTimeStamp
//            newTiming[i].presentationTimeStamp = presentationTimeStamp
//            newTiming[i].duration = CMTime(seconds: delta / 1000, preferredTimescale: 1000000)
//        }

//        var out: CMSampleBuffer?
//        CMSampleBufferCreateCopyWithNewTiming(nil, sampleBuffer, newTiming.count, &newTiming, &out)
        
        
        print("callback sampleBuffer.pts: \(sampleBuffer.presentationTimeStamp.seconds)")
        print("callback sampleBuffer.dts: \(sampleBuffer.decodeTimeStamp.seconds)")
        print("callback sampleBuffer.duration: \(sampleBuffer.duration.seconds)")
        // dumps ALL the details of the frame
//        print("callback CMShow(sampleBuffer):")
//        CFShow(sampleBuffer)

        let encoder: H264Encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        encoder.delegate?.sampleOutput(video: sampleBuffer)
        os_signpost(.end, log: SignpostLog.encoder, name: "callback")
    }

    private var encoderSpec: CFDictionary {
        var spec: [NSString: AnyObject] = [:]
        spec[kVTVideoEncoderSpecification_EncoderID] = "com.apple.videotoolbox.videoencoder.h264" as AnyObject
        // mac os only?
//        spec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = kCFBooleanTrue
//        spec[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = kCFBooleanFalse
        return spec as CFDictionary
    }

    private var _session: VTCompressionSession?
    private var session: VTCompressionSession? {
        get {
            if _session == nil {
                guard VTCompressionSessionCreate(
                    kCFAllocatorDefault,
                    width,
                    height,
                    kCMVideoCodecType_H264,
                    encoderSpec,
                    attributes as CFDictionary?,
                    nil,
                    callback,
                    Unmanaged.passUnretained(self).toOpaque(),
                    &_session
                    ) == noErr else {
//                    logger.warn("create a VTCompressionSessionCreate")
                    return nil
                }
                invalidateSession = false
//                VTCompressionSessionCreate(<#T##allocator: CFAllocator?##CFAllocator?#>,
//                                           <#T##width: Int32##Int32#>,
//                                           <#T##height: Int32##Int32#>,
//                                           <#T##codecType: CMVideoCodecType##CMVideoCodecType#>,
//                                           <#T##encoderSpecification: CFDictionary?##CFDictionary?#>,
//                                           <#T##sourceImageBufferAttributes: CFDictionary?##CFDictionary?#>,
//                                           <#T##compressedDataAllocator: CFAllocator?##CFAllocator?#>,
//                                           <#T##outputCallback: VTCompressionOutputCallback?##VTCompressionOutputCallback?##(UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, OSStatus, VTEncodeInfoFlags, CMSampleBuffer?) -> Void#>,
//                                           <#T##outputCallbackRefCon: UnsafeMutableRawPointer?##UnsafeMutableRawPointer?#>,
//                                           <#T##compressionSessionOut: UnsafeMutablePointer<VTCompressionSession?>##UnsafeMutablePointer<VTCompressionSession?>#>)

//                guard VTSessionSetProperty(_session!, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_3_1) == noErr else {
//                    fatalError()
//                }
//                var result: NSObject? = nil
//                guard VTSessionCopyProperty(_session!, kVTCompressionPropertyKey_ProfileLevel, kCFAllocatorDefault, &result) == noErr else {
//                    fatalError()
//                }
//                print("profileLevel: value: \(String(describing: result))")
//
//                status = VTCompressionSessionPrepareToEncodeFrames(_session!)
//                supportedProperty = _session?.copySupportedPropertyDictionary()

//                status = VTSessionSetProperties(_session!, properties as CFDictionary)
//                var support: CFDictionary? = nil
//                guard VTSessionCopySupportedPropertyDictionary(_session!, &support) == noErr else {
//                    fatalError()
//                }

//                for (key, _) in properties {
//                    var result: NSObject? = nil
//                    VTSessionCopyProperty(_session!, key as CFString, kCFAllocatorDefault, &result)
//                    print("key: \(key), value: \(String(describing: result))")
//                }

//                kVTCompressionPropertyKey_PixelTransferProperties: [
            ////                "ScalingMode": scalingMode
                ////            ] as NSObject

                let pixelTransferProperties: [CFString: CFString] = [kVTPixelTransferPropertyKey_ScalingMode: kVTScalingMode_Trim]
                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_PixelTransferProperties, pixelTransferProperties as NSObject)

                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSInteger(2) as CFTypeRef)
                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_MaxKeyFrameInterval, NSInteger(60) as CFTypeRef)

                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel)
                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_AverageBitRate, NSInteger(1200000) as CFTypeRef)
//              VTSessionSetProperty(_session!, kVTCompressionPropertyKey_AverageBitRate, NSInteger(4000000) as CFTypeRef)
////                NSArray *limit = @[@(_configuration.videoBitRate * 1.5/8), @(1)];

//                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_ExpectedFrameRate, NSInteger(30) as CFTypeRef)
//                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
//                let limit: NSArray = NSArray(array: [NSInteger(468750), NSInteger(1)])
                var cpb_size = Int(468750)
                var max_bitrate_window = Float(1.5)
                let cf_cpb_size = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &cpb_size)
                let cf_max_bitrate_window = CFNumberCreate(kCFAllocatorDefault, CFNumberType.floatType, &max_bitrate_window)

                var arrayCallback = kCFTypeArrayCallBacks
                let rateControl = CFArrayCreateMutable(kCFAllocatorDefault, 2, &arrayCallback)

                CFArrayAppendValue(rateControl, unsafeBitCast(cf_cpb_size, to: UnsafeRawPointer.self))
                CFArrayAppendValue(rateControl, unsafeBitCast(cf_max_bitrate_window, to: UnsafeRawPointer.self))

                // setting DataRateLimits causes the DTS to be invalid
//                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_DataRateLimits, rateControl)

//                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
//                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
//                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)

//                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_VideoEncoderPixelBufferAttributes, pixelBufferPoolAttributes as CFDictionary)

                VTSessionSetProperty(_session!, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC)

                VTCompressionSessionPrepareToEncodeFrames(_session!)
            }
            return _session
        }
        set {
            if let session: VTCompressionSession = _session {
                VTCompressionSessionCompleteFrames(session, kCMTimeInvalid)
                VTCompressionSessionInvalidate(session)
            }
            _session = newValue
        }
    }

    func encodeImageBuffer(_ imageBuffer: CVImageBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        guard running else {
//            print("H264Encoder bailing because not running")
            return
        }
        guard locked == 0 else {
            print("H264Encoder bailing because locked")
            self.frameCount += 1
            return
        }
        if invalidateSession {
            session = nil
        }
        guard let session: VTCompressionSession = session else {
            print("H264Encoder bailing because there is no session")
            return
        }

        let d = CMTime(value: 100, timescale: 3000)
        let p = CMTimeMultiply(d, Int32(self.frameCount))

        var x = imageBuffer
        var flags: VTEncodeInfoFlags = []

        var frameProperties: [NSString: Any] = [:]
        if self.frameCount % 60 == 0 {
            frameProperties[kVTEncodeFrameOptionKey_ForceKeyFrame] = kCFBooleanTrue
            os_signpost(.begin, log: SignpostLog.encoder, name: "encodeFrame", "keyframe")
        } else {
            os_signpost(.begin, log: SignpostLog.encoder, name: "encodeFrame")
        }

//        print("VTCompressionSessionEncodeFrame.pts: \(CMTimeGetSeconds(p))")
//        print("VTCompressionSessionEncodeFrame.dts: \(CMTimeGetSeconds(d))")

        if session.numberOfPendingFrames.intValue > 0 {
            print("pending number of frames is > 0: \(session.numberOfPendingFrames)")
        }
        
//        print(session.debugDescription)

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer, //muted ? lastImageBuffer ?? imageBuffer : imageBuffer,
            p,
            d,
            frameProperties as CFDictionary,
            &x,
            &flags
        )

        if flags.contains(VTEncodeInfoFlags.frameDropped) {
            print("VTCompressionSessionEncodeFrame reported bailing because it dropped a frame")
        }
        os_signpost(.end, log: SignpostLog.encoder, name: "encodeFrame")
//        VTCompressionSessionEncodeFrame(<#T##session: VTCompressionSession##VTCompressionSession#>,
//                                        <#T##imageBuffer: CVImageBuffer##CVImageBuffer#>,
//                                        <#T##presentationTimeStamp: CMTime##CMTime#>,
//                                        <#T##duration: CMTime##CMTime#>,
//                                        <#T##frameProperties: CFDictionary?##CFDictionary?#>,
//                                        <#T##sourceFrameRefCon: UnsafeMutableRawPointer?##UnsafeMutableRawPointer?#>,
//                                        <#T##infoFlagsOut: UnsafeMutablePointer<VTEncodeInfoFlags>?##UnsafeMutablePointer<VTEncodeInfoFlags>?#>)

//        let presentTime = CMTimeMake(Int64(frameCount), 30)
//        let dur = CMTimeMake(1, 30)

//        var now = NSNumber(value: CACurrentMediaTime()*1000)

//        VTCompressionSessionEncodeFrame(
//            session,
//            imageBuffer, //muted ? lastImageBuffer ?? imageBuffer : imageBuffer,
//            presentTime,
//            dur,
//            nil, // properties as CFDictionary,
//            &now,
//            &flags
//        )
        print("H264Encoder frameCount: \(frameCount)")
        self.frameCount += 1
        if !muted {
            lastImageBuffer = imageBuffer
        }
    }

    private func setProperty(_ key: CFString, _ value: CFTypeRef?) {
//        lockQueue.async {
//            guard let session: VTCompressionSession = self._session else {
//                return
//            }
//            self.status = VTSessionSetProperty(
//                session,
//                key,
//                value
//            )
//        }
    }

#if os(iOS)
    @objc func applicationWillEnterForeground(_ notification: Notification) {
        invalidateSession = true
    }
    @objc func didAudioSessionInterruption(_ notification: Notification) {
        guard
            let userInfo: [AnyHashable: Any] = notification.userInfo,
            let value: NSNumber = userInfo[AVAudioSessionInterruptionTypeKey] as? NSNumber,
            let type: AVAudioSessionInterruptionType = AVAudioSessionInterruptionType(rawValue: value.uintValue) else {
            return
        }
        switch type {
        case .ended:
            invalidateSession = true
        default:
            break
        }
    }
#endif
}

extension H264Encoder: Running {
    // MARK: Running
    func startRunning() {
        lockQueue.async {
            self.running = true
#if os(iOS)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.didAudioSessionInterruption),
                name: .AVAudioSessionInterruption,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.applicationWillEnterForeground),
                name: .UIApplicationWillEnterForeground,
                object: nil
            )
#endif
        }
    }

    func stopRunning() {
        lockQueue.async {
            self.session = nil
            self.lastImageBuffer = nil
            self.formatDescription = nil
#if os(iOS)
            NotificationCenter.default.removeObserver(self)
#endif
            self.running = false
            self.frameCount = 0
        }
    }
}
