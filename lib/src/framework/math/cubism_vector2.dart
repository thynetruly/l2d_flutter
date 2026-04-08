import 'libm.dart';

/// 2D vector for math operations.
///
/// Ported from Framework/src/Math/CubismVector2.hpp.
class CubismVector2 {
  double x;
  double y;

  CubismVector2([this.x = 0.0, this.y = 0.0]);

  /// Creates a copy of this vector.
  CubismVector2 copy() => CubismVector2(x, y);

  CubismVector2 operator +(CubismVector2 other) =>
      CubismVector2(x + other.x, y + other.y);

  CubismVector2 operator -(CubismVector2 other) =>
      CubismVector2(x - other.x, y - other.y);

  CubismVector2 operator *(double scalar) =>
      CubismVector2(x * scalar, y * scalar);

  CubismVector2 operator /(double scalar) =>
      CubismVector2(x / scalar, y / scalar);

  /// Returns the length (magnitude) of this vector.
  ///
  /// Uses [LibM.sqrtf] for bit-exact parity with C++ `sqrtf`.
  double get length => LibM.sqrtf(x * x + y * y);

  /// Returns the distance from this vector to [other].
  ///
  /// Uses [LibM.sqrtf] for bit-exact parity with C++ `sqrtf`.
  double distanceTo(CubismVector2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return LibM.sqrtf(dx * dx + dy * dy);
  }

  /// Dot product with [other].
  double dot(CubismVector2 other) => (x * other.x) + (y * other.y);

  /// Normalizes this vector in place.
  ///
  /// Matches C++ exactly: `powf((X*X)+(Y*Y), 0.5f)` (NOT `sqrtf`).
  /// While mathematically equivalent, `powf` and `sqrtf` may produce different
  /// bit patterns in libm, so we use `powf` to match C++ bit-for-bit.
  void normalize() {
    final len = LibM.powf(x * x + y * y, 0.5);
    x = x / len;
    y = y / len;
  }

  /// Returns a normalized copy of this vector.
  ///
  /// Matches C++ exactly via `powf`. Note: the C++ Cubism Framework only has a
  /// `Normalize()` method (in-place); this Dart-only `normalized()` returns a
  /// new vector using the same formula.
  CubismVector2 normalized() {
    final len = LibM.powf(x * x + y * y, 0.5);
    return CubismVector2(x / len, y / len);
  }

  @override
  bool operator ==(Object other) =>
      other is CubismVector2 && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CubismVector2($x, $y)';
}
