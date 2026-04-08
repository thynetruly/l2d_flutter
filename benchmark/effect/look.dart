// Look benchmark — CubismLook's linear-combination dampening formula.
//
// CubismLook has zero libm calls; it's three multiply-adds per configured
// parameter. This benchmark exists for completeness (so run_all covers every
// effect class) and serves as a "lower bound" on per-parameter update cost.

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_look.dart';

import '../fixtures.dart';
import '../harness.dart';

class _LookBench extends CubismBenchmark {
  _LookBench()
      : super(
          module: 'effect',
          benchName: 'look',
          innerIterations: 1000,
        );

  late CubismModel _model;
  late CubismLook _look;

  @override
  void setup() {
    _model = Fixtures.haru().newModel();
    _look = CubismLook(parameters: const [
      LookParameterData(
        parameterId: 'ParamAngleX',
        factorX: 30.0,
        factorY: 0.0,
        factorXY: 0.0,
      ),
      LookParameterData(
        parameterId: 'ParamAngleY',
        factorX: 0.0,
        factorY: 30.0,
        factorXY: 0.0,
      ),
      LookParameterData(
        parameterId: 'ParamAngleZ',
        factorX: 0.0,
        factorY: 0.0,
        factorXY: 30.0,
      ),
      LookParameterData(
        parameterId: 'ParamBodyAngleX',
        factorX: 10.0,
        factorY: 0.0,
        factorXY: 0.0,
      ),
    ]);
  }

  @override
  void run() {
    // Sweep the drag inputs so each call hits a distinct parameter state.
    _look.updateParameters(_model, 0.3, 0.4);
    _look.updateParameters(_model, -0.2, 0.5);
    _look.updateParameters(_model, 0.7, -0.1);
  }

  @override
  void teardown() {
    _model.dispose();
  }
}

List<CubismBenchmark> all() => [_LookBench()];
