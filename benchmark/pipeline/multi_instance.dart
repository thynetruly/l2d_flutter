// Multi-instance benchmark — N × Haru simultaneously.
//
// Tests homogeneous scaling: how many copies of the same model can a single
// isolate drive through the full pipeline before frame time blows up?
// Catches per-instance state that accidentally ends up shared across
// instances (finalizer pressure, static caches, global side effects).
//
// Variants: N × {60 fps, 120 fps} for N ∈ {1, 2, 4, 8} = 8 records.
// Reports total ms/frame and ms/frame/instance so linear vs super-linear
// scaling is visible.

import 'dart:math' as math;

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';

import '../fixtures.dart';
import '../harness.dart';

/// One independent pipeline, bound to its own CubismModel.
class _Instance {
  final CubismModel model;
  final CubismMotion motion;
  final CubismEyeBlink eyeBlink;
  final CubismBreath breath;
  final CubismPhysics? physics;
  final CubismPose? pose;

  _Instance({
    required this.model,
    required this.motion,
    required this.eyeBlink,
    required this.breath,
    required this.physics,
    required this.pose,
  });

  void tick(double dt, double elapsed) {
    motion.updateParameters(model, elapsed, 1.0, 0.0, -1.0,
        userTimeSeconds: elapsed);
    eyeBlink.updateParameters(model, dt);
    breath.updateParameters(model, dt);
    physics?.evaluate(model, dt);
    pose?.updateParameters(model, dt);
    model.update();
  }

  void dispose() => model.dispose();
}

class _MultiInstanceBench extends CubismBenchmark {
  // One op = (targetFps × seconds) frames, with each frame ticking
  // [instanceCount] independent Haru pipelines. Per-frame cost (for the
  // entire group) = meanNs / framesPerOp. Per-instance per-frame cost
  // = that value / instanceCount — useful for scaling analysis.
  _MultiInstanceBench({
    required this.instanceCount,
    required this.targetFps,
    required this.seconds,
  }) : super(
          module: 'pipeline',
          benchName: 'multiInstance',
          variant: '${instanceCount}x${targetFps}fps',
          opKind: OpKind.frameRun,
          framesPerOp: (targetFps * seconds).round(),
          innerIterations: 1,
          // Heavy benchmarks: trim sample count so a single --run-all doesn't
          // take forever. Still well above statistical noise floor.
          sampleCount: 15,
          warmupMs: 100,
        );

  final int instanceCount;
  final int targetFps;
  final double seconds;

  late final int _frames = (targetFps * seconds).round();
  late final double _dt = 1.0 / targetFps;

  final List<_Instance> _instances = [];

  @override
  void setup() {
    final fixture = Fixtures.haru();
    for (int i = 0; i < instanceCount; i++) {
      final model = fixture.newModel();
      final motion = fixture.newIdleMotion()!;
      motion.isLoop = true;
      motion.fadeInSeconds = 0.5;
      motion.fadeOutSeconds = 0.5;
      final eye = CubismEyeBlink(
        parameterIds: fixture.settings.eyeBlinkParameterIds,
        // Use distinct seeds so instances don't tick in lockstep (lockstep
        // would hide any GC pressure that interacts with shared allocator
        // state — we want to expose it).
        random: math.Random(42 + i),
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
      _instances.add(_Instance(
        model: model,
        motion: motion,
        eyeBlink: eye,
        breath: breath,
        physics: physics,
        pose: pose,
      ));
    }
  }

  @override
  void run() {
    double elapsed = 0.0;
    for (int f = 0; f < _frames; f++) {
      elapsed += _dt;
      // Sequential per-instance ticks; intentionally not interleaved so
      // per-instance cache locality is preserved (which is what a real
      // multi-character renderer does).
      for (final inst in _instances) {
        inst.tick(_dt, elapsed);
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
        'target_fps': targetFps,
        'instance_count': instanceCount,
        'frame_budget_ms': 1000.0 / targetFps,
      };
}

List<CubismBenchmark> all() => [
      for (final n in const [1, 2, 4, 8])
        for (final fps in const [60, 120])
          _MultiInstanceBench(
            instanceCount: n,
            targetFps: fps,
            seconds: 2.0, // 2 seconds × up to 8 instances × 120 fps keeps
                          // per-bench wall time reasonable
          ),
    ];
