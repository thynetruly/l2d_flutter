// Full motion benchmark — 600 frames of Haru's idle motion playback.
//
// This is the realistic motion-playback hot path: CubismMotion parses the
// real motion3.json from Samples/Resources/Haru/, and each frame calls
// updateParameters with a CubismModel built from the real moc3. Per the
// plan that's 63 curves × ~296 segments evaluated every frame, with a
// significant chunk going through Cardano's algorithm.
//
// Two variants:
//   default — straight timing pass.
//   instrumentedCount — wraps LibM.cosf/sinf/atan2f/sqrtf/acos/cbrt/powf/
//                        cbrtf with counters during one full run and emits
//                        the tallies in `metadata`. This variant is NOT
//                        timed — the instrumentation skews measurements.
//                        Purpose: empirically confirm the hot-path counts
//                        in Context (250 motion LibM calls per frame).

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';

import '../fixtures.dart';
import '../harness.dart';

class _FullMotionBench extends CubismBenchmark {
  // One op = 600-frame Haru idle motion playback (10 s @ 60 fps).
  // Per-frame cost = meanNs / 600.
  _FullMotionBench()
      : super(
          module: 'motion',
          benchName: 'fullMotion',
          opKind: OpKind.frameRun,
          framesPerOp: _frames,
          innerIterations: 1,
          sampleCount: 20,
          warmupMs: 100,
        );

  static const int _frames = 600;
  static const double _dt = 1.0 / 60.0;

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismMotion _motion;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _motion = _fixture.newIdleMotion()!;
    _motion.isLoop = true;
    _motion.fadeInSeconds = 0.5;
    _motion.fadeOutSeconds = 0.5;
  }

  @override
  void run() {
    double elapsed = 0.0;
    for (int f = 0; f < _frames; f++) {
      elapsed += _dt;
      _motion.updateParameters(_model, elapsed, 1.0, 0.0, -1.0,
          userTimeSeconds: elapsed);
    }
  }

  @override
  void teardown() {
    _model.dispose();
    BenchSink.sink(_motion.modelOpacity);
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
        'curves': _motion.data.curveCount,
        'segments': _motion.data.segments.length,
        'points': _motion.data.points.length,
        'restricted_beziers': _motion.data.restrictedBeziers,
      };
}

List<CubismBenchmark> all() => [_FullMotionBench()];
