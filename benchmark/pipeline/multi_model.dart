// Multi-model benchmark — distinct sample models running in parallel.
//
// The most realistic "visual-novel with a cast" workload: Haru + Hiyori +
// Mao + Mark + Natori + Ren + Rice + Wanko, each running motion + physics
// + eye blink + breath + pose (where available). Answers "what happens
// when every model has a different hot path?" and surfaces per-model
// variance.
//
// Variants:
//   2models, 4models, 8models × {60 fps, 120 fps} = 6 records.
//
// Per-model Stopwatch splits are emitted in metadata so the slowest model
// in the mix is visible and can be targeted for optimization.

import 'dart:math' as math;

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';

import '../fixtures.dart';
import '../harness.dart';

const _allModelsInOrder = [
  SampleModel.haru,
  SampleModel.hiyori,
  SampleModel.mao,
  SampleModel.natori,
  SampleModel.mark,
  SampleModel.ren,
  SampleModel.rice,
  SampleModel.wanko,
];

/// One per-model pipeline. Holds its own model, motion, effects and
/// per-frame Stopwatch accumulator for metadata splits.
class _ModelPipeline {
  final SampleModel sample;
  final CubismModel model;
  final CubismMotion? motion;
  final CubismEyeBlink eyeBlink;
  final CubismBreath breath;
  final CubismPhysics? physics;
  final CubismPose? pose;

  int elapsedUs = 0;

  _ModelPipeline({
    required this.sample,
    required this.model,
    required this.motion,
    required this.eyeBlink,
    required this.breath,
    required this.physics,
    required this.pose,
  });

  static _ModelPipeline build(SampleModel sample, int seedOffset) {
    final fixture = Fixtures.load(sample);
    final model = fixture.newModel();
    final motion = fixture.newIdleMotion();
    if (motion != null) {
      motion.isLoop = true;
      motion.fadeInSeconds = 0.5;
      motion.fadeOutSeconds = 0.5;
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
    return _ModelPipeline(
      sample: sample,
      model: model,
      motion: motion,
      eyeBlink: eye,
      breath: breath,
      physics: physics,
      pose: pose,
    );
  }

  void tick(double dt, double elapsed, Stopwatch sw) {
    sw.reset();
    sw.start();
    motion?.updateParameters(model, elapsed, 1.0, 0.0, -1.0,
        userTimeSeconds: elapsed);
    eyeBlink.updateParameters(model, dt);
    breath.updateParameters(model, dt);
    physics?.evaluate(model, dt);
    pose?.updateParameters(model, dt);
    model.update();
    sw.stop();
    elapsedUs += sw.elapsedMicroseconds;
  }

  void dispose() => model.dispose();
}

class _MultiModelBench extends CubismBenchmark {
  // One op = (targetFps × seconds) frames, with each frame ticking
  // [modelCount] DISTINCT sample models. Per-frame cost (for the entire
  // mix) = meanNs / framesPerOp. See metadata.*_us for per-model splits.
  _MultiModelBench({
    required this.modelCount,
    required this.targetFps,
    required this.seconds,
  }) : super(
          module: 'pipeline',
          benchName: 'multiModel',
          variant: '${modelCount}models@${targetFps}fps',
          opKind: OpKind.frameRun,
          framesPerOp: (targetFps * seconds).round(),
          innerIterations: 1,
          sampleCount: 15,
          warmupMs: 100,
        );

  final int modelCount;
  final int targetFps;
  final double seconds;

  late final int _frames = (targetFps * seconds).round();
  late final double _dt = 1.0 / targetFps;

  final List<_ModelPipeline> _pipelines = [];

  @override
  void setup() {
    final selected = _allModelsInOrder.take(modelCount).toList();
    for (int i = 0; i < selected.length; i++) {
      _pipelines.add(_ModelPipeline.build(selected[i], i));
    }
  }

  @override
  void run() {
    double elapsed = 0.0;
    final sw = Stopwatch();
    for (final p in _pipelines) {
      p.elapsedUs = 0;
    }
    for (int f = 0; f < _frames; f++) {
      elapsed += _dt;
      for (final p in _pipelines) {
        p.tick(_dt, elapsed, sw);
      }
    }
  }

  @override
  void teardown() {
    for (final p in _pipelines) {
      p.dispose();
    }
    _pipelines.clear();
  }

  @override
  Map<String, Object?> get metadata {
    final perModel = <String, int>{};
    for (final p in _pipelines) {
      perModel['${p.sample.metaKey}_us'] = p.elapsedUs;
    }
    return {
      'frames': _frames,
      'dt_seconds': _dt,
      'target_fps': targetFps,
      'model_count': modelCount,
      'frame_budget_ms': 1000.0 / targetFps,
      'models_included': _pipelines.map((p) => p.sample.metaKey).toList(),
      // Per-model accumulated ms across the full run; slowest = biggest value
      ...perModel,
    };
  }
}

List<CubismBenchmark> all() => [
      for (final n in const [2, 4, 8])
        for (final fps in const [60, 120])
          _MultiModelBench(
            modelCount: n,
            targetFps: fps,
            seconds: 2.0,
          ),
    ];
