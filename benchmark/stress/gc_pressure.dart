// GC pressure stress test.
//
// Runs the full managed pipeline (motion manager + expression manager +
// all effects + physics) at 120 fps with the stress-rig physics (50
// particles — the heaviest physics config) to maximise per-frame
// allocations: CubismVector2 chains in physics, MotionPoint temps in
// Bezier evaluation, Float32List scratches in matrix ops, plus expression
// blending's per-parameter accumulator list.
//
// Purpose: measure worst-case GC pause intrusion on frame time. Look at
// p95 and p99 relative to the mean — a big gap means GC pauses are
// landing inside the frame window. This is the benchmark that tells you
// whether Tier 2 (allocation reduction) work is needed.

import 'dart:math' as math;

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_expression_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion_manager.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';

import '../fixtures.dart';
import '../harness.dart';
import '../physics/pendulum_stress.dart' show generateStressRig;

class _GcPressureBench extends CubismBenchmark {
  // One op = 300 frames at 120 fps (2.5 s simulated time). Uses:
  //   - CubismMotionManager with an idle motion (curve eval allocs)
  //   - CubismExpressionMotionManager with 4 overlapping expressions
  //   - Eye blink + breath
  //   - 50-particle stress physics rig (10 sub-rigs × 5 particles)
  //   - model.update() (native FFI)
  //
  // 120 fps doubles the sub-step count in physics, further amplifying
  // per-frame allocations compared to 60 fps.
  _GcPressureBench()
      : super(
          module: 'stress',
          benchName: 'gcPressure',
          opKind: OpKind.frameRun,
          framesPerOp: _frames,
          innerIterations: 1,
          sampleCount: 15,
          warmupMs: 100,
        );

  static const int _frames = 300;
  static const double _dt = 1.0 / 120.0; // 120 fps for max sub-stepping

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismMotionManager _motionManager;
  late CubismExpressionMotionManager _exprManager;
  late CubismEyeBlink _eyeBlink;
  late CubismBreath _breath;
  late CubismPhysics _physics;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();

    // Motion manager with idle motion.
    _motionManager = CubismMotionManager();
    final motion = _fixture.newIdleMotion()!;
    motion.isLoop = true;
    motion.fadeInSeconds = 0.5;
    motion.fadeOutSeconds = 0.5;
    _motionManager.startMotionPriority(motion, priority: 1);

    // Expression storm: start 4 expressions at once so all are blending.
    _exprManager = CubismExpressionMotionManager();
    final exprs = _fixture.newExpressions(4);
    for (final e in exprs) {
      _exprManager.startExpression(e);
    }

    _eyeBlink = CubismEyeBlink(
      parameterIds: _fixture.settings.eyeBlinkParameterIds,
      random: math.Random(42),
    );
    _breath = CubismBreath(parameters: const [
      BreathParameterData(
        parameterId: 'ParamBreath',
        offset: 0.0,
        peak: 0.4,
        cycle: 3.2345,
        weight: 0.5,
      ),
    ]);

    // Use the heavy 50-particle stress rig instead of Haru's 8 particles.
    final stressJson = generateStressRig(subRigCount: 10, particlesPerRig: 5);
    _physics = CubismPhysics.fromString(stressJson);
    _physics.stabilization(_model);
  }

  @override
  void run() {
    for (int f = 0; f < _frames; f++) {
      _motionManager.updateMotion(_model, _dt);
      _exprManager.updateMotion(_model, _dt);
      _eyeBlink.updateParameters(_model, _dt);
      _breath.updateParameters(_model, _dt);
      _physics.evaluate(_model, _dt);
      _model.update();
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
        'physics_particles': 50,
        'expressions_active': 4,
        'pipeline': 'managed (motionManager + expressionManager + stressPhysics)',
      };
}

List<CubismBenchmark> all() => [_GcPressureBench()];
