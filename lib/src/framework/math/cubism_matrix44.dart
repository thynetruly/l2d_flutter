import 'dart:typed_data';

import 'cubism_math.dart';

/// 4x4 matrix for 2D/3D transformations (column-major storage).
///
/// Ported from Framework/src/Math/CubismMatrix44.hpp.
///
/// Storage layout (column-major):
/// ```
/// [0]  [4]  [8]   [12]
/// [1]  [5]  [9]   [13]
/// [2]  [6]  [10]  [14]
/// [3]  [7]  [11]  [15]
/// ```
class CubismMatrix44 {
  final Float32List _tr = Float32List(16);

  CubismMatrix44() {
    loadIdentity();
  }

  /// Direct access to the underlying 16-element array.
  Float32List get array => _tr;

  /// Sets the matrix to the identity matrix.
  void loadIdentity() {
    for (int i = 0; i < 16; i++) {
      _tr[i] = 0.0;
    }
    _tr[0] = 1.0;
    _tr[5] = 1.0;
    _tr[10] = 1.0;
    _tr[15] = 1.0;
  }

  /// Copies 16 float values from [src] into this matrix.
  void setMatrix(Float32List src) {
    for (int i = 0; i < 16; i++) {
      _tr[i] = src[i];
    }
  }

  double get scaleX => _tr[0];
  double get scaleY => _tr[5];
  double get translateX => _tr[12];
  double get translateY => _tr[13];

  /// Applies the X-axis transformation to [src].
  double transformX(double src) => _tr[0] * src + _tr[12];

  /// Applies the Y-axis transformation to [src].
  double transformY(double src) => _tr[5] * src + _tr[13];

  /// Inverse X-axis transformation.
  double invertTransformX(double src) => (src - _tr[12]) / _tr[0];

  /// Inverse Y-axis transformation.
  double invertTransformY(double src) => (src - _tr[13]) / _tr[5];

  /// Translates by relative amounts [x] and [y].
  void translateRelative(double x, double y) {
    final tr1 = Float32List(16);
    _setIdentity(tr1);
    tr1[12] = x;
    tr1[13] = y;
    multiply(tr1, _tr, _tr);
  }

  /// Sets absolute translation to [x] and [y].
  void translate(double x, double y) {
    _tr[12] = x;
    _tr[13] = y;
  }

  /// Sets absolute X translation.
  void translateXTo(double x) => _tr[12] = x;

  /// Sets absolute Y translation.
  void translateYTo(double y) => _tr[13] = y;

  /// Scales by relative factors [x] and [y].
  void scaleRelative(double x, double y) {
    final tr1 = Float32List(16);
    _setIdentity(tr1);
    tr1[0] = x;
    tr1[5] = y;
    multiply(tr1, _tr, _tr);
  }

  /// Sets absolute scale to [x] and [y].
  void scale(double x, double y) {
    _tr[0] = x;
    _tr[5] = y;
  }

  /// Multiplies this matrix by [m]: `this = m * this`.
  void multiplyByMatrix(CubismMatrix44 m) {
    multiply(m._tr, _tr, _tr);
  }

  /// Calculates the inverse of this matrix.
  ///
  /// Returns identity matrix if the determinant is too small.
  CubismMatrix44 getInvert() {
    // Extract 3x3 rotation part
    final r00 = _tr[0], r10 = _tr[1], r20 = _tr[2];
    final r01 = _tr[4], r11 = _tr[5], r21 = _tr[6];
    final r02 = _tr[8], r12 = _tr[9], r22 = _tr[10];

    // Extract translation
    final tx = _tr[12], ty = _tr[13], tz = _tr[14];

    // Calculate 3x3 determinant
    final det = r00 * (r11 * r22 - r12 * r21) -
        r01 * (r10 * r22 - r12 * r20) +
        r02 * (r10 * r21 - r11 * r20);

    final result = CubismMatrix44();
    if (CubismMath.absF(det) < CubismMath.epsilon) {
      return result; // Return identity
    }

    // Cofactor matrix / determinant
    final inv00 = (r11 * r22 - r12 * r21) / det;
    final inv01 = -(r01 * r22 - r02 * r21) / det;
    final inv02 = (r01 * r12 - r02 * r11) / det;
    final inv10 = -(r10 * r22 - r12 * r20) / det;
    final inv11 = (r00 * r22 - r02 * r20) / det;
    final inv12 = -(r00 * r12 - r02 * r10) / det;
    final inv20 = (r10 * r21 - r11 * r20) / det;
    final inv21 = -(r00 * r21 - r01 * r20) / det;
    final inv22 = (r00 * r11 - r01 * r10) / det;

    final dst = result._tr;
    dst[0] = inv00;  dst[1] = inv10;  dst[2] = inv20;  dst[3] = 0.0;
    dst[4] = inv01;  dst[5] = inv11;  dst[6] = inv21;  dst[7] = 0.0;
    dst[8] = inv02;  dst[9] = inv12;  dst[10] = inv22; dst[11] = 0.0;
    dst[12] = -(inv00 * tx + inv01 * ty + inv02 * tz);
    dst[13] = -(inv10 * tx + inv11 * ty + inv12 * tz);
    dst[14] = -(inv20 * tx + inv21 * ty + inv22 * tz);
    dst[15] = 1.0;

    return result;
  }

  /// Multiplies two 4x4 matrices: `dst = a * b`.
  ///
  /// [dst] may alias [a] or [b] (handled via temporary copy).
  static void multiply(Float32List a, Float32List b, Float32List dst) {
    final c = Float32List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        c[j + i * 4] = a[0 + i * 4] * b[j + 0 * 4] +
            a[1 + i * 4] * b[j + 1 * 4] +
            a[2 + i * 4] * b[j + 2 * 4] +
            a[3 + i * 4] * b[j + 3 * 4];
      }
    }
    for (int i = 0; i < 16; i++) {
      dst[i] = c[i];
    }
  }

  static void _setIdentity(Float32List m) {
    for (int i = 0; i < 16; i++) {
      m[i] = 0.0;
    }
    m[0] = 1.0;
    m[5] = 1.0;
    m[10] = 1.0;
    m[15] = 1.0;
  }
}
