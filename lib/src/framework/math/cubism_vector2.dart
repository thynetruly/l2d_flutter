import 'dart:math' as math;

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
  double get length => math.sqrt(x * x + y * y);

  /// Returns the distance from this vector to [other].
  double distanceTo(CubismVector2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Dot product with [other].
  double dot(CubismVector2 other) => (x * other.x) + (y * other.y);

  /// Normalizes this vector in place.
  void normalize() {
    final len = math.pow(x * x + y * y, 0.5);
    x = x / len;
    y = y / len;
  }

  /// Returns a normalized copy of this vector.
  CubismVector2 normalized() {
    final len = math.pow(x * x + y * y, 0.5);
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
