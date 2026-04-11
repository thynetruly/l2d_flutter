// Model scaling benchmark — heavy model counts with staggered + simultaneous loading.
//
// Tracks how per-frame cost degrades as model count increases from 1 to 32.
// Two loading strategies:
//
//   simultaneous — all N models are loaded (moc parse + physics stabilize +
//                  motion parse) before the first frame. Measures the
//                  steady-state per-frame cost after startup.
//
//   staggered    — models are loaded one per second during the frame loop.
//                  Measures the per-frame cost spike when a new model's
//                  physics stabilization + first curve evaluation hit
//                  mid-animation. This simulates a visual novel loading
//                  characters as they enter the scene.
//
// Both variants use the same 120-frame run (2 s at 60 fps). The staggered
// variant loads a new model every 60 frames (1 s), so by frame 60×(N-1)
// all models are active. For N>2 this means the first and last model have
// been animating for very different durations — exposing any per-instance
// warmup artifacts (JIT, first-frame physics snap, etc.).
//
// Models: cycles through all 8 sample models, repeating as needed. E.g.
// N=16 uses each sample model twice, N=32 uses each four times. Each
// instance gets its own CubismModel + physics + motion + effects.

import 'dart:math' as math;

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion_manager.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';

import '../fixtures.dart';
import '../harness.dart';

const _allModels = SampleModel.values; // 8 models

class _ModelInstance {
  final SampleModel sample;
  final CubismModel model;
  final CubismMotionManager motionManager;
  final CubismEyeBlink eyeBlink;
  final CubismBreath breath;
  final CubismPhysics? physics;
  final CubismPose? pose;

  _ModelInstance({
    required this.sample,
    required this.model,
    required this.motionManager,
    required this.eyeBlink,
    required this.breath,
    required this.physics,
    required this.pose,
  });

  static _ModelInstance build(SampleModel sample, int seedOffset) {
    final fixture = Fixtures.load(sample);
    final model = fixture.newModel();
    final manager = CubismMotionManager();
    final motion = fixture.newIdleMotion();
    if (motion != null) {
      motion.isLoop = true;
      motion.fadeInSeconds = 0.5;
      motion.fadeOutSeconds = 0.5;
      manager.startMotionPriority(motion, priority: 1);
    }
    final eye = CubismEyeBlink(
      parameterIds: fixture.settings.eyeBlinkParameterIds,
      random: math.Random(42 + seedOffset),
    );
    final breath = CubismBreath(parameters: const [
      BreathParameterData(
        parameterId: 'ParamBreath',
        offset: 0.0,
        peak: 0.4,
        cycle: 3.2345,
        weight: 0.5,
      ),
    ]);
    final physics = fixture.newPhysics();
    physics?.stabilization(model);
    final pose = fixture.newPose();
    return _ModelInstance(
      sample: sample,
      model: model,
      motionManager: manager,
      eyeBlink: eye,
      breath: breath,
      physics: physics,
      pose: pose,
    );
  }

  void tick(double dt) {
    motionManager.updateMotion(model, dt);
    eyeBlink.updateParameters(model, dt);
    breath.updateParameters(model, dt);
    physics?.evaluate(model, dt);
    pose?.updateParameters(model, dt);
    model.update();
  }

  void dispose() => model.dispose();
}

class _ModelScalingBench extends CubismBenchmark {
  _ModelScalingBench({
    required this.modelCount,
    required this.staggered,
  }) : super(
          module: 'pipeline',
          benchName: 'modelScaling',
          variant: '${modelCount}models_${staggered ? "staggered" : "simultaneous"}',
          opKind: OpKind.frameRun,
          framesPerOp: _frames,
          innerIterations: 1,
          sampleCount: staggered ? 10 : 15,
          warmupMs: 100,
        );

  final int modelCount;
  final bool staggered;

  static const int _frames = 120;
  static const double _dt = 1.0 / 60.0;
  static const int _staggerIntervalFrames = 60;

  final List<_ModelInstance> _instances = [];
  final Stopwatch _loadSw = Stopwatch();
  int _totalLoadUs = 0;

  @override
  void setup() {
    _instances.clear();
    _totalLoadUs = 0;
    if (!staggered) {
      // Simultaneous: load all models up front.
      _loadSw.reset();
      _loadSw.start();
      for (int i = 0; i < modelCount; i++) {
        final sample = _allModels[i % _allModels.length];
        _instances.add(_ModelInstance.build(sample, i));
      }
      _loadSw.stop();
      _totalLoadUs = _loadSw.elapsedMicroseconds;
    }
  }

  @override
  void run() {
    int nextToLoad = staggered ? 0 : modelCount; // skip loading if simultaneous

    for (int f = 0; f < _frames; f++) {
      // Staggered: load one model every _staggerIntervalFrames.
      if (staggered && f % _staggerIntervalFrames == 0 && nextToLoad < modelCount) {
        _loadSw.reset();
        _loadSw.start();
        final sample = _allModels[nextToLoad % _allModels.length];
        _instances.add(_ModelInstance.build(sample, nextToLoad));
        _loadSw.stop();
        _totalLoadUs += _loadSw.elapsedMicroseconds;
        nextToLoad++;
      }

      // Tick all currently-loaded instances.
      for (final inst in _instances) {
        inst.tick(_dt);
      }
    }
  }

  @override
  void teardown() {
    for (final inst in _instances) {
      inst.dispose();
    }
    _instances.clear();
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
        'model_count': modelCount,
        'loading': staggered ? 'staggered' : 'simultaneous',
        if (staggered) 'stagger_interval_frames': _staggerIntervalFrames,
        'total_load_us': _totalLoadUs,
      };
}

List<CubismBenchmark> all() => [
      // Simultaneous: all models loaded before first frame.
      for (final n in const [1, 2, 4, 8, 16, 32])
        _ModelScalingBench(modelCount: n, staggered: false),
      // Staggered: models loaded during the frame loop, 1 per second.
      for (final n in const [2, 4, 8, 16])
        _ModelScalingBench(modelCount: n, staggered: true),
    ];
