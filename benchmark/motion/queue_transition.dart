// Motion queue transition benchmark — 120 frames of a priority crossfade.
//
// Exercises CubismMotionManager with two motions, where the second starts
// at t=0.5s with a higher priority, triggering a fade-out of the first
// while the second fades in. The fade window overlaps for ~1s so both
// motions are evaluating curves per frame — worst-case motion load.

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion_manager.dart';

import '../fixtures.dart';
import '../harness.dart';

class _QueueTransitionBench extends CubismBenchmark {
  _QueueTransitionBench()
      : super(
          module: 'motion',
          benchName: 'queueTransition',
          innerIterations: 1,
          sampleCount: 25,
          warmupMs: 100,
        );

  static const int _frames = 120;
  static const double _dt = 1.0 / 60.0;

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismMotion _motionA;
  late CubismMotion _motionB;
  late CubismMotionManager _manager;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _motionA = _fixture.newIdleMotion()!;
    _motionA.isLoop = true;
    _motionA.fadeInSeconds = 0.5;
    _motionA.fadeOutSeconds = 0.5;
    _motionB = _fixture.newIdleMotion()!; // same motion, different instance
    _motionB.isLoop = true;
    _motionB.fadeInSeconds = 0.5;
    _motionB.fadeOutSeconds = 0.5;
    _manager = CubismMotionManager();
    _manager.startMotionPriority(_motionA, priority: 1);
  }

  @override
  void run() {
    for (int f = 0; f < _frames; f++) {
      // At frame 30 (t=0.5s) start the second motion with higher priority
      // so the manager begins fading A out while fading B in.
      if (f == 30) {
        _manager.startMotionPriority(_motionB, priority: 2);
      }
      _manager.updateMotion(_model, _dt);
    }
  }

  @override
  void teardown() {
    _model.dispose();
    BenchSink.sink(_manager.userTimeSeconds);
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
        'overlap_frames': _frames - 30,
      };
}

List<CubismBenchmark> all() => [_QueueTransitionBench()];
