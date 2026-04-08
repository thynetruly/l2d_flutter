// Breath benchmark — 360 frames of Haru's breath effect (6 seconds @ 60 fps).
//
// Each call to CubismBreath.updateParameters does one LibM.sinf per
// configured parameter. Haru has 5 breath parameters (see the C++ SDK demo
// controller) but we use a 1-parameter config matching the existing full
// pipeline test so numbers compare apples-to-apples with other benchmarks.

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';

import '../fixtures.dart';
import '../harness.dart';

class _BreathBench extends CubismBenchmark {
  // One op = 360-frame simulated breath update (6 s @ 60 fps). Per-frame
  // cost = meanNs / 360. The reporter shows both columns automatically.
  _BreathBench()
      : super(
          module: 'effect',
          benchName: 'breath',
          opKind: OpKind.frameRun,
          framesPerOp: _frames,
          innerIterations: 1,
          sampleCount: 30,
        );

  static const int _frames = 360;
  static const double _dt = 1.0 / 60.0;

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismBreath _breath;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _breath = CubismBreath(parameters: const [
      BreathParameterData(
        parameterId: 'ParamBreath',
        offset: 0.0,
        peak: 0.4,
        cycle: 3.2345,
        weight: 0.5,
      ),
      BreathParameterData(
        parameterId: 'ParamAngleX',
        offset: 0.0,
        peak: 15.0,
        cycle: 6.5345,
        weight: 0.5,
      ),
      BreathParameterData(
        parameterId: 'ParamAngleY',
        offset: 0.0,
        peak: 8.0,
        cycle: 3.5345,
        weight: 0.5,
      ),
    ]);
  }

  @override
  void run() {
    for (int i = 0; i < _frames; i++) {
      _breath.updateParameters(_model, _dt);
    }
  }

  @override
  void teardown() {
    _model.dispose();
    BenchSink.sink(_breath.currentTime);
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
        'parameter_count': _breath.parameters.length,
      };
}

List<CubismBenchmark> all() => [_BreathBench()];
