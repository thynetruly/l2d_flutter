/// Canvas information for a Cubism model.
class CubismCanvas {
  /// Canvas width in pixels.
  final double width;

  /// Canvas height in pixels.
  final double height;

  /// Origin X position in pixels.
  final double originX;

  /// Origin Y position in pixels.
  final double originY;

  /// Pixels per unit scale factor.
  final double pixelsPerUnit;

  const CubismCanvas({
    required this.width,
    required this.height,
    required this.originX,
    required this.originY,
    required this.pixelsPerUnit,
  });

  @override
  String toString() =>
      'CubismCanvas(${width}x$height, origin=($originX,$originY), ppu=$pixelsPerUnit)';
}
