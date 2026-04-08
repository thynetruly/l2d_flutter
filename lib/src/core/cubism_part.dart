import 'dart:ffi';

/// A named part on a Cubism model.
///
/// Parts are logical groupings of drawables (e.g., "body", "hair_front").
/// Each part has an ID string and a mutable [opacity] value.
class CubismPart {
  /// The part's string ID.
  final String id;

  /// Index of this part within the model.
  final int index;

  /// Index of this part's parent part, or -1 if it has no parent.
  final int parentPartIndex;

  /// Pointer to the opacities buffer in native memory.
  final Pointer<Float> _opacitiesPointer;

  CubismPart({
    required this.id,
    required this.index,
    required this.parentPartIndex,
    required Pointer<Float> opacitiesPointer,
  }) : _opacitiesPointer = opacitiesPointer;

  /// Current opacity of this part (0.0 = invisible, 1.0 = fully visible).
  double get opacity => _opacitiesPointer[index];

  /// Sets the opacity, clamped to [0.0..1.0].
  set opacity(double v) {
    _opacitiesPointer[index] = v.clamp(0.0, 1.0);
  }

  /// Whether this part has a parent part.
  bool get hasParent => parentPartIndex >= 0;

  @override
  String toString() => 'CubismPart($id: opacity=$opacity)';
}
