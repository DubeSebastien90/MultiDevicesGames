import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // engineBridge is the FlutterViewController in the implicit-engine path.
    guard let messenger = engineBridge as? FlutterBinaryMessenger else { return }
    let channel = FlutterMethodChannel(
      name: "com.multidevicesgames/display_metrics",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getPhysicalScreenInfo":
        self?.handleDisplayMetrics(result: result)
      case "getDeviceInfo":
        self?.handleDeviceInfo(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// What kind of device this is, for features that only exist on some of them.
  ///
  /// [idiom] rather than the model identifier because the simulator reports its
  /// host architecture — 'arm64' — where a device reports 'iPhone17,1', so a
  /// prefix test on the model would call every simulator an iPad and the one
  /// place this is used would go untested.
  private func handleDeviceInfo(result: FlutterResult) {
    let idiom: String
    switch UIDevice.current.userInterfaceIdiom {
    case .phone: idiom = "phone"
    case .pad: idiom = "pad"
    default: idiom = "other"
    }
    // Major only. The callers ask "is this at least iOS 17", and parsing the
    // whole version string in Dart to answer that invites the usual mistakes
    // with '17.10' sorting below '17.9'.
    let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    result(["idiom": idiom, "systemMajor": major])
  }

  private func handleDisplayMetrics(result: FlutterResult) {
    let screen = UIScreen.main
    // nativeBounds is always in portrait, regardless of current orientation.
    let widthPx = Int(screen.nativeBounds.width)
    let heightPx = Int(screen.nativeBounds.height)
    let modelId = Self.deviceModelId()

    if let ppi = Self.ppiTable[modelId] {
      result([
        "widthPx": widthPx,
        "heightPx": heightPx,
        "xdpi": ppi,
        "ydpi": ppi,
        "source": "ios_lookup",
        "trusted": true,
      ])
    } else {
      // Unknown model: return data but mark untrusted so Dart falls back to
      // the Flutter density-bucket estimate.
      result([
        "widthPx": widthPx,
        "heightPx": heightPx,
        "xdpi": Double(screen.scale) * 163.0,
        "ydpi": Double(screen.scale) * 163.0,
        "source": "density_bucket",
        "trusted": false,
      ])
    }
  }

  private static func deviceModelId() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
  }

  // Known panel PPI per device model identifier. Add new models as they ship;
  // unknown models fall back to the Flutter density-bucket estimate gracefully.
  private static let ppiTable: [String: Double] = [
    // iPhone 16 family
    "iPhone17,1": 460, "iPhone17,2": 460, "iPhone17,3": 460, "iPhone17,4": 460,
    // iPhone 15 family
    "iPhone16,1": 460, "iPhone16,2": 460, "iPhone15,4": 460, "iPhone15,5": 460,
    // iPhone 14 family
    "iPhone15,2": 460, "iPhone15,3": 460, "iPhone14,7": 460, "iPhone14,8": 460,
    // iPhone 13 family
    "iPhone14,2": 460, "iPhone14,3": 458, "iPhone14,4": 476, "iPhone14,5": 460,
    // iPhone 12 family
    "iPhone13,1": 476, "iPhone13,2": 460, "iPhone13,3": 460, "iPhone13,4": 458,
    // iPhone 11 family
    "iPhone12,1": 326, "iPhone12,3": 458, "iPhone12,5": 458,
    // iPhone X / XS / XR
    "iPhone10,3": 458, "iPhone10,6": 458,
    "iPhone11,2": 458, "iPhone11,4": 458, "iPhone11,6": 458, "iPhone11,8": 326,
    // iPhone 8 / 8 Plus
    "iPhone10,1": 326, "iPhone10,4": 326, "iPhone10,2": 401, "iPhone10,5": 401,
    // iPhone SE
    "iPhone12,8": 326, "iPhone14,6": 326,
  ]
}
