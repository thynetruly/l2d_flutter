// CPU-side renderer benchmark.
//
// CubismRenderer.drawModel() does two things per drawable:
//   1. CPU work: vertex position transform (MVP × each vertex), UV
//      coordinate scaling, index list copy, render-order sorting.
//   2. GPU work: canvas.drawVertices() with an ImageShader.
//
// This benchmark isolates the CPU work (1) — the part under our control.
// It can run under pure `dart test` / `dart run` without a Flutter
// environment. The GPU work (2) requires a real Canvas surface and will
// be measured in the Flutter benchmark app (benchmark/flutter/).
//
// Methodology: for each drawable, replicate the exact loops from
// CubismRenderer._drawDrawable (vertex transform, UV scale, index copy)
// using the model's real drawable data. Count the total vertex and index
// throughput per frame.
//
// This also serves as the "high drawable count" stress test: Haru has
// ~80 drawables; we measure per-drawable cost and project to 200+.

import 'dart:typed_data';

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_matrix44.dart';

import '../fixtures.dart';
import '../harness.dart';

class _CpuDrawBench extends CubismBenchmark {
  // One op = one full frame's worth of drawable processing: sort all
  // drawables by render order, then for each visible drawable transform
  // vertices, scale UVs, copy indices. framesPerOp = 1 so meanNs is
  // directly "ns per frame of CPU render work".
  _CpuDrawBench()
      : super(
          module: 'rendering',
          benchName: 'cpuDraw',
          opKind: OpKind.frameRun,
          framesPerOp: 1,
          innerIterations: 100,
          sampleCount: 30,
        );

  late CubismModel _model;
  late CubismMatrix44 _mvp;
  // Simulate a 1920×1080 canvas.
  static const double _w = 1920.0;
  static const double _h = 1080.0;

  int _totalVerts = 0;
  int _totalIndices = 0;
  int _visibleDrawables = 0;
  double _sink = 0.0;

  @override
  void setup() {
    _model = Fixtures.haru().newModel();
    _mvp = CubismMatrix44();
    // Run one model update so drawables have valid vertex data.
    _model.update();
  }

  @override
  void run() {
    final drawableCount = _model.drawableCount;

    // 1. Sort drawables by render order (same as CubismRenderer.drawModel).
    final sortedIndices = List<int>.generate(drawableCount, (i) => i);
    final renderOrders = _model.renderOrders;
    sortedIndices.sort((a, b) => renderOrders[a].compareTo(renderOrders[b]));

    int totalVerts = 0;
    int totalIdxs = 0;
    int visible = 0;
    final mvpArr = _mvp.array;

    // 2. Per-drawable CPU work (mirrors CubismRenderer._drawDrawable).
    for (final index in sortedIndices) {
      final drawable = _model.drawables[index];
      if (!drawable.isVisible) continue;
      if (drawable.vertexCount == 0) continue;
      if (drawable.indexCount == 0) continue;

      final positions = drawable.getVertexPositions();
      final uvs = drawable.getVertexUvs();
      final indices = drawable.getIndices();
      if (positions.isEmpty || indices.isEmpty) continue;

      visible++;
      totalVerts += positions.length ~/ 2;
      totalIdxs += indices.length;

      // --- Vertex transform (MVP to screen space) ---
      final transformed = Float32List(positions.length);
      for (int i = 0; i < positions.length; i += 2) {
        final mx = positions[i];
        final my = positions[i + 1];
        transformed[i] =
            (mvpArr[0] * mx + mvpArr[12]) * _w / 2.0 + _w / 2.0;
        transformed[i + 1] =
            (mvpArr[5] * my + mvpArr[13]) * -_h / 2.0 + _h / 2.0;
      }

      // --- UV scaling (to texture dimensions, assume 2048×2048) ---
      final scaledUvs = Float32List(uvs.length);
      for (int i = 0; i < uvs.length; i += 2) {
        scaledUvs[i] = uvs[i] * 2048.0;
        scaledUvs[i + 1] = uvs[i + 1] * 2048.0;
      }

      // --- Index copy (Uint16List conversion) ---
      final indexList = Uint16List.fromList(indices.toList());

      // Prevent DCE.
      _sink += transformed[0] + scaledUvs[0] + indexList[0];
    }

    _totalVerts = totalVerts;
    _totalIndices = totalIdxs;
    _visibleDrawables = visible;
  }

  @override
  void teardown() {
    _model.dispose();
    BenchSink.sink(_sink);
  }

  @override
  Map<String, Object?> get metadata => {
        'total_drawables': _model.drawableCount,
        'visible_drawables': _visibleDrawables,
        'total_vertices': _totalVerts,
        'total_indices': _totalIndices,
        'canvas_size': '${_w.round()}x${_h.round()}',
        '_note': 'CPU-side only. Does NOT call canvas.drawVertices. '
            'See benchmark/flutter/ for GPU measurement.',
      };
}

/// Stress variant: runs the CPU draw loop N times per op to simulate
/// rendering N models (or a model with N× the drawables). Reports the
/// scaling behaviour.
class _CpuDrawScaleBench extends CubismBenchmark {
  _CpuDrawScaleBench({required int multiplier})
      : _multiplier = multiplier,
        super(
          module: 'rendering',
          benchName: 'cpuDrawScale',
          variant: '${multiplier}x',
          opKind: OpKind.frameRun,
          framesPerOp: 1,
          innerIterations: 20,
          sampleCount: 20,
        );

  final int _multiplier;

  late CubismModel _model;
  late CubismMatrix44 _mvp;
  static const double _w = 1920.0;
  static const double _h = 1080.0;
  double _sink = 0.0;

  @override
  void setup() {
    _model = Fixtures.haru().newModel();
    _mvp = CubismMatrix44();
    _model.update();
  }

  @override
  void run() {
    final mvpArr = _mvp.array;
    // Repeat the entire drawable pass _multiplier times to simulate
    // higher drawable counts.
    for (int rep = 0; rep < _multiplier; rep++) {
      for (int d = 0; d < _model.drawableCount; d++) {
        final drawable = _model.drawables[d];
        if (!drawable.isVisible || drawable.vertexCount == 0) continue;

        final positions = drawable.getVertexPositions();
        final uvs = drawable.getVertexUvs();
        final indices = drawable.getIndices();
        if (positions.isEmpty || indices.isEmpty) continue;

        final transformed = Float32List(positions.length);
        for (int i = 0; i < positions.length; i += 2) {
          transformed[i] =
              (mvpArr[0] * positions[i] + mvpArr[12]) * _w / 2.0 + _w / 2.0;
          transformed[i + 1] =
              (mvpArr[5] * positions[i + 1] + mvpArr[13]) * -_h / 2.0 +
                  _h / 2.0;
        }
        final scaledUvs = Float32List(uvs.length);
        for (int i = 0; i < uvs.length; i += 2) {
          scaledUvs[i] = uvs[i] * 2048.0;
          scaledUvs[i + 1] = uvs[i + 1] * 2048.0;
        }
        final indexList = Uint16List.fromList(indices.toList());
        _sink += transformed[0] + scaledUvs[0] + indexList[0];
      }
    }
  }

  @override
  void teardown() {
    _model.dispose();
    BenchSink.sink(_sink);
  }

  @override
  Map<String, Object?> get metadata => {
        'multiplier': _multiplier,
        'effective_drawables': _model.drawableCount * _multiplier,
        '_note': 'Simulates $_multiplier× Haru drawable count '
            '(~${_model.drawableCount * _multiplier} drawables). '
            'CPU-side vertex transform + UV scale + index copy only.',
      };
}

List<CubismBenchmark> all() => [
      _CpuDrawBench(),
      _CpuDrawScaleBench(multiplier: 1), // baseline (= cpuDraw but via scale path)
      _CpuDrawScaleBench(multiplier: 3), // ~240 drawables
      _CpuDrawScaleBench(multiplier: 5), // ~400 drawables
    ];
