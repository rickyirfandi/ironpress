import 'dart:ffi';
import 'dart:io';

const String _libName = 'ironpress';

/// Load the native library for the current platform.
///
/// Throws [UnsupportedError] if the current platform is not supported.
/// Throws [StateError] with actionable message if the library cannot be loaded.
DynamicLibrary loadNativeLibrary() {
  if (Platform.isAndroid) {
    return _tryOpen(
      'lib$_libName.so',
      'Android',
      'Ensure the Rust .so is included in your APK\'s jniLibs.',
    );
  }

  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }

  if (Platform.isMacOS) {
    return _tryOpen(
      'lib$_libName.dylib',
      'macOS',
      'Run the Rust build script and ensure the .dylib is bundled via CocoaPods.',
    );
  }

  if (Platform.isLinux) {
    return _tryOpen(
      'lib$_libName.so',
      'Linux',
      'Run the Rust build script and place the .so next to your executable.',
    );
  }

  if (Platform.isWindows) {
    return _tryOpen(
      '$_libName.dll',
      'Windows',
      'Run the Rust build script and place the .dll next to your executable.',
    );
  }

  throw UnsupportedError(
    'ironpress: unsupported platform ${Platform.operatingSystem}',
  );
}

DynamicLibrary _tryOpen(String name, String platform, String hint) {
  try {
    return DynamicLibrary.open(name);
  } catch (e) {
    throw StateError(
      'ironpress: failed to load native library "$name" on $platform.\n'
      '$hint\n'
      'Original error: $e',
    );
  }
}
