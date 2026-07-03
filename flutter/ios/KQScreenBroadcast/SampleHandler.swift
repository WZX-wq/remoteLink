import CoreMedia
import CoreVideo
import Foundation
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
  private let appGroupId = "group.com.kunqiong.remotelink"
  private let defaults: UserDefaults?
  private var videoFrameCount = 0
  private var appAudioFrameCount = 0
  private var micAudioFrameCount = 0

  override init() {
    defaults = UserDefaults(suiteName: appGroupId)
    super.init()
  }

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    videoFrameCount = 0
    appAudioFrameCount = 0
    micAudioFrameCount = 0
    publishStatus(state: "started", width: 0, height: 0)
  }

  override func broadcastPaused() {
    publishStatus(state: "paused")
  }

  override func broadcastResumed() {
    publishStatus(state: "resumed")
  }

  override func broadcastFinished() {
    publishStatus(state: "finished")
  }

  override func processSampleBuffer(
    _ sampleBuffer: CMSampleBuffer,
    with sampleBufferType: RPSampleBufferType
  ) {
    switch sampleBufferType {
    case .video:
      videoFrameCount += 1
      guard videoFrameCount == 1 || videoFrameCount % 30 == 0 else {
        return
      }
      if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        publishStatus(
          state: "capturing",
          width: CVPixelBufferGetWidth(pixelBuffer),
          height: CVPixelBufferGetHeight(pixelBuffer)
        )
      } else {
        publishStatus(state: "capturing", width: 0, height: 0)
      }
    case .audioApp:
      appAudioFrameCount += 1
      publishStatus(state: "capturing")
    case .audioMic:
      micAudioFrameCount += 1
      publishStatus(state: "capturing")
    @unknown default:
      publishStatus(state: "unknown")
    }
  }

  private func publishStatus(
    state: String,
    width: Int? = nil,
    height: Int? = nil
  ) {
    guard let defaults = defaults else {
      return
    }
    defaults.set(state, forKey: "kq_broadcast_state")
    defaults.set(videoFrameCount, forKey: "kq_broadcast_video_frames")
    defaults.set(appAudioFrameCount, forKey: "kq_broadcast_app_audio_frames")
    defaults.set(micAudioFrameCount, forKey: "kq_broadcast_mic_audio_frames")
    defaults.set(Date().timeIntervalSince1970, forKey: "kq_broadcast_updated_at")
    if let width = width {
      defaults.set(width, forKey: "kq_broadcast_width")
    }
    if let height = height {
      defaults.set(height, forKey: "kq_broadcast_height")
    }
    defaults.synchronize()
  }
}
