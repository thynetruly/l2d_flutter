import 'cubism_matrix44.dart';

/// Model matrix for positioning and scaling a Live2D model.
///
/// Ported from Framework/src/Math/CubismModelMatrix.hpp.
class CubismModelMatrix extends CubismMatrix44 {
  final double _width;
  final double _height;

  CubismModelMatrix(double w, double h)
      : _width = w,
        _height = h {
    setHeight(2.0);
  }

  /// Scales model to fit width [w], maintaining aspect ratio.
  void setWidth(double w) {
    final scaleX = w / _width;
    scale(scaleX, scaleX);
  }

  /// Scales model to fit height [h], maintaining aspect ratio.
  void setHeight(double h) {
    final scaleX = h / _height;
    scale(scaleX, scaleX);
  }

  /// Sets absolute position.
  void setPosition(double x, double y) => translate(x, y);

  /// Centers the model at ([x], [y]).
  void setCenterPosition(double x, double y) {
    centerX(x);
    centerY(y);
  }

  /// Positions top edge at [y].
  void top(double y) => setY(y);

  /// Positions bottom edge at [y].
  void bottom(double y) {
    final h = _height * scaleY;
    translateYTo(y - h);
  }

  /// Positions left edge at [x].
  void left(double x) => setX(x);

  /// Positions right edge at [x].
  void right(double x) {
    final w = _width * scaleX;
    translateXTo(x - w);
  }

  /// Centers horizontally at [x].
  void centerX(double x) {
    final w = _width * scaleX;
    translateXTo(x - (w / 2.0));
  }

  /// Sets left edge X position.
  void setX(double x) => translateXTo(x);

  /// Centers vertically at [y].
  void centerY(double y) {
    final h = _height * scaleY;
    translateYTo(y - (h / 2.0));
  }

  /// Sets top edge Y position.
  void setY(double y) => translateYTo(y);

  /// Applies layout configuration from a key-value map.
  ///
  /// Supported keys: "width", "height", "x", "y", "center_x", "center_y",
  /// "top", "bottom", "left", "right".
  void setupFromLayout(Map<String, double> layout) {
    // First pass: width/height must be processed first
    final w = layout['width'];
    if (w != null) setWidth(w);

    final h = layout['height'];
    if (h != null) setHeight(h);

    // Second pass: position
    for (final entry in layout.entries) {
      switch (entry.key) {
        case 'x':
          setX(entry.value);
        case 'y':
          setY(entry.value);
        case 'center_x':
          centerX(entry.value);
        case 'center_y':
          centerY(entry.value);
        case 'top':
          top(entry.value);
        case 'bottom':
          bottom(entry.value);
        case 'left':
          left(entry.value);
        case 'right':
          right(entry.value);
      }
    }
  }
}
