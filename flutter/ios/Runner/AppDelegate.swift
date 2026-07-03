import UIKit
import Flutter
import WebKit
import ReplayKit

@main
@objc class AppDelegate: FlutterAppDelegate, WKNavigationDelegate {
  private var paymentWebView: WKWebView?
  private var paymentResult: FlutterResult?
  private var paymentTimeout: Timer?
  private let broadcastExtensionBundleId = "com.kunqiong.remotelink.broadcast"
  private let broadcastAppGroupId = "group.com.kunqiong.remotelink"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerPaymentChannel()
    dummyMethodToEnforceBundling();
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerPaymentChannel() {
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
      case "open_alipay_html":
        self.openAlipayHtml(call.arguments as? String ?? "", result: result)
      case "open_payment_uri":
        self.openPaymentUri(call.arguments as? String ?? "", result: result)
      case "show_broadcast_picker":
        self.showBroadcastPicker(result: result)
      case "get_broadcast_status":
        self.getBroadcastStatus(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func openAlipayHtml(_ html: String, result: @escaping FlutterResult) {
    let checkoutHtml = html.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !checkoutHtml.isEmpty else {
      result(false)
      return
    }

    finishPaymentHandoff(opened: false)
    paymentResult = result

    guard let rootView = window?.rootViewController?.view else {
      finishPaymentHandoff(opened: false)
      return
    }

    let configuration = WKWebViewConfiguration()
    configuration.preferences.javaScriptEnabled = true
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
    webView.navigationDelegate = self
    webView.alpha = 0.01
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.accessibilityElementsHidden = true
    rootView.addSubview(webView)
    paymentWebView = webView
    paymentTimeout = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
      self?.finishPaymentHandoff(opened: false)
    }
    webView.loadHTMLString(checkoutHtml, baseURL: URL(string: "https://openapi.alipay.com/"))
  }

  private func openPaymentUri(_ value: String, result: @escaping FlutterResult) {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: text) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
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
    guard let defaults = UserDefaults(suiteName: broadcastAppGroupId) else {
      result([
        "state": "unavailable",
        "videoFrames": 0,
        "appAudioFrames": 0,
        "micAudioFrames": 0,
        "width": 0,
        "height": 0,
        "updatedAt": 0.0,
        "isFresh": false,
      ])
      return
    }

    let updatedAt = defaults.double(forKey: "kq_broadcast_updated_at")
    result([
      "state": defaults.string(forKey: "kq_broadcast_state") ?? "not_started",
      "videoFrames": defaults.integer(forKey: "kq_broadcast_video_frames"),
      "appAudioFrames": defaults.integer(forKey: "kq_broadcast_app_audio_frames"),
      "micAudioFrames": defaults.integer(forKey: "kq_broadcast_mic_audio_frames"),
      "width": defaults.integer(forKey: "kq_broadcast_width"),
      "height": defaults.integer(forKey: "kq_broadcast_height"),
      "updatedAt": updatedAt,
      "isFresh": updatedAt > 0 && Date().timeIntervalSince1970 - updatedAt < 5.0,
    ])
  }

  private func finishPaymentHandoff(opened: Bool) {
    paymentTimeout?.invalidate()
    paymentTimeout = nil
    paymentWebView?.navigationDelegate = nil
    paymentWebView?.stopLoading()
    paymentWebView?.removeFromSuperview()
    paymentWebView = nil
    if let result = paymentResult {
      paymentResult = nil
      result(opened)
    }
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.allow)
      return
    }
    let scheme = (url.scheme ?? "").lowercased()
    if scheme.isEmpty || scheme == "http" || scheme == "https" || scheme == "about" {
      decisionHandler(.allow)
      return
    }
    decisionHandler(.cancel)
    UIApplication.shared.open(url, options: [:]) { [weak self] opened in
      self?.finishPaymentHandoff(opened: opened)
    }
  }
    
  public func dummyMethodToEnforceBundling() {
      dummy_method_to_enforce_bundling();
    session_get_rgba(nil, 0);
  }
}
