import 'dart:typed_data';

/// Utility for emulating single-precision (float32) arithmetic in Dart.
///
/// The upstream Cubism Framework uses `float` (32-bit) throughout its math
/// operations. Dart's `double` is 64-bit, so naive translations produce
/// results that differ from C++ at the ~1e-7 level (float32 epsilon).
///
/// For exact behavioral parity with C++, intermediate results can be
/// truncated to float32 precision using [cast]. This is especially important
/// when:
/// - Comparing against C++ golden reference data
/// - Writing results that will be read back (precision loss accumulates)
/// - Running iterative simulations where rounding mode matters
///
/// Usage:
/// ```dart
/// final x = Float32.cast(value * CubismMath.pi);
/// final y = Float32.cast(0.5 - 0.5 * Float32.cast(math.cos(x)));
/// ```
///
/// Note: Dart's `Float32List` storage automatically truncates on write,
/// so any code using `Float32List` for intermediate storage already has
/// float32 semantics (see [CubismMatrix44]).
class Float32 {
  Float32._();

  // Single-element scratch buffer. Not thread-safe but Dart is single-isolate.
  static final Float32List _buf = Float32List(1);

  /// Truncates [v] to float32 precision and returns it as a double.
  ///
  /// This is equivalent to `(float)v` in C++, except that the result is
  /// stored back into a double for further computation.
  static double cast(double v) {
    _buf[0] = v;
    return _buf[0];
  }
}
