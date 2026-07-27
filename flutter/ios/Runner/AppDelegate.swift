import UIKit
import Flutter
import ReplayKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private struct BroadcastConfigSource {
    let directory: URL
    let configFileName: String
    let config2FileName: String
  }

  private enum VoiceCaptureDestination {
    case remoteSession(String)
    case broadcastHost
  }

  private let broadcastExtensionBundleId = "com.kunqiong.remotelink.broadcast"
  private let broadcastAppGroupId = "group.com.kunqiong.remotelink"
  private let broadcastConfigDirectoryName = "remoteLink-config"
  private let broadcastConfigFileName = "鲲穹远程桌面.toml"
  private let broadcastConfig2FileName = "鲲穹远程桌面2.toml"
  private let defaultConfigFileName = "鲲穹远程桌面_default.toml"
  private let defaultConfig2FileName = "鲲穹远程桌面_default2.toml"
  private let legacyConfigFileName = "RustDesk.toml"
  private let legacyConfig2FileName = "RustDesk2.toml"
  private let broadcastUuidFileName = "kq-ios-device-uuid"
  private let sharedDeviceIdFileName = "kq-ios-device-id"
  private let configProfileMigrationMarkerFileName =
    "kq-ios-config-profile-migration-v1"
  private let broadcastStatusFileName = "kq-broadcast-status.json"
  private let voiceCallRequestFileName = "kq-ios-voice-call-request.json"
  private let voiceCallResponseFileName = "kq-ios-voice-call-response.json"
  private let voiceCallStateFileName = "kq-ios-voice-call-state.json"
  private let voiceCallAudioFileName = "kq-ios-voice-call-audio.bin"
  private let voiceCallAudioRecordMagic: UInt32 = 0x4156514B
  private let voiceCallAudioHeaderSize = 16
  private let voiceCallAudioMaxSamples = 11_520
  private let voiceAudioEngine = AVAudioEngine()
  private let voiceAudioQueue = DispatchQueue(
    label: "com.kunqiong.remotelink.voice-audio",
    qos: .userInitiated
  )
  private var voiceCaptureDestination: VoiceCaptureDestination?
  private var voiceAudioSamples = [Float]()
  private var voiceAudioReadIndex = 0
  private var voiceTapInstalled = false
  private let voicePlaybackEngine = AVAudioEngine()
  private let voicePlaybackNode = AVAudioPlayerNode()
  private let voicePlaybackQueue = DispatchQueue(
    label: "com.kunqiong.remotelink.voice-playback",
    qos: .userInitiated
  )
  private var voicePlaybackTimer: DispatchSourceTimer?
  private var voicePlaybackRequestId: String?
  private var voicePlaybackOffset: UInt64 = 0
  private var voicePlaybackPending = Data()
  private var voicePlaybackStartedAt: Date?
  private var voicePlaybackNodeAttached = false
  private var voiceBroadcastCaptureRequestId: String?
  private var voiceInvitationTimer: Timer?
  private var voiceInvitationRequestId: String?
  // ReplayKit may defer starting the upload extension until after its system
  // confirmation UI closes. Keep this picker attached for that handoff.
  private var broadcastPicker: RPSystemBroadcastPickerView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerNativeChannel()
    startIOSVoiceCallInvitationMonitor()
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
      case "get_pending_ios_voice_call":
        self.getPendingIOSVoiceCall(result: result)
      case "respond_to_ios_voice_call":
        self.respondToIOSVoiceCall(arguments: call.arguments, result: result)
      case "get_ios_voice_call_state":
        self.getIOSVoiceCallState(result: result)
      case "end_ios_voice_call":
        self.endIOSVoiceCall(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    withMicrophonePermission { granted in
      result(granted)
    }
  }

  private func withMicrophonePermission(
    completion: @escaping (Bool) -> Void
  ) {
    let session = AVAudioSession.sharedInstance()
    let complete: (Bool) -> Void = { granted in
      DispatchQueue.main.async {
        completion(granted)
      }
    }
    switch session.recordPermission {
    case .granted:
      complete(true)
    case .denied:
      complete(false)
    case .undetermined:
      session.requestRecordPermission { granted in
        complete(granted)
      }
    @unknown default:
      complete(false)
    }
  }

  private func startIOSVoiceCapture(_ sessionId: String) -> Bool {
    let normalizedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSessionId.isEmpty else {
      return false
    }
    return startIOSVoiceCapture(destination: .remoteSession(normalizedSessionId))
  }

  private func startIOSBroadcastHostVoiceCapture() -> Bool {
    startIOSVoiceCapture(destination: .broadcastHost)
  }

  private func startIOSVoiceCapture(destination: VoiceCaptureDestination) -> Bool {
    stopIOSVoiceCapture(deactivateAudioSession: false)
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.defaultToSpeaker, .allowBluetoothHFP]
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
        voiceCaptureDestination = destination
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

  private func stopIOSVoiceCapture(deactivateAudioSession: Bool = true) {
    if voiceTapInstalled {
      voiceAudioEngine.inputNode.removeTap(onBus: 0)
      voiceTapInstalled = false
    }
    voiceAudioEngine.stop()
    voiceAudioQueue.sync {
      voiceCaptureDestination = nil
      voiceAudioSamples.removeAll(keepingCapacity: false)
      voiceAudioReadIndex = 0
    }
    if deactivateAudioSession {
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    }
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

    guard let destination = voiceCaptureDestination else {
      return
    }
    voiceAudioSamples.append(contentsOf: normalized)
    while voiceAudioSamples.count - voiceAudioReadIndex >= 960 {
      let endIndex = voiceAudioReadIndex + 960
      let frame = Array(voiceAudioSamples[voiceAudioReadIndex..<endIndex])
      voiceAudioReadIndex = endIndex
      switch destination {
      case .remoteSession(let sessionId):
        sendIOSVoiceFrame(frame, sessionId: sessionId)
      case .broadcastHost:
        sendIOSHostVoiceFrame(frame)
      }
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

  private func sendIOSHostVoiceFrame(_ frame: [Float]) {
    frame.withUnsafeBufferPointer { framePointer in
      kq_ios_host_voice_call_audio(
        framePointer.baseAddress,
        UInt(framePointer.count)
      )
    }
  }

  private func voiceCallDirectory() -> URL? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: broadcastAppGroupId
    ) else {
      return nil
    }
    return container.appendingPathComponent(
      broadcastConfigDirectoryName,
      isDirectory: true
    )
  }

  private func voiceCallFileURL(_ fileName: String) -> URL? {
    voiceCallDirectory()?.appendingPathComponent(fileName)
  }

  private func readVoiceCallJSON(_ fileName: String) -> [String: Any]? {
    guard let url = voiceCallFileURL(fileName),
          let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data),
          let value = object as? [String: Any] else {
      return nil
    }
    return value
  }

  private func writeVoiceCallJSON(_ value: [String: Any], fileName: String) throws {
    guard let directory = voiceCallDirectory(),
          let url = voiceCallFileURL(fileName) else {
      throw NSError(
        domain: "com.kunqiong.remotelink.voice-call",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "App Group is unavailable"]
      )
    }
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let data = try JSONSerialization.data(withJSONObject: value)
    try data.write(to: url, options: .atomic)
  }

  private func voiceCallNumber(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
  }

  private func pendingIOSVoiceCall() -> [String: Any]? {
    guard let request = readVoiceCallJSON(voiceCallRequestFileName),
          let requestId = request["requestId"] as? String,
          let expiresAt = voiceCallNumber(request["expiresAt"]),
          !requestId.isEmpty else {
      return nil
    }
    if expiresAt <= Date().timeIntervalSince1970 {
      if let url = voiceCallFileURL(voiceCallRequestFileName) {
        try? FileManager.default.removeItem(at: url)
      }
      return nil
    }
    if let response = readVoiceCallJSON(voiceCallResponseFileName),
       response["requestId"] as? String == requestId {
      return nil
    }
    return [
      "requestId": requestId,
      "expiresAt": expiresAt,
    ]
  }

  private func getPendingIOSVoiceCall(result: @escaping FlutterResult) {
    result(pendingIOSVoiceCall())
  }

  private func startIOSVoiceCallInvitationMonitor() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleApplicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    monitorIOSVoiceCallInvitation()
    let timer = Timer(
      timeInterval: 1.0,
      target: self,
      selector: #selector(monitorIOSVoiceCallInvitation),
      userInfo: nil,
      repeats: true
    )
    voiceInvitationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  @objc private func handleApplicationDidBecomeActive() {
    monitorIOSVoiceCallInvitation()
  }

  @objc private func monitorIOSVoiceCallInvitation() {
    guard UIApplication.shared.applicationState == .active,
          voiceInvitationRequestId == nil,
          let pending = pendingIOSVoiceCall(),
          let requestId = pending["requestId"] as? String,
          let presenter = voiceInvitationPresenter(),
          presenter.presentedViewController == nil else {
      return
    }

    voiceInvitationRequestId = requestId
    let alert = UIAlertController(
      title: "语音通话",
      message: "已连接设备请求发起语音通话。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "拒绝", style: .cancel) { [weak self] _ in
      self?.respondToNativeIOSVoiceCall(requestId: requestId, accepted: false)
    })
    alert.addAction(UIAlertAction(title: "接听", style: .default) { [weak self] _ in
      self?.respondToNativeIOSVoiceCall(requestId: requestId, accepted: true)
    })
    presenter.present(alert, animated: true)
  }

  private func voiceInvitationPresenter() -> UIViewController? {
    guard let controller = window?.rootViewController,
          controller.viewIfLoaded?.window != nil else {
      return nil
    }
    return controller
  }

  private func respondToNativeIOSVoiceCall(requestId: String, accepted: Bool) {
    respondToIOSVoiceCall(
      arguments: ["requestId": requestId, "accepted": accepted],
      result: { [weak self] value in
        DispatchQueue.main.async {
          guard let self = self else { return }
          self.voiceInvitationRequestId = nil
          if value as? Bool != true {
            NSLog("Failed to respond to iOS voice call invitation")
          }
        }
      }
    )
  }

  private func respondToIOSVoiceCall(arguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = arguments as? [String: Any],
          let requestId = arguments["requestId"] as? String,
          let accepted = arguments["accepted"] as? Bool,
          isPendingIOSVoiceCallRequest(requestId) else {
      result(false)
      return
    }

    guard accepted else {
      finishIOSVoiceCallResponse(
        requestId: requestId,
        accepted: false,
        result: result
      )
      return
    }

    // The responder is the side that needs the microphone. Request permission
    // here as well as in Flutter so direct native calls cannot establish a
    // silent one-way voice call.
    withMicrophonePermission { [weak self] granted in
      guard let self = self else {
        result(false)
        return
      }
      self.finishIOSVoiceCallResponse(
        requestId: requestId,
        accepted: granted,
        result: result
      )
    }
  }

  private func isPendingIOSVoiceCallRequest(_ requestId: String) -> Bool {
    guard let request = readVoiceCallJSON(voiceCallRequestFileName),
          request["requestId"] as? String == requestId,
          let expiresAt = voiceCallNumber(request["expiresAt"]) else {
      return false
    }
    return expiresAt > Date().timeIntervalSince1970
  }

  private func finishIOSVoiceCallResponse(
    requestId: String,
    accepted: Bool,
    result: @escaping FlutterResult
  ) {
    guard isPendingIOSVoiceCallRequest(requestId) else {
      result(false)
      return
    }
    do {
      try writeVoiceCallJSON([
        "requestId": requestId,
        "accepted": accepted,
        "respondedAt": Date().timeIntervalSince1970,
      ], fileName: voiceCallResponseFileName)
      if accepted {
        startIOSVoicePlayback(requestId: requestId)
      } else {
        stopIOSVoicePlayback()
      }
      result(true)
    } catch {
      NSLog("Failed to write iOS voice call response: \(error)")
      result(false)
    }
  }

  private func getIOSVoiceCallState(result: @escaping FlutterResult) {
    guard let state = readVoiceCallJSON(voiceCallStateFileName),
          state["active"] as? Bool == true,
          let requestId = state["requestId"] as? String,
          !requestId.isEmpty else {
      result(false)
      return
    }
    result(true)
  }

  private func endIOSVoiceCall(result: @escaping FlutterResult) {
    voicePlaybackQueue.async { [weak self] in
      guard let self = self,
            let state = self.readVoiceCallJSON(self.voiceCallStateFileName),
            state["active"] as? Bool == true else {
        DispatchQueue.main.async { result(false) }
        return
      }
      self.stopIOSVoicePlaybackLocked(deactivateAudioSession: true)
      let ended = kq_ios_host_voice_call_end()
      DispatchQueue.main.async { result(ended) }
    }
  }

  private func startIOSVoicePlayback(requestId: String) {
    voicePlaybackQueue.async { [weak self] in
      guard let self = self else { return }
      self.stopIOSVoicePlaybackLocked(deactivateAudioSession: false)
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
        if !self.voicePlaybackNodeAttached {
          self.voicePlaybackEngine.attach(self.voicePlaybackNode)
          self.voicePlaybackEngine.connect(
            self.voicePlaybackNode,
            to: self.voicePlaybackEngine.mainMixerNode,
            format: nil
          )
          self.voicePlaybackNodeAttached = true
        }
        self.voicePlaybackEngine.prepare()
        try self.voicePlaybackEngine.start()
      } catch {
        NSLog("Failed to start iOS voice playback: \(error)")
        return
      }
      self.voicePlaybackRequestId = requestId
      self.voicePlaybackOffset = 0
      self.voicePlaybackPending.removeAll(keepingCapacity: true)
      self.voicePlaybackStartedAt = Date()
      let timer = DispatchSource.makeTimerSource(queue: self.voicePlaybackQueue)
      timer.schedule(deadline: .now(), repeating: .milliseconds(20))
      timer.setEventHandler { [weak self] in
        self?.drainIOSVoicePlaybackAudio()
      }
      self.voicePlaybackTimer = timer
      timer.resume()
    }
  }

  private func stopIOSVoicePlayback() {
    voicePlaybackQueue.async { [weak self] in
      self?.stopIOSVoicePlaybackLocked(deactivateAudioSession: true)
    }
  }

  private func stopIOSVoicePlaybackLocked(deactivateAudioSession: Bool) {
    voicePlaybackTimer?.setEventHandler {}
    voicePlaybackTimer?.cancel()
    voicePlaybackTimer = nil
    voicePlaybackNode.stop()
    voicePlaybackEngine.stop()
    voicePlaybackRequestId = nil
    voicePlaybackOffset = 0
    voicePlaybackPending.removeAll(keepingCapacity: false)
    voicePlaybackStartedAt = nil
    if voiceBroadcastCaptureRequestId != nil {
      stopIOSVoiceCapture(deactivateAudioSession: false)
      voiceBroadcastCaptureRequestId = nil
    }
    if deactivateAudioSession {
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    }
  }

  private func drainIOSVoicePlaybackAudio() {
    guard let requestId = voicePlaybackRequestId else {
      return
    }
    if let state = readVoiceCallJSON(voiceCallStateFileName),
       state["requestId"] as? String == requestId,
       state["active"] as? Bool == true {
      if voiceBroadcastCaptureRequestId != requestId,
         startIOSBroadcastHostVoiceCapture() {
        voiceBroadcastCaptureRequestId = requestId
      }
    } else if let state = readVoiceCallJSON(voiceCallStateFileName),
              state["requestId"] as? String == requestId,
              state["active"] as? Bool == false {
      stopIOSVoicePlaybackLocked(deactivateAudioSession: true)
      return
    }
    if let startedAt = voicePlaybackStartedAt,
       Date().timeIntervalSince(startedAt) > 10,
       readVoiceCallJSON(voiceCallStateFileName) == nil {
      stopIOSVoicePlaybackLocked(deactivateAudioSession: true)
      return
    }
    guard let audioURL = voiceCallFileURL(voiceCallAudioFileName),
          let data = try? Data(contentsOf: audioURL) else {
      return
    }
    if UInt64(data.count) < voicePlaybackOffset {
      voicePlaybackOffset = 0
      voicePlaybackPending.removeAll(keepingCapacity: true)
    }
    if UInt64(data.count) > voicePlaybackOffset {
      voicePlaybackPending.append(
        data.subdata(in: Int(voicePlaybackOffset)..<data.count)
      )
      voicePlaybackOffset = UInt64(data.count)
    }
    while voicePlaybackPending.count >= voiceCallAudioHeaderSize {
      let magic = readVoiceCallUInt32(voicePlaybackPending, offset: 0)
      let sampleRate = readVoiceCallUInt32(voicePlaybackPending, offset: 4)
      let channels = Int(readVoiceCallUInt16(voicePlaybackPending, offset: 8))
      let sampleCount = Int(readVoiceCallUInt32(voicePlaybackPending, offset: 12))
      guard magic == voiceCallAudioRecordMagic,
            sampleRate > 0,
            channels >= 1,
            channels <= 2,
            sampleCount > 0,
            sampleCount <= voiceCallAudioMaxSamples,
            sampleCount % channels == 0 else {
        voicePlaybackPending.removeAll(keepingCapacity: true)
        return
      }
      let byteCount = sampleCount * MemoryLayout<UInt32>.size
      let recordLength = voiceCallAudioHeaderSize + byteCount
      guard voicePlaybackPending.count >= recordLength else {
        return
      }
      var samples = [Float]()
      samples.reserveCapacity(sampleCount)
      for index in 0..<sampleCount {
        let offset = voiceCallAudioHeaderSize + index * MemoryLayout<UInt32>.size
        samples.append(Float(bitPattern: readVoiceCallUInt32(voicePlaybackPending, offset: offset)))
      }
      voicePlaybackPending.removeSubrange(0..<recordLength)
      scheduleIOSVoicePlayback(
        samples: samples,
        sampleRate: Double(sampleRate),
        channels: channels
      )
    }
  }

  private func readVoiceCallUInt32(_ data: Data, offset: Int) -> UInt32 {
    UInt32(data[offset]) |
      UInt32(data[offset + 1]) << 8 |
      UInt32(data[offset + 2]) << 16 |
      UInt32(data[offset + 3]) << 24
  }

  private func readVoiceCallUInt16(_ data: Data, offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
  }

  private func scheduleIOSVoicePlayback(
    samples: [Float],
    sampleRate: Double,
    channels: Int
  ) {
    let frameCount = samples.count / channels
    guard frameCount > 0,
          let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
          ),
          let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
          ),
          let channelData = buffer.floatChannelData else {
      return
    }
    buffer.frameLength = AVAudioFrameCount(frameCount)
    for frame in 0..<frameCount {
      for channel in 0..<channels {
        channelData[channel][frame] = samples[frame * channels + channel]
      }
    }
    voicePlaybackNode.scheduleBuffer(buffer)
    if !voicePlaybackNode.isPlaying {
      voicePlaybackNode.play()
    }
  }

  private func showBroadcastPicker(result: @escaping FlutterResult) {
#if targetEnvironment(simulator)
    result(FlutterError(
      code: "ios_simulator_unavailable",
      message: "ReplayKit broadcast picker is unavailable in iOS Simulator.",
      details: nil
    ))
#else
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let rootView = self.window?.rootViewController?.view else {
        result(false)
        return
      }

      self.broadcastPicker?.removeFromSuperview()
      let picker = RPSystemBroadcastPickerView(frame: .zero)
      picker.preferredExtension = self.broadcastExtensionBundleId
      picker.showsMicrophoneButton = false
      picker.isAccessibilityElement = false
      picker.translatesAutoresizingMaskIntoConstraints = false
      self.broadcastPicker = picker
      rootView.addSubview(picker)
      rootView.bringSubviewToFront(picker)
      NSLayoutConstraint.activate([
        picker.widthAnchor.constraint(equalToConstant: 44),
        picker.heightAnchor.constraint(equalToConstant: 44),
        picker.trailingAnchor.constraint(
          equalTo: rootView.safeAreaLayoutGuide.trailingAnchor,
          constant: -24
        ),
        picker.topAnchor.constraint(
          equalTo: rootView.safeAreaLayoutGuide.topAnchor,
          constant: 12
        ),
      ])
      rootView.layoutIfNeeded()

      DispatchQueue.main.async { [weak self, weak picker] in
        guard let self = self, let picker = picker else {
          result(false)
          return
        }
        guard let button = self.findBroadcastPickerButton(in: picker) else {
          self.removeBroadcastPicker(picker)
          result(false)
          return
        }

        button.sendActions(for: .allTouchEvents)
        result(true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak picker] in
          guard let self = self, let picker = picker else { return }
          self.removeBroadcastPicker(picker)
        }
      }
    }
#endif
  }

  private func findBroadcastPickerButton(in view: UIView) -> UIButton? {
    if let button = view as? UIButton {
      return button
    }
    for subview in view.subviews {
      if let button = findBroadcastPickerButton(in: subview) {
        return button
      }
    }
    return nil
  }

  private func removeBroadcastPicker(_ picker: RPSystemBroadcastPickerView) {
    picker.removeFromSuperview()
    if broadcastPicker === picker {
      broadcastPicker = nil
    }
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
      let legacyDirectory: URL?
      if let values = arguments as? [String: Any],
         let legacyPath = values["legacyDir"] as? String,
         !legacyPath.isEmpty {
        legacyDirectory = URL(fileURLWithPath: legacyPath, isDirectory: true)
      } else {
        legacyDirectory = nil
      }
      try migrateBroadcastConfiguration(from: legacyDirectory, to: destination)
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

  private func migrateBroadcastConfiguration(from source: URL?, to destination: URL) throws {
    let fileManager = FileManager.default
    let canonicalConfig = destination.appendingPathComponent(broadcastConfigFileName)
    let migrationMarker = destination.appendingPathComponent(
      configProfileMigrationMarkerFileName
    )
    guard !fileManager.fileExists(atPath: migrationMarker.path) else {
      try synchronizeSharedIdentityFiles(from: source, to: destination)
      return
    }

    var candidates = [BroadcastConfigSource]()
    // Existing versions can leave the main app on this custom-client profile
    // while ReplayKit uses the unsuffixed profile. Prefer the active main-app
    // profile once, then use the stable unsuffixed name in both processes.
    candidates.append(BroadcastConfigSource(
      directory: destination,
      configFileName: defaultConfigFileName,
      config2FileName: defaultConfig2FileName
    ))
    if let source,
       source.path != destination.path {
      candidates.append(BroadcastConfigSource(
        directory: source,
        configFileName: defaultConfigFileName,
        config2FileName: defaultConfig2FileName
      ))
      candidates.append(BroadcastConfigSource(
        directory: source,
        configFileName: broadcastConfigFileName,
        config2FileName: broadcastConfig2FileName
      ))
      candidates.append(BroadcastConfigSource(
        directory: source,
        configFileName: legacyConfigFileName,
        config2FileName: legacyConfig2FileName
      ))
    }
    candidates.append(BroadcastConfigSource(
      directory: destination,
      configFileName: legacyConfigFileName,
      config2FileName: legacyConfig2FileName
    ))

    guard let selected = candidates.first(where: { candidate in
      fileManager.fileExists(
        atPath: candidate.directory
          .appendingPathComponent(candidate.configFileName)
          .path
      )
    }) else {
      if fileManager.fileExists(atPath: canonicalConfig.path) {
        try synchronizeSharedIdentityFiles(from: source, to: destination)
        try Data("1".utf8).write(to: migrationMarker, options: .atomic)
      }
      return
    }

    func copy(_ sourceName: String, to destinationName: String, required: Bool) throws -> Bool {
      let sourceFile = selected.directory.appendingPathComponent(sourceName)
      let destinationFile = destination.appendingPathComponent(destinationName)
      if sourceFile.path == destinationFile.path {
        return true
      }
      if fileManager.fileExists(atPath: sourceFile.path) {
        if fileManager.fileExists(atPath: destinationFile.path) {
          try fileManager.removeItem(at: destinationFile)
        }
        try fileManager.copyItem(at: sourceFile, to: destinationFile)
        return true
      }
      if required {
        return false
      }
      if destinationName == broadcastConfig2FileName,
         fileManager.fileExists(atPath: destinationFile.path) {
        try fileManager.removeItem(at: destinationFile)
      }
      return true
    }

    guard try copy(selected.configFileName, to: broadcastConfigFileName, required: true) else {
      return
    }
    _ = try copy(selected.config2FileName, to: broadcastConfig2FileName, required: false)
    _ = try copy(broadcastUuidFileName, to: broadcastUuidFileName, required: false)
    _ = try copy(sharedDeviceIdFileName, to: sharedDeviceIdFileName, required: false)
    try synchronizeSharedIdentityFiles(from: source, to: destination)
    try Data("1".utf8).write(to: migrationMarker, options: .atomic)
    NSLog("[Config Migration] Unified iOS config profile from \(selected.configFileName)")
  }

  private func synchronizeSharedIdentityFiles(from source: URL?, to destination: URL) throws {
    guard let source, source.path != destination.path else {
      return
    }
    let fileManager = FileManager.default
    for fileName in [broadcastUuidFileName, sharedDeviceIdFileName] {
      let target = destination.appendingPathComponent(fileName)
      guard !fileManager.fileExists(atPath: target.path) else {
        continue
      }
      let legacy = source.appendingPathComponent(fileName)
      guard fileManager.fileExists(atPath: legacy.path) else {
        continue
      }
      try fileManager.copyItem(at: legacy, to: target)
    }
  }

  public func dummyMethodToEnforceBundling() {
      dummy_method_to_enforce_bundling();
    session_get_rgba(nil, 0);
  }
}
