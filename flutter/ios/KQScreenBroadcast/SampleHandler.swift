import Accelerate
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
  private let appGroupId = "group.com.kunqiong.remotelink"
  private let configDirectoryName = "remoteLink-config"
  private let maxLongEdge = 1920
  private let defaults: UserDefaults?
  private var videoFrameCount = 0
  private var appAudioFrameCount = 0
  private var micAudioFrameCount = 0
  private var transportStarted = false
  private var audioForwardingActive = false
  private var scaledFrame = [UInt8]()
  private var audioConverters = [String: AVAudioConverter]()
  private let outputAudioFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 48_000,
    channels: 2,
    interleaved: true
  )!

  override init() {
    defaults = UserDefaults(suiteName: appGroupId)
    super.init()
  }

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    videoFrameCount = 0
    appAudioFrameCount = 0
    micAudioFrameCount = 0
    transportStarted = false
    audioForwardingActive = false
    audioConverters.removeAll()
    publishStatus(
      state: "started",
      width: 0,
      height: 0,
      transportState: "waiting_for_frame"
    )
  }

  override func broadcastPaused() {
    if transportStarted {
      kq_ios_broadcast_pause()
    }
    publishStatus(
      state: "paused",
      transportState: transportStarted ? "paused" : "waiting_for_frame"
    )
  }

  override func broadcastResumed() {
    if transportStarted {
      kq_ios_broadcast_resume()
    }
    publishStatus(
      state: "resumed",
      transportState: transportStarted ? "ready" : "waiting_for_frame"
    )
  }

  override func broadcastFinished() {
    if transportStarted {
      kq_ios_broadcast_stop()
    }
    transportStarted = false
    audioForwardingActive = false
    audioConverters.removeAll()
    publishStatus(state: "finished", transportState: "stopped")
  }

  override func processSampleBuffer(
    _ sampleBuffer: CMSampleBuffer,
    with sampleBufferType: RPSampleBufferType
  ) {
    switch sampleBufferType {
    case .video:
      videoFrameCount += 1
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        publishFailure(code: "missing_pixel_buffer")
        return
      }

      let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
      guard pixelFormat == kCVPixelFormatType_32BGRA else {
        publishFailure(code: "unsupported_pixel_format")
        return
      }

      let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
      guard lockResult == kCVReturnSuccess else {
        publishFailure(code: "pixel_buffer_lock_failed")
        return
      }
      defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
      }

      let width = CVPixelBufferGetWidth(pixelBuffer)
      let height = CVPixelBufferGetHeight(pixelBuffer)
      let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
      guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        publishFailure(code: "missing_base_address")
        return
      }

      let pushResult = submitVideoFrame(
        baseAddress: baseAddress,
        width: width,
        height: height,
        stride: stride
      )
      guard pushResult == 0 else {
        publishFailure(code: "frame_submit_\(pushResult)")
        return
      }

      if !transportStarted {
        guard let configDirectory = sharedConfigDirectory() else {
          publishFailure(code: "app_group_unavailable")
          return
        }
        let startResult = configDirectory.utf8CString.withUnsafeBufferPointer { buffer in
          guard let baseAddress = buffer.baseAddress else {
            return Int32(1)
          }
          return kq_ios_broadcast_start(
            UnsafeRawPointer(baseAddress).assumingMemoryBound(to: UInt8.self),
            UInt(max(0, buffer.count - 1))
          )
        }
        guard startResult == 0 else {
          publishFailure(code: "transport_start_\(startResult)")
          return
        }
        transportStarted = true
      }

      if videoFrameCount == 1 || videoFrameCount % 30 == 0 {
        publishStatus(
          state: "capturing",
          width: width,
          height: height,
          transportState: "ready"
        )
      }
    case .audioApp:
      appAudioFrameCount += 1
      guard transportStarted else {
        return
      }
      let audioResult = submitApplicationAudio(sampleBuffer)
      if audioResult == 0 {
        audioForwardingActive = true
        if appAudioFrameCount == 1 || appAudioFrameCount % 100 == 0 {
          publishStatus(state: "capturing", transportState: "ready")
        }
      } else if appAudioFrameCount == 1 || appAudioFrameCount % 100 == 0 {
        // Keep video streaming if a device returns an audio format that cannot
        // be converted. The shared status gives the app a useful diagnostic.
        publishStatus(
          state: "capturing",
          transportState: "ready",
          errorCode: "audio_submit_\(audioResult)"
        )
      }
    case .audioMic:
      // Screen-sharing audio is application sound. Microphone audio remains in
      // the existing voice-call channel so the two independent sources do not
      // get mixed twice and create echo for the remote viewer.
      micAudioFrameCount += 1
    @unknown default:
      publishStatus(state: "unknown")
    }
  }

  private func publishStatus(
    state: String,
    width: Int? = nil,
    height: Int? = nil,
    transportState: String? = nil,
    errorCode: String? = nil
  ) {
    guard let defaults = defaults else {
      return
    }
    defaults.set(state, forKey: "kq_broadcast_state")
    defaults.set(videoFrameCount, forKey: "kq_broadcast_video_frames")
    defaults.set(appAudioFrameCount, forKey: "kq_broadcast_app_audio_frames")
    defaults.set(micAudioFrameCount, forKey: "kq_broadcast_mic_audio_frames")
    defaults.set(Date().timeIntervalSince1970, forKey: "kq_broadcast_updated_at")
    defaults.set(
      transportState ?? (transportStarted ? "ready" : "waiting_for_frame"),
      forKey: "kq_broadcast_transport_state"
    )
    let viewerCount = transportStarted
      ? Int(kq_ios_broadcast_active_viewer_count())
      : 0
    defaults.set(viewerCount, forKey: "kq_broadcast_remote_viewer_count")
    defaults.set(viewerCount > 0, forKey: "kq_broadcast_remote_view_available")
    defaults.set(audioForwardingActive, forKey: "kq_broadcast_audio_supported")
    defaults.set(true, forKey: "kq_broadcast_view_only")
    defaults.set(errorCode ?? "", forKey: "kq_broadcast_error_code")
    if let width = width {
      defaults.set(width, forKey: "kq_broadcast_width")
    }
    if let height = height {
      defaults.set(height, forKey: "kq_broadcast_height")
    }
    defaults.synchronize()
  }

  private func submitVideoFrame(
    baseAddress: UnsafeMutableRawPointer,
    width: Int,
    height: Int,
    stride: Int
  ) -> Int32 {
    let target = normalizedVideoSize(width: width, height: height)
    if target.width == width && target.height == height {
      return kq_ios_broadcast_push_bgra(
        baseAddress,
        UInt(stride * height),
        UInt(width),
        UInt(height),
        UInt(stride)
      )
    }

    let targetStride = target.width * 4
    let targetLength = targetStride * target.height
    if scaledFrame.count != targetLength {
      scaledFrame = [UInt8](repeating: 0, count: targetLength)
    }

    return scaledFrame.withUnsafeMutableBytes { output in
      guard let outputBaseAddress = output.baseAddress else {
        return Int32(2)
      }
      var source = vImage_Buffer(
        data: baseAddress,
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: stride
      )
      var destination = vImage_Buffer(
        data: outputBaseAddress,
        height: vImagePixelCount(target.height),
        width: vImagePixelCount(target.width),
        rowBytes: targetStride
      )
      let scaleResult = vImageScale_ARGB8888(
        &source,
        &destination,
        nil,
        vImage_Flags(kvImageHighQualityResampling)
      )
      guard scaleResult == kvImageNoError else {
        return Int32(2)
      }
      return kq_ios_broadcast_push_bgra(
        outputBaseAddress,
        UInt(targetLength),
        UInt(target.width),
        UInt(target.height),
        UInt(targetStride)
      )
    }
  }

  private func submitApplicationAudio(_ sampleBuffer: CMSampleBuffer) -> Int32 {
    guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      return 10
    }
    let inputFormat = AVAudioFormat(cmAudioFormatDescription: description)
    let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
    guard frameCount > 0,
          let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
          ) else {
      return 11
    }
    inputBuffer.frameLength = AVAudioFrameCount(frameCount)
    let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer,
      at: 0,
      frameCount: Int32(frameCount),
      into: inputBuffer.mutableAudioBufferList
    )
    guard copyStatus == 0 else {
      return 12
    }

    let key = "\(inputFormat.sampleRate)-\(inputFormat.channelCount)-\(inputFormat.isInterleaved)-\(inputFormat.commonFormat)"
    guard let converter = audioConverter(for: inputFormat, key: key) else {
      return 13
    }
    let outputCapacity = AVAudioFrameCount(max(
      1,
      Int(ceil(Double(frameCount) * outputAudioFormat.sampleRate / inputFormat.sampleRate)) + 32
    ))
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: outputAudioFormat,
      frameCapacity: outputCapacity
    ) else {
      return 14
    }

    var suppliedInput = false
    var conversionError: NSError?
    let conversionStatus = converter.convert(to: outputBuffer, error: &conversionError) {
      _, inputStatus in
      if suppliedInput {
        inputStatus.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      inputStatus.pointee = .haveData
      return inputBuffer
    }
    guard conversionStatus != .error,
          conversionError == nil,
          outputBuffer.frameLength > 0 else {
      return 15
    }

    let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
    guard let data = audioBuffer.mData,
          audioBuffer.mDataByteSize > 0 else {
      return 16
    }
    let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.stride
    guard sampleCount > 0 && sampleCount % 2 == 0 else {
      return 17
    }
    return kq_ios_broadcast_push_audio_f32(
      data.assumingMemoryBound(to: Float.self),
      UInt(sampleCount)
    )
  }

  private func audioConverter(for inputFormat: AVAudioFormat, key: String) -> AVAudioConverter? {
    if let converter = audioConverters[key] {
      return converter
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: outputAudioFormat) else {
      return nil
    }
    audioConverters[key] = converter
    return converter
  }

  private func normalizedVideoSize(width: Int, height: Int) -> (width: Int, height: Int) {
    let longEdge = max(width, height)
    let scale = longEdge > maxLongEdge
      ? Double(maxLongEdge) / Double(longEdge)
      : 1.0
    var targetWidth = max(2, Int(Double(width) * scale))
    var targetHeight = max(2, Int(Double(height) * scale))
    targetWidth -= targetWidth % 2
    targetHeight -= targetHeight % 2
    return (targetWidth, targetHeight)
  }

  private func publishFailure(code: String) {
    publishStatus(
      state: "failed",
      transportState: "failed",
      errorCode: code
    )
  }

  private func sharedConfigDirectory() -> String? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else {
      return nil
    }
    let directory = container.appendingPathComponent(
      configDirectoryName,
      isDirectory: true
    )
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      return directory.path
    } catch {
      return nil
    }
  }
}
