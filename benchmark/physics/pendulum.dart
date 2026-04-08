// Pendulum benchmark — 300 frames (5 s) of Haru's physics simulation.
//
// Haru's physics3.json describes 4 sub-rigs × 2 particles = 8 particles
// total. Each `evaluate()` call does sub-stepping at the physics FPS, so
// there are typically 1–2 sub-steps per 60 fps frame. Per the hot-path
// estimate this is ~170 LibM calls per frame and ~560 CubismVector2
// allocations (the single biggest allocation source in the pipeline).

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';

import '../fixtures.dart';
import '../harness.dart';

class _PendulumBench extends CubismBenchmark {
  // One op = 300-frame Haru physics evaluation (5 s @ 60 fps).
  // Per-frame cost = meanNs / 300.
  _PendulumBench()
      : super(
          module: 'physics',
          benchName: 'pendulum',
          variant: 'haru_8particles',
          opKind: OpKind.frameRun,
          framesPerOp: _frames,
          innerIterations: 1,
          sampleCount: 20,
          warmupMs: 100,
        );

  static const int _frames = 300;
  static const double _dt = 1.0 / 60.0;

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismPhysics _physics;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _physics = _fixture.newPhysics()!;
    _physics.stabilization(_model);
  }

  @override
  void run() {
    for (int f = 0; f < _frames; f++) {
      _physics.evaluate(_model, _dt);
    }
  }

  @override
  void teardown() {
    _model.dispose();
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
      };
}

List<CubismBenchmark> all() => [_PendulumBench()];
