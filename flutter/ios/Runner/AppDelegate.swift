import UIKit
import Flutter
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, WKNavigationDelegate {
  private var paymentWebView: WKWebView?
  private var paymentResult: FlutterResult?
  private var paymentTimeout: Timer?

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
