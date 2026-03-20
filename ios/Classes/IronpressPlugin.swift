import Flutter
import UIKit

/// Minimal plugin registration. All actual work is done via dart:ffi
/// directly to the statically linked Rust library.
public class IronpressPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // No method channel needed — we use dart:ffi exclusively.
        // This class exists only to satisfy Flutter's plugin registration.
    }
}
