// Pose benchmark — 120 frames (2 s @ 60 fps) of Haru's pose3.json crossfade.
//
// Pose has no libm calls but writes to part opacities and cross-fades
// between groups. It's a good "stress the model parameter/part API"
// benchmark that isolates FFI part-write cost from math cost.

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';

import '../fixtures.dart';
import '../harness.dart';

class _PoseBench extends CubismBenchmark {
  // One op = 120-frame pose crossfade simulation (2 s @ 60 fps).
  // Per-frame cost = meanNs / 120.
  _PoseBench()
      : super(
          module: 'effect',
          benchName: 'pose',
          opKind: OpKind.frameRun,
          framesPerOp: _frames,
          innerIterations: 1,
          sampleCount: 30,
        );

  static const int _frames = 120;
  static const double _dt = 1.0 / 60.0;

  late ModelFixture _fixture;
  late CubismModel _model;
  CubismPose? _pose;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _pose = _fixture.newPose();
    if (_pose == null) {
      throw StateError(
        'Haru fixture has no pose3.json — this benchmark requires one. '
        'If Haru ships without pose data now, switch the benchmark to a '
        'different sample model.',
      );
    }
  }

  @override
  void run() {
    final pose = _pose!;
    for (int i = 0; i < _frames; i++) {
      pose.updateParameters(_model, _dt);
    }
  }

  @override
  void teardown() {
    _model.dispose();
    BenchSink.sink(_pose?.fadeTimeSeconds);
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
      };
}

List<CubismBenchmark> all() => [_PoseBench()];
