import 'dart:ffi';
import 'dart:io';

/// FFI bindings to libm — the C standard math library.
///
/// Provides float-precision (`cosf`/`sinf`/`atan2f`/`sqrtf`/`cbrtf`/etc.)
/// and double-precision (`acos`/`cbrt`) math functions to achieve **bit-exact**
/// parity with the C++ Cubism Framework.
///
/// The C++ Cubism Framework uses libm functions throughout (`csmFloat32 cosf(x)`,
/// `csmFloat32 sinf(x)`, etc.). Dart's `dart:math` is double-precision; even
/// truncating its results to float32 via [Float32List] does not produce the same
/// bit pattern as C++'s `cosf`, because the underlying double-precision cos and
/// the float-precision cosf can differ in the last ULP.
///
/// By calling libm via FFI, Dart uses the **same** math library that the C++
/// Cubism Core library uses on the same platform. Same library = same bits =
/// bit-identical results.
///
/// Platform notes:
/// - Linux: opens `libm.so.6` (glibc).
/// - Android: math functions live in libc; resolved via process symbols.
/// - macOS / iOS: math functions live in libSystem; resolved via process symbols.
/// - Windows: prefers `ucrtbase.dll` (UCRT), falls back to legacy `msvcrt.dll`.
///
/// Cross-platform note: glibc, Apple's libSystem, MSVCRT, and bionic all
/// implement `cosf`/`sinf`/etc. independently. They can differ in the last ULP.
/// This means **Dart-on-Linux ≡ C++-on-Linux** and **Dart-on-macOS ≡ C++-on-macOS**,
/// but Dart-on-Linux may differ from Dart-on-macOS in the last bit. This is the
/// same behavior as C++ itself — bit-exact within a platform, near-exact across
/// platforms.
class LibM {
  LibM._();

  static DynamicLibrary? _lib;
  static DynamicLibrary get _libm => _lib ??= _open();

  static DynamicLibrary _open() {
    if (Platform.isLinux) {
      return DynamicLibrary.open('libm.so.6');
    }
    if (Platform.isAndroid) {
      // Bionic merged libm into libc; symbols are accessible via process.
      try {
        return DynamicLibrary.open('libm.so');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
    if (Platform.isMacOS || Platform.isIOS) {
      // libSystem is always loaded; math functions are part of it.
      return DynamicLibrary.process();
    }
    if (Platform.isWindows) {
      // Modern UCRT first, legacy MSVCRT fallback.
      try {
        return DynamicLibrary.open('ucrtbase.dll');
      } catch (_) {
        return DynamicLibrary.open('msvcrt.dll');
      }
    }
    throw UnsupportedError(
      'libm not available on platform: ${Platform.operatingSystem}',
    );
  }

  // -------------------------------------------------------------------------
  // Float-precision functions (single-precision IEEE 754 binary32)
  //
  // These match the C++ Cubism Framework's csmFloat32 function calls exactly.
  // The Dart Float32 → Dart Float32 signature ensures the FFI marshalling
  // truncates to single-precision on input and reads single-precision on output.
  //
  // `isLeaf: true` is safe on every libm function below — they are pure
  // numeric routines with no callbacks into Dart and no heap access. Adding
  // the hint drops the Dart→native transition cost by roughly half (measured
  // at ~150 ns → ~75 ns per call on Linux x86_64 — see benchmark/math/
  // transcendentals.dart and the Tier-1 decision in docs/PERFORMANCE.md).
  // -------------------------------------------------------------------------

  /// Single-precision cosine. Matches C `cosf(float)`.
  static final double Function(double) cosf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('cosf', isLeaf: true);

  /// Single-precision sine. Matches C `sinf(float)`.
  static final double Function(double) sinf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('sinf', isLeaf: true);

  /// Single-precision tangent. Matches C `tanf(float)`.
  static final double Function(double) tanf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('tanf', isLeaf: true);

  /// Single-precision arc-tangent of y/x. Matches C `atan2f(float, float)`.
  static final double Function(double, double) atan2f = _libm.lookupFunction<
      Float Function(Float, Float),
      double Function(double, double)>('atan2f', isLeaf: true);

  /// Single-precision square root. Matches C `sqrtf(float)`.
  static final double Function(double) sqrtf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('sqrtf', isLeaf: true);

  /// Single-precision cube root. Matches C `cbrtf(float)`.
  ///
  /// Note: the C++ Cubism Cardano solver uses `cbrt` (double) intentionally,
  /// not `cbrtf`. Use [cbrt] for that path; this function is provided for
  /// completeness.
  static final double Function(double) cbrtf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('cbrtf', isLeaf: true);

  /// Single-precision arc-cosine. Matches C `acosf(float)`.
  ///
  /// Note: the C++ Cubism Cardano solver uses `acos` (double) intentionally,
  /// not `acosf`. Use [acos] for that path; this function is provided for
  /// completeness.
  static final double Function(double) acosf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('acosf', isLeaf: true);

  /// Single-precision arc-sine. Matches C `asinf(float)`.
  static final double Function(double) asinf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('asinf', isLeaf: true);

  /// Single-precision absolute value. Matches C `fabsf(float)`.
  static final double Function(double) fabsf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('fabsf', isLeaf: true);

  /// Single-precision floating-point modulo. Matches C `fmodf(float, float)`.
  static final double Function(double, double) fmodf = _libm.lookupFunction<
      Float Function(Float, Float),
      double Function(double, double)>('fmodf', isLeaf: true);

  /// Single-precision floor. Matches C `floorf(float)`.
  static final double Function(double) floorf = _libm.lookupFunction<
      Float Function(Float),
      double Function(double)>('floorf', isLeaf: true);

  /// Single-precision power. Matches C `powf(float, float)`.
  static final double Function(double, double) powf = _libm.lookupFunction<
      Float Function(Float, Float),
      double Function(double, double)>('powf', isLeaf: true);

  // -------------------------------------------------------------------------
  // Double-precision functions
  //
  // These exist because the C++ Cubism Framework's Cardano solver intentionally
  // uses `acos()` and `cbrt()` (double-precision) for stability, then truncates
  // the result to csmFloat32 on assignment. Dart must do exactly the same to
  // achieve bit-exact parity.
  //
  // `isLeaf: true` applies here too — same purity argument as the float-
  // precision functions.
  // -------------------------------------------------------------------------

  /// Double-precision arc-cosine. Matches C `acos(double)`.
  ///
  /// Used by the Cardano solver (matches C++ exactly).
  static final double Function(double) acos = _libm.lookupFunction<
      Double Function(Double),
      double Function(double)>('acos', isLeaf: true);

  /// Double-precision cube root. Matches C `cbrt(double)`.
  ///
  /// Used by the Cardano solver (matches C++ exactly).
  static final double Function(double) cbrt = _libm.lookupFunction<
      Double Function(Double),
      double Function(double)>('cbrt', isLeaf: true);

  /// Allows test injection of a custom DynamicLibrary (for unit testing only).
  static void overrideLibrary(DynamicLibrary lib) => _lib = lib;
}
