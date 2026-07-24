import UIKit
import Flutter
import ReplayKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let broadcastExtensionBundleId = "com.kunqiong.remotelink.broadcast"
  private let broadcastAppGroupId = "group.com.kunqiong.remotelink"
  private let broadcastConfigDirectoryName = "remoteLink-config"
  private let broadcastStatusFileName = "kq-broadcast-status.json"
  private let voiceAudioEngine = AVAudioEngine()
  private let voiceAudioQueue = DispatchQueue(
    label: "com.kunqiong.remotelink.voice-audio",
    qos: .userInitiated
  )
  private var voiceSessionId: String?
  private var voiceAudioSamples = [Float]()
  private var voiceAudioReadIndex = 0
  private var voiceTapInstalled = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerNativeChannel()
    dummyMethodToEnforceBundling();
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerNativeChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(name: "mChannel", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "show_broadcast_picker":
        self.showBroadcastPicker(result: result)
      case "get_broadcast_status":
        self.getBroadcastStatus(result: result)
      case "prepare_broadcast_config_dir":
        self.prepareBroadcastConfigDirectory(
          arguments: call.arguments,
          result: result
        )
      case "request_microphone_permission":
        self.requestMicrophonePermission(result: result)
      case "start_ios_voice_capture":
        result(self.startIOSVoiceCapture(call.arguments as? String ?? ""))
      case "stop_ios_voice_capture":
        self.stopIOSVoiceCapture()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    switch session.recordPermission {
    case .granted:
      result(true)
    case .denied:
      result(false)
    case .undetermined:
      session.requestRecordPermission { granted in
        DispatchQueue.main.async {
          result(granted)
        }
      }
    @unknown default:
      result(false)
    }
  }

  private func startIOSVoiceCapture(_ sessionId: String) -> Bool {
    let normalizedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSessionId.isEmpty else {
      return false
    }

    stopIOSVoiceCapture()
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.defaultToSpeaker, .allowBluetooth]
      )
      try audioSession.setPreferredSampleRate(48_000)
      try audioSession.setActive(true)

      let inputNode = voiceAudioEngine.inputNode
      let format = inputNode.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        stopIOSVoiceCapture()
        return false
      }

      voiceAudioQueue.sync {
        voiceSessionId = normalizedSessionId
        voiceAudioSamples.removeAll(keepingCapacity: true)
        voiceAudioReadIndex = 0
      }

      inputNode.installTap(
        onBus: 0,
        bufferSize: 960,
        format: format
      ) { [weak self] buffer, _ in
        self?.enqueueIOSVoiceBuffer(buffer, sampleRate: format.sampleRate)
      }
      voiceTapInstalled = true
      voiceAudioEngine.prepare()
      try voiceAudioEngine.start()
      return true
    } catch {
      NSLog("Failed to start iOS voice capture: \(error)")
      stopIOSVoiceCapture()
      return false
    }
  }

  private func stopIOSVoiceCapture() {
    if voiceTapInstalled {
      voiceAudioEngine.inputNode.removeTap(onBus: 0)
      voiceTapInstalled = false
    }
    voiceAudioEngine.stop()
    voiceAudioQueue.sync {
      voiceSessionId = nil
      voiceAudioSamples.removeAll(keepingCapacity: false)
      voiceAudioReadIndex = 0
    }
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }

  private func enqueueIOSVoiceBuffer(
    _ buffer: AVAudioPCMBuffer,
    sampleRate: Double
  ) {
    guard let channelData = buffer.floatChannelData else {
      return
    }
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameCount > 0, channelCount > 0 else {
      return
    }

    var mono = [Float](repeating: 0, count: frameCount)
    for frame in 0..<frameCount {
      var value: Float = 0
      for channel in 0..<channelCount {
        value += channelData[channel][frame]
      }
      mono[frame] = value / Float(channelCount)
    }

    voiceAudioQueue.async { [weak self] in
      self?.processIOSVoiceSamples(mono, sampleRate: sampleRate)
    }
  }

  private func processIOSVoiceSamples(
    _ mono: [Float],
    sampleRate: Double
  ) {
    let normalized: [Float]
    if abs(sampleRate - 48_000) < 1 {
      normalized = mono
    } else {
      let outputCount = max(1, Int(Double(mono.count) * 48_000 / sampleRate))
      normalized = (0..<outputCount).map { index in
        let sourcePosition = Double(index) * sampleRate / 48_000
        let lower = min(Int(sourcePosition), mono.count - 1)
        let upper = min(lower + 1, mono.count - 1)
        let fraction = Float(sourcePosition - Double(lower))
        return mono[lower] + (mono[upper] - mono[lower]) * fraction
      }
    }

    guard let sessionId = voiceSessionId else {
      return
    }
    voiceAudioSamples.append(contentsOf: normalized)
    while voiceAudioSamples.count - voiceAudioReadIndex >= 960 {
      let endIndex = voiceAudioReadIndex + 960
      let frame = Array(voiceAudioSamples[voiceAudioReadIndex..<endIndex])
      voiceAudioReadIndex = endIndex
      sendIOSVoiceFrame(frame, sessionId: sessionId)
    }
    if voiceAudioReadIndex >= 9_600 {
      voiceAudioSamples.removeFirst(voiceAudioReadIndex)
      voiceAudioReadIndex = 0
    }
  }

  private func sendIOSVoiceFrame(_ frame: [Float], sessionId: String) {
    let sessionBytes = Array(sessionId.utf8)
    sessionBytes.withUnsafeBufferPointer { sessionPointer in
      frame.withUnsafeBufferPointer { framePointer in
        kq_ios_voice_call_audio(
          sessionPointer.baseAddress,
          UInt(sessionPointer.count),
          framePointer.baseAddress,
          UInt(framePointer.count)
        )
      }
    }
  }

  private func showBroadcastPicker(result: @escaping FlutterResult) {
    guard let rootView = window?.rootViewController?.view else {
      result(false)
      return
    }

    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    picker.preferredExtension = broadcastExtensionBundleId
    picker.showsMicrophoneButton = false
    picker.alpha = 0.01
    picker.isAccessibilityElement = false
    rootView.addSubview(picker)

    for subview in picker.subviews {
      if let button = subview as? UIButton {
        button.sendActions(for: .touchUpInside)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          picker.removeFromSuperview()
        }
        result(true)
        return
      }
    }

    picker.removeFromSuperview()
    result(false)
  }

  private func getBroadcastStatus(result: @escaping FlutterResult) {
    let defaultsStatus = broadcastStatusFromDefaults()
    let fileStatus = loadBroadcastStatusFile()
    let selectedStatus = selectNewestBroadcastStatus(
      defaultsStatus,
      fileStatus
    )
    result(normalizeBroadcastStatus(selectedStatus))
  }

  private func broadcastStatusFromDefaults() -> [String: Any]? {
    guard let defaults = UserDefaults(suiteName: broadcastAppGroupId) else {
      return nil
    }
    return [
      "state": defaults.string(forKey: "kq_broadcast_state") ?? "not_started",
      "videoFrames": defaults.integer(forKey: "kq_broadcast_video_frames"),
      "appAudioFrames": defaults.integer(forKey: "kq_broadcast_app_audio_frames"),
      "micAudioFrames": defaults.integer(forKey: "kq_broadcast_mic_audio_frames"),
      "width": defaults.integer(forKey: "kq_broadcast_width"),
      "height": defaults.integer(forKey: "kq_broadcast_height"),
      "updatedAt": defaults.double(forKey: "kq_broadcast_updated_at"),
      "transportState": defaults.string(forKey: "kq_broadcast_transport_state") ?? "not_started",
      "registrationState": defaults.integer(forKey: "kq_broadcast_registration_state"),
      "remoteViewAvailable": defaults.bool(forKey: "kq_broadcast_remote_view_available"),
      "remoteViewerCount": defaults.integer(forKey: "kq_broadcast_remote_viewer_count"),
      "deviceId": defaults.string(forKey: "kq_broadcast_device_id") ?? "",
      "audioSupported": defaults.bool(forKey: "kq_broadcast_audio_supported"),
      "viewOnly": defaults.object(forKey: "kq_broadcast_view_only") == nil
        ? true
        : defaults.bool(forKey: "kq_broadcast_view_only"),
      "errorCode": defaults.string(forKey: "kq_broadcast_error_code") ?? "",
    ]
  }

  private func loadBroadcastStatusFile() -> [String: Any]? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: broadcastAppGroupId
    ) else {
      return nil
    }
    let url = container.appendingPathComponent(broadcastStatusFileName)
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data),
          let status = object as? [String: Any] else {
      return nil
    }
    return status
  }

  private func selectNewestBroadcastStatus(
    _ defaultsStatus: [String: Any]?,
    _ fileStatus: [String: Any]?
  ) -> [String: Any]? {
    guard let defaultsStatus = defaultsStatus else { return fileStatus }
    guard let fileStatus = fileStatus else { return defaultsStatus }
    let defaultsUpdatedAt = defaultsStatus["updatedAt"] as? Double ?? 0
    let fileUpdatedAt = fileStatus["updatedAt"] as? Double ?? 0
    return fileUpdatedAt > defaultsUpdatedAt ? fileStatus : defaultsStatus
  }

  private func normalizeBroadcastStatus(_ status: [String: Any]?) -> [String: Any] {
    guard let status = status else {
      return [
        "state": "unavailable",
        "videoFrames": 0,
        "appAudioFrames": 0,
        "micAudioFrames": 0,
        "width": 0,
        "height": 0,
        "updatedAt": 0.0,
        "isFresh": false,
        "transportState": "unavailable",
        "registrationState": 0,
        "remoteViewAvailable": false,
        "remoteViewerCount": 0,
        "deviceId": "",
        "audioSupported": false,
        "viewOnly": true,
        "errorCode": "app_group_unavailable",
      ]
    }
    let updatedAt = status["updatedAt"] as? Double ?? 0
    var normalized = status
    normalized["isFresh"] = updatedAt > 0 &&
      Date().timeIntervalSince1970 - updatedAt < 5.0
    return normalized
  }

  private func prepareBroadcastConfigDirectory(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: broadcastAppGroupId
    ) else {
      result(FlutterError(
        code: "app_group_unavailable",
        message: "无法准备屏幕共享配置，请检查应用安装状态。",
        details: nil
      ))
      return
    }

    let destination = container.appendingPathComponent(
      broadcastConfigDirectoryName,
      isDirectory: true
    )
    let fileManager = FileManager.default
    do {
      try fileManager.createDirectory(
        at: destination,
        withIntermediateDirectories: true
      )
      if let values = arguments as? [String: Any],
         let legacyPath = values["legacyDir"] as? String,
         !legacyPath.isEmpty {
        try migrateBroadcastConfiguration(
          from: URL(fileURLWithPath: legacyPath, isDirectory: true),
          to: destination
        )
      }
      result(destination.path)
    } catch {
      NSLog("Failed to prepare broadcast config directory: \(error)")
      result(FlutterError(
        code: "config_migration_failed",
        message: "屏幕共享配置准备失败，请重新打开应用后再试。",
        details: nil
      ))
    }
  }

  private func migrateBroadcastConfiguration(from source: URL, to destination: URL) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: source.path) else {
      return
    }
    for item in try fileManager.contentsOfDirectory(
      at: source,
      includingPropertiesForKeys: nil
    ) {
      let target = destination.appendingPathComponent(item.lastPathComponent)
      guard !fileManager.fileExists(atPath: target.path) else {
        continue
      }
      try fileManager.copyItem(at: item, to: target)
    }
  }

  public func dummyMethodToEnforceBundling() {
      dummy_method_to_enforce_bundling();
    session_get_rgba(nil, 0);
  }
}
