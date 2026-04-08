import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../core/cubism_model.dart';
import '../../core/cubism_drawable.dart';
import '../math/cubism_matrix44.dart';

/// Renders a Cubism model to a Flutter [Canvas] using [CustomPainter].
///
/// Ported from Framework/src/Rendering/CubismRenderer.hpp.
/// Instead of OpenGL/Metal/D3D, this uses Flutter's Canvas API to draw
/// the model's drawable meshes with proper blend modes, opacity, and ordering.
class CubismRenderer {
  CubismModel? _model;
  final List<ui.Image> _textures = [];

  /// The Model-View-Projection matrix for transforming vertices.
  CubismMatrix44 mvpMatrix = CubismMatrix44();

  double _modelColorR = 1.0;
  double _modelColorG = 1.0;
  double _modelColorB = 1.0;
  double _modelColorA = 1.0;

  /// Whether textures use premultiplied alpha.
  bool isPremultipliedAlpha = false;

  /// Initializes the renderer with the given model.
  void initialize(CubismModel model) {
    _model = model;
  }

  /// Sets the model color tint (RGBA, each 0.0-1.0).
  void setModelColor(double r, double g, double b, double a) {
    _modelColorR = r;
    _modelColorG = g;
    _modelColorB = b;
    _modelColorA = a;
  }

  /// Sets the texture at [index].
  void setTexture(int index, ui.Image texture) {
    while (_textures.length <= index) {
      _textures.add(texture); // Placeholder expansion
    }
    _textures[index] = texture;
  }

  /// Returns the texture at [index], or null.
  ui.Image? getTexture(int index) {
    if (index < 0 || index >= _textures.length) return null;
    return _textures[index];
  }

  /// Draws the model to the given [canvas] with the given [size].
  ///
  /// Drawables are sorted by render order and drawn as textured triangle meshes
  /// with appropriate blend modes and opacity.
  void drawModel(Canvas canvas, Size size) {
    final model = _model;
    if (model == null) return;

    // Get sorted drawable indices by render order
    final drawableCount = model.drawableCount;
    final sortedIndices = List<int>.generate(drawableCount, (i) => i);
    final renderOrders = model.renderOrders;
    sortedIndices.sort((a, b) => renderOrders[a].compareTo(renderOrders[b]));

    // Draw each drawable in render order
    for (final index in sortedIndices) {
      final drawable = model.drawables[index];

      if (!drawable.isVisible) continue;
      if (drawable.vertexCount == 0) continue;
      if (drawable.indexCount == 0) continue;

      _drawDrawable(canvas, size, drawable);
    }
  }

  void _drawDrawable(Canvas canvas, Size size, CubismDrawable drawable) {
    final texture = getTexture(drawable.textureIndex);
    final positions = drawable.getVertexPositions();
    final uvs = drawable.getVertexUvs();
    final indices = drawable.getIndices();

    if (positions.isEmpty || indices.isEmpty) return;

    final opacity = drawable.opacity * _modelColorA;
    if (opacity <= 0.0) return;

    // Build vertices for Canvas.drawVertices
    // Transform model-space positions through MVP matrix to screen space
    final transformedPositions = Float32List(positions.length);
    for (int i = 0; i < positions.length; i += 2) {
      final mx = positions[i];
      final my = positions[i + 1];
      // Apply MVP: simple 2D transform (scaleX * x + translateX, scaleY * y + translateY)
      transformedPositions[i] =
          (mvpMatrix.array[0] * mx + mvpMatrix.array[12]) * size.width / 2.0 +
              size.width / 2.0;
      transformedPositions[i + 1] =
          (mvpMatrix.array[5] * my + mvpMatrix.array[13]) * -size.height / 2.0 +
              size.height / 2.0;
    }

    // Scale UVs to texture dimensions
    Float32List? scaledUvs;
    if (texture != null) {
      scaledUvs = Float32List(uvs.length);
      for (int i = 0; i < uvs.length; i += 2) {
        scaledUvs[i] = uvs[i] * texture.width.toDouble();
        scaledUvs[i + 1] = uvs[i + 1] * texture.height.toDouble();
      }
    }

    // Convert indices to Uint16List
    final indexList = Uint16List.fromList(indices.toList());

    // Create the vertices
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      transformedPositions,
      textureCoordinates: scaledUvs,
      indices: indexList,
    );

    // Determine blend mode
    final blendMode = _getBlendMode(drawable);

    // Draw
    final paint = Paint()
      ..color = ui.Color.fromRGBO(
        (_modelColorR * 255).round(),
        (_modelColorG * 255).round(),
        (_modelColorB * 255).round(),
        opacity,
      )
      ..blendMode = blendMode;

    if (texture != null) {
      // Draw with texture using shader
      final shader = ui.ImageShader(
        texture,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Matrix4.identity().storage,
      );
      paint.shader = shader;
    }

    canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
  }

  static ui.BlendMode _getBlendMode(CubismDrawable drawable) {
    switch (drawable.blendMode) {
      case CubismBlendMode.additive:
        return ui.BlendMode.plus;
      case CubismBlendMode.multiplicative:
        return ui.BlendMode.multiply;
      case CubismBlendMode.normal:
        return ui.BlendMode.srcOver;
    }
  }
}
