// Full-frame pipeline benchmark — the headline metric.
//
// Simulates a real render loop for Haru: motion → eye blink → breath →
// physics → pose → model.update(). This is the single number that matters
// for "can we hit 60 fps on this device?". Two variants:
//
//   @60fps  — dt = 1/60, 300 frames = 5 s of simulated time, target
//              ≤ 16.6 ms/frame. This is the v1 baseline.
//   @120fps — dt = 1/120, 600 frames = 5 s, target ≤ 8.3 ms/frame. Confirms
//              whether high-refresh targets (ProMotion iPad, 120 Hz
//              Android) fit budget. Most per-frame work is independent of
//              dt, so timing should be within ~5% of the 60 fps variant;
//              only the sub-stepped physics scales with dt.
//
// metadata carries per-phase Stopwatch splits (~50 ns overhead per phase
// is acceptable for diagnostic data).

import 'dart:math' as math;

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';

import '../fixtures.dart';
import '../harness.dart';

class _FullFrameBench extends CubismBenchmark {
  // One op = (targetFps × seconds) frames of the full pipeline
  // (motion + eye blink + breath + physics + pose + model.update).
  // Per-frame cost = meanNs / framesPerOp. Target per-frame budgets:
  //   60 fps  → ≤ 16.6 ms/frame
  //   120 fps → ≤  8.3 ms/frame
  _FullFrameBench({required this.targetFps, required this.seconds})
      : super(
          module: 'pipeline',
          benchName: 'fullFrame',
          variant: '${targetFps}fps',
          opKind: OpKind.frameRun,
          framesPerOp: (targetFps * seconds).round(),
          innerIterations: 1,
          sampleCount: 20,
          warmupMs: 100,
        );

  final int targetFps;
  final double seconds;
  late final int _frames = (targetFps * seconds).round();
  late final double _dt = 1.0 / targetFps;

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismMotion _motion;
  late CubismEyeBlink _eyeBlink;
  late CubismBreath _breath;
  CubismPhysics? _physics;
  CubismPose? _pose;

  // Per-phase split timers (only populated by the last `run` invocation,
  // which is fine — samples are all identical workloads).
  final _splits = <String, int>{
    'motion_us': 0,
    'eye_blink_us': 0,
    'breath_us': 0,
    'physics_us': 0,
    'pose_us': 0,
    'update_us': 0,
  };

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _motion = _fixture.newIdleMotion()!;
    _motion.isLoop = true;
    _motion.fadeInSeconds = 0.5;
    _motion.fadeOutSeconds = 0.5;
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
    _physics = _fixture.newPhysics();
    _physics?.stabilization(_model);
    _pose = _fixture.newPose();
  }

  @override
  void run() {
    double elapsed = 0.0;
    final sw = Stopwatch();
    int motionUs = 0, eyeUs = 0, breathUs = 0, physUs = 0, poseUs = 0, updateUs = 0;

    for (int f = 0; f < _frames; f++) {
      elapsed += _dt;

      sw.reset();
      sw.start();
      _motion.updateParameters(_model, elapsed, 1.0, 0.0, -1.0,
          userTimeSeconds: elapsed);
      sw.stop();
      motionUs += sw.elapsedMicroseconds;

      sw.reset();
      sw.start();
      _eyeBlink.updateParameters(_model, _dt);
      sw.stop();
      eyeUs += sw.elapsedMicroseconds;

      sw.reset();
      sw.start();
      _breath.updateParameters(_model, _dt);
      sw.stop();
      breathUs += sw.elapsedMicroseconds;

      if (_physics != null) {
        sw.reset();
        sw.start();
        _physics!.evaluate(_model, _dt);
        sw.stop();
        physUs += sw.elapsedMicroseconds;
      }

      if (_pose != null) {
        sw.reset();
        sw.start();
        _pose!.updateParameters(_model, _dt);
        sw.stop();
        poseUs += sw.elapsedMicroseconds;
      }

      sw.reset();
      sw.start();
      _model.update();
      sw.stop();
      updateUs += sw.elapsedMicroseconds;
    }

    _splits['motion_us'] = motionUs;
    _splits['eye_blink_us'] = eyeUs;
    _splits['breath_us'] = breathUs;
    _splits['physics_us'] = physUs;
    _splits['pose_us'] = poseUs;
    _splits['update_us'] = updateUs;
  }

  @override
  void teardown() {
    _model.dispose();
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
        'target_fps': targetFps,
        'frame_budget_ms': 1000.0 / targetFps,
        // per-phase splits total for one full run (not per-frame)
        ..._splits,
      };
}

List<CubismBenchmark> all() => [
      _FullFrameBench(targetFps: 60, seconds: 5.0),
      _FullFrameBench(targetFps: 120, seconds: 5.0),
    ];
