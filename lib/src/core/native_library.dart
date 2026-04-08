import 'dart:ffi';
import 'dart:io';

import '../generated/cubism_core_bindings.dart';

/// Singleton access to the Cubism Core native library and its FFI bindings.
class NativeLibrary {
  NativeLibrary._();

  static CubismCoreBindings? _bindings;

  /// The FFI bindings instance, lazily initialized on first access.
  static CubismCoreBindings get bindings {
    _bindings ??= CubismCoreBindings(_openLibrary());
    return _bindings!;
  }

  /// Opens the platform-appropriate native library.
  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libLive2DCubismCore.so');
    }
    if (Platform.isIOS) {
      // iOS uses static linking; symbols are in the main process.
      return DynamicLibrary.process();
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libLive2DCubismCore.dylib');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('Live2DCubismCore.dll');
    }
    throw UnsupportedError(
      'Unsupported platform: ${Platform.operatingSystem}',
    );
  }

  /// Allows injecting a custom [DynamicLibrary] for testing or custom loading.
  static void overrideBindings(CubismCoreBindings bindings) {
    _bindings = bindings;
  }

  /// Resets the bindings to force re-initialization on next access.
  static void reset() {
    _bindings = null;
  }
}
