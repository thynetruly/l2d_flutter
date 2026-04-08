import 'dart:typed_data';

import 'cubism_matrix44.dart';

/// View matrix with boundary constraints for camera/viewport control.
///
/// Ported from Framework/src/Math/CubismViewMatrix.hpp.
class CubismViewMatrix extends CubismMatrix44 {
  double _screenLeft = 0.0;
  double _screenRight = 0.0;
  double _screenTop = 0.0;
  double _screenBottom = 0.0;
  double _maxLeft = 0.0;
  double _maxRight = 0.0;
  double _maxTop = 0.0;
  double _maxBottom = 0.0;
  double maxScale = 0.0;
  double minScale = 0.0;

  double get screenLeft => _screenLeft;
  double get screenRight => _screenRight;
  double get screenBottom => _screenBottom;
  double get screenTop => _screenTop;
  double get maxLeft => _maxLeft;
  double get maxRight => _maxRight;
  double get maxBottom => _maxBottom;
  double get maxTop => _maxTop;

  bool get isMaxScale => scaleX >= maxScale;
  bool get isMinScale => scaleX <= minScale;

  void setScreenRect(double left, double right, double bottom, double top) {
    _screenLeft = left;
    _screenRight = right;
    _screenTop = top;
    _screenBottom = bottom;
  }

  void setMaxScreenRect(double left, double right, double bottom, double top) {
    _maxLeft = left;
    _maxRight = right;
    _maxTop = top;
    _maxBottom = bottom;
  }

  /// Adjusts translation with boundary constraints.
  void adjustTranslate(double x, double y) {
    final tr = array;

    // X-axis constraint
    if (tr[0] * _maxLeft + (tr[12] + x) > _screenLeft) {
      x = _screenLeft - tr[0] * _maxLeft - tr[12];
    }
    if (tr[0] * _maxRight + (tr[12] + x) < _screenRight) {
      x = _screenRight - tr[0] * _maxRight - tr[12];
    }

    // Y-axis constraint
    if (tr[5] * _maxTop + (tr[13] + y) < _screenTop) {
      y = _screenTop - tr[5] * _maxTop - tr[13];
    }
    if (tr[5] * _maxBottom + (tr[13] + y) > _screenBottom) {
      y = _screenBottom - tr[5] * _maxBottom - tr[13];
    }

    // Apply via matrix multiplication
    CubismMatrix44.multiply(
      Float32List.fromList([
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, 0, 1,
      ]),
      tr,
      tr,
    );
  }

  /// Adjusts scaling around center point ([cx], [cy]) with min/max constraints.
  void adjustScale(double cx, double cy, double scaleFactor) {
    final tr = array;
    var targetScale = scaleFactor * tr[0];

    if (targetScale < minScale) {
      if (tr[0] > 0.0) scaleFactor = minScale / tr[0];
    }
    if (targetScale > maxScale) {
      if (tr[0] > 0.0) scaleFactor = maxScale / tr[0];
    }

    // Translate to center -> scale -> translate back
    final tr1 = Float32List.fromList([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      cx, cy, 0, 1,
    ]);
    final tr2 = Float32List.fromList([
      scaleFactor, 0, 0, 0,
      0, scaleFactor, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    final tr3 = Float32List.fromList([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      -cx, -cy, 0, 1,
    ]);

    CubismMatrix44.multiply(tr3, tr, tr);
    CubismMatrix44.multiply(tr2, tr, tr);
    CubismMatrix44.multiply(tr1, tr, tr);
  }
}
