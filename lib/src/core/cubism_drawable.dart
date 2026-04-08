import 'dart:ffi';
import 'dart:typed_data';

import '../generated/cubism_core_bindings.dart';

/// Blend mode for a drawable.
enum CubismBlendMode {
  normal,
  additive,
  multiplicative,
}

/// A drawable mesh on a Cubism model.
///
/// Drawables represent the individual mesh elements that compose the model's
/// visual appearance. Each drawable has vertices, UVs, triangle indices,
/// a texture reference, blend mode, opacity, and optional clipping masks.
///
/// Dynamic properties (opacity, vertex positions, flags) are queried from
/// the native model on each access, reflecting the latest [CubismModel.update]
/// results.
class CubismDrawable {
  /// The drawable's string ID.
  final String id;

  /// Index of this drawable within the model.
  final int index;

  /// Constant flags (blend additive, multiplicative, double-sided, inverted mask).
  final int constantFlags;

  /// Texture index this drawable references.
  final int textureIndex;

  /// Parent part index for this drawable.
  final int parentPartIndex;

  // Pointers to native model for dynamic data queries
  final Pointer<csmModel> _model;
  final CubismCoreBindings _bindings;

  CubismDrawable({
    required this.id,
    required this.index,
    required this.constantFlags,
    required this.textureIndex,
    required this.parentPartIndex,
    required Pointer<csmModel> model,
    required CubismCoreBindings bindings,
  })  : _model = model,
        _bindings = bindings;

  /// Whether this drawable uses additive blending.
  bool get isBlendAdditive => (constantFlags & csmBlendAdditive) != 0;

  /// Whether this drawable uses multiplicative blending.
  bool get isBlendMultiplicative =>
      (constantFlags & csmBlendMultiplicative) != 0;

  /// Whether this drawable is double-sided.
  bool get isDoubleSided => (constantFlags & csmIsDoubleSided) != 0;

  /// Whether this drawable's mask is inverted.
  bool get isInvertedMask => (constantFlags & csmIsInvertedMask) != 0;

  /// The blend mode of this drawable.
  CubismBlendMode get blendMode {
    if (isBlendAdditive) return CubismBlendMode.additive;
    if (isBlendMultiplicative) return CubismBlendMode.multiplicative;
    return CubismBlendMode.normal;
  }

  /// Dynamic flags (visibility, change tracking).
  int get dynamicFlags =>
      _bindings.csmGetDrawableDynamicFlags(_model)[index];

  /// Whether this drawable is currently visible.
  bool get isVisible => (dynamicFlags & csmIsVisible) != 0;

  /// Whether visibility changed since the last update.
  bool get visibilityDidChange =>
      (dynamicFlags & csmVisibilityDidChange) != 0;

  /// Whether opacity changed since the last update.
  bool get opacityDidChange => (dynamicFlags & csmOpacityDidChange) != 0;

  /// Whether vertex positions changed since the last update.
  bool get vertexPositionsDidChange =>
      (dynamicFlags & csmVertexPositionsDidChange) != 0;

  /// Current opacity of this drawable.
  double get opacity =>
      _bindings.csmGetDrawableOpacities(_model)[index];

  /// Draw order for layering.
  int get drawOrder =>
      _bindings.csmGetDrawableDrawOrders(_model)[index];

  /// Render order for sorting.
  int get renderOrder =>
      _bindings.csmGetRenderOrders(_model)[index];

  /// Number of vertices in this drawable's mesh.
  int get vertexCount =>
      _bindings.csmGetDrawableVertexCounts(_model)[index];

  /// Number of triangle indices.
  int get indexCount =>
      _bindings.csmGetDrawableIndexCounts(_model)[index];

  /// Number of clipping masks applied to this drawable.
  int get maskCount =>
      _bindings.csmGetDrawableMaskCounts(_model)[index];

  /// Gets the vertex positions as a flat Float32List [x0, y0, x1, y1, ...].
  Float32List getVertexPositions() {
    final count = vertexCount;
    if (count == 0) return Float32List(0);
    final positions = _bindings.csmGetDrawableVertexPositions(_model)[index];
    // Each csmVector2 is 2 floats (X, Y) = 8 bytes
    return positions.cast<Float>().asTypedList(count * 2);
  }

  /// Gets the UV coordinates as a flat Float32List [u0, v0, u1, v1, ...].
  Float32List getVertexUvs() {
    final count = vertexCount;
    if (count == 0) return Float32List(0);
    final uvs = _bindings.csmGetDrawableVertexUvs(_model)[index];
    return uvs.cast<Float>().asTypedList(count * 2);
  }

  /// Gets the triangle indices as a Uint16List.
  Uint16List getIndices() {
    final count = indexCount;
    if (count == 0) return Uint16List(0);
    final indices = _bindings.csmGetDrawableIndices(_model)[index];
    return indices.cast<Uint16>().asTypedList(count);
  }

  /// Gets the mask drawable indices for this drawable.
  List<int> getMaskIndices() {
    final count = maskCount;
    if (count == 0) return const [];
    final masks = _bindings.csmGetDrawableMasks(_model)[index];
    return List<int>.generate(count, (i) => masks[i]);
  }

  /// Gets the multiply color (RGBA) for this drawable.
  ({double r, double g, double b, double a}) get multiplyColor {
    final colors = _bindings.csmGetDrawableMultiplyColors(_model);
    final c = colors[index];
    return (r: c.X, g: c.Y, b: c.Z, a: c.W);
  }

  /// Gets the screen color (RGBA) for this drawable.
  ({double r, double g, double b, double a}) get screenColor {
    final colors = _bindings.csmGetDrawableScreenColors(_model);
    final c = colors[index];
    return (r: c.X, g: c.Y, b: c.Z, a: c.W);
  }

  @override
  String toString() =>
      'CubismDrawable($id: verts=$vertexCount, tris=${indexCount ~/ 3}, tex=$textureIndex)';
}
