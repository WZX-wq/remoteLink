import Accelerate
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
  private var scaledFrame = [UInt8]()

  override init() {
    defaults = UserDefaults(suiteName: appGroupId)
    super.init()
  }

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    videoFrameCount = 0
    appAudioFrameCount = 0
    micAudioFrameCount = 0
    transportStarted = false
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
    case .audioApp, .audioMic:
      // The broadcast transport currently carries video only. Do not expose
      // captured audio as if a remote device could hear it.
      break
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
    defaults.set(false, forKey: "kq_broadcast_remote_view_available")
    defaults.set(false, forKey: "kq_broadcast_audio_supported")
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
