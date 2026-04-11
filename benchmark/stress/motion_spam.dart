// Rapid motion switching stress test.
//
// Queues 5-10 motions in rapid succession through CubismMotionManager with
// overlapping fade windows. Measures queue management + concurrent curve
// evaluation under worst-case motion-spam conditions (e.g. the user
// clicking/tapping animation triggers faster than they finish fading).
//
// At peak overlap, 3-4 motions are evaluating curves simultaneously per
// frame — each computing fade-in/fade-out weights, running evaluateCurve
// on all their parameter curves, and blending into the same model parameters.

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion_manager.dart';

import '../fixtures.dart';
import '../harness.dart';

class _MotionSpamBench extends CubismBenchmark {
  // One op = 300-frame simulation. During the first 150 frames, a new
  // motion is queued every 30 frames (= every 0.5 s at 60 fps), so at
  // frame 150 there are ~5 motions in the queue with overlapping fades.
  // The remaining 150 frames let the queue drain while measuring the
  // fade-out tail cost.
  _MotionSpamBench({required int motionCount})
      : _motionCount = motionCount,
        super(
          module: 'stress',
          benchName: 'motionSpam',
          variant: '${motionCount}motions',
          opKind: OpKind.frameRun,
          framesPerOp: _frames,
          innerIterations: 1,
          sampleCount: 15,
          warmupMs: 100,
        );

  final int _motionCount;
  static const int _frames = 300;
  static const double _dt = 1.0 / 60.0;
  static const int _queueInterval = 30; // frames between new motion starts

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismMotionManager _manager;
  late List<CubismMotion> _motions;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _manager = CubismMotionManager();
    _motions = _fixture.newMotions(_motionCount);
    for (final m in _motions) {
      m.fadeInSeconds = 0.5;
      m.fadeOutSeconds = 0.5;
    }
  }

  @override
  void run() {
    int nextMotion = 0;
    for (int f = 0; f < _frames; f++) {
      // Queue a new motion every _queueInterval frames until we run out.
      if (f % _queueInterval == 0 && nextMotion < _motions.length) {
        _manager.startMotionPriority(
          _motions[nextMotion],
          priority: nextMotion + 1,
        );
        nextMotion++;
      }
      _manager.updateMotion(_model, _dt);
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
        'motion_count': _motionCount,
        'queue_interval_frames': _queueInterval,
        'peak_concurrent_motions': (_motionCount).clamp(0, 5),
      };
}

List<CubismBenchmark> all() => [
      _MotionSpamBench(motionCount: 5),
      _MotionSpamBench(motionCount: 10),
    ];
