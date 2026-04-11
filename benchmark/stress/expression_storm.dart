// Expression crossfade storm stress test.
//
// Starts 3-4 expressions in rapid succession through
// CubismExpressionMotionManager so multiple are blending simultaneously.
// Measures the O(params × expressions) blend loop — each active expression
// iterates all model parameters and applies additive/multiply/overwrite
// weights.
//
// Haru has 8 expression files (F01..F08) so we have real data. Each
// expression modifies a subset of the model's ~40+ parameters. With 4
// active expressions in crossfade, the blend loop is ~160 parameter
// updates per frame — small compared to motion curves, but the per-param
// map lookup makes it allocation-sensitive.

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_expression_motion.dart';

import '../fixtures.dart';
import '../harness.dart';

class _ExpressionStormBench extends CubismBenchmark {
  // One op = 300-frame simulation. A new expression is started every 30
  // frames. With fadeInTime=1.0 and fadeOutTime=1.0 (defaults), there's a
  // long overlap window where 3-4 expressions are blending simultaneously.
  _ExpressionStormBench({required int expressionCount})
      : _exprCount = expressionCount,
        super(
          module: 'stress',
          benchName: 'expressionStorm',
          variant: '${expressionCount}expressions',
          opKind: OpKind.frameRun,
          framesPerOp: _frames,
          innerIterations: 1,
          sampleCount: 20,
          warmupMs: 100,
        );

  final int _exprCount;
  static const int _frames = 300;
  static const double _dt = 1.0 / 60.0;
  static const int _startInterval = 30;

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismExpressionMotionManager _exprManager;
  late List<CubismExpressionMotion> _expressions;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _exprManager = CubismExpressionMotionManager();
    _expressions = _fixture.newExpressions(_exprCount);
    if (_expressions.isEmpty) {
      throw StateError(
        'Haru has no expression files — this benchmark needs ≥1. '
        'Check Samples/Resources/Haru/expressions/',
      );
    }
  }

  @override
  void run() {
    int nextExpr = 0;
    for (int f = 0; f < _frames; f++) {
      if (f % _startInterval == 0 && nextExpr < _expressions.length) {
        _exprManager.startExpression(_expressions[nextExpr]);
        nextExpr++;
      }
      _exprManager.updateMotion(_model, _dt);
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
        'expression_count': _exprCount,
        'start_interval_frames': _startInterval,
      };
}

List<CubismBenchmark> all() => [
      _ExpressionStormBench(expressionCount: 4),
      _ExpressionStormBench(expressionCount: 8),
    ];
