import 'dart:ffi';

import '../generated/cubism_core_bindings.dart';
import 'native_library.dart';

/// Singleton providing access to Cubism Core version info and logging.
class CubismCore {
  CubismCore._();

  static CubismCoreBindings get _bindings => NativeLibrary.bindings;

  /// Returns the Cubism Core library version as a packed integer.
  ///
  /// The version is encoded as: (major << 24) | (minor << 16) | patch.
  static int get version => _bindings.csmGetVersion();

  /// Returns the version as a human-readable "major.minor.patch" string.
  static String get versionString {
    final v = version;
    final major = (v >> 24) & 0xFF;
    final minor = (v >> 16) & 0xFF;
    final patch = v & 0xFFFF;
    return '$major.$minor.$patch';
  }

  /// Returns the latest MOC file format version supported by this Core.
  static int get latestMocVersion => _bindings.csmGetLatestMocVersion();

  /// Gets the MOC file format version from raw moc data.
  static int getMocVersion(Pointer<Void> address, int size) {
    return _bindings.csmGetMocVersion(address, size);
  }

  /// Checks consistency of moc data.
  ///
  /// Returns `true` if the moc data is valid, `false` otherwise.
  /// The [address] must be aligned to 64 bytes (csmAlignofMoc).
  static bool hasMocConsistency(Pointer<Void> address, int size) {
    return _bindings.csmHasMocConsistency(address, size) == 1;
  }

  /// Sets the native log handler callback.
  static void setLogFunction(csmLogFunction handler) {
    _bindings.csmSetLogFunction(handler);
  }

  /// Gets the current native log handler, or nullptr if none is set.
  static csmLogFunction getLogFunction() {
    return _bindings.csmGetLogFunction();
  }
}
