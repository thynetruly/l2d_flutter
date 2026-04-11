// Cardano algorithm benchmark — the main Bezier curve evaluation hot path.
//
// cubism_motion.dart:_bezierEvaluateCardano calls
// CubismMath.cardanoAlgorithmForBezier on every frame for every Bezier
// segment of every parameter curve that is currently active. For Haru's
// idle motion that's ~296 segments across 63 curves — this one function
// runs hundreds of times per frame and its cost dominates motion playback.
//
// The 5 discriminant branches (|a|<epsilon quadratic, disc<0 three-root,
// disc==0 double-root, disc>0 one-root, and the |b|<epsilon degenerate
// quadratic) each take a different code path through libm. We sample all
// five with representative coefficients so the mean is a meaningful
// "typical call cost" instead of best/worst case.

import 'package:l2d_flutter_plugin/src/framework/math/cubism_math.dart';

import '../harness.dart';

class _CardanoBench extends CubismBenchmark {
  // One op = unrolled batch of 6 cardanoAlgorithmForBezier calls spanning
  // all 5 discriminant branches. Per-call cost = meanNs / 6.
  _CardanoBench()
      : super(
          module: 'math',
          benchName: 'cardanoAlgorithmForBezier',
          opKind: OpKind.callBatch,
          innerIterations: 10000,
        );

  double _acc = 0.0;

  @override
  void run() {
    // Coefficients chosen to land in each of the 5 code paths:
    //   1. |a|<eps -> quadraticEquation happy path
    //   2. discriminant < 0 -> three distinct real roots (LibM.sqrtf + acos + cbrt + cosf x3)
    //   3. discriminant == 0 -> repeated roots (LibM.cbrt only)
    //   4. discriminant > 0 -> one real root (LibM.sqrtf + cbrt x2)
    //   5. |a|<eps AND |b|<eps -> -c
    _acc += CubismMath.cardanoAlgorithmForBezier(0.0, 1.0, 2.0, -3.0);
    _acc += CubismMath.cardanoAlgorithmForBezier(1.0, -6.0, 11.0, -6.0);
    _acc += CubismMath.cardanoAlgorithmForBezier(1.0, 0.0, 0.0, 0.0);
    _acc += CubismMath.cardanoAlgorithmForBezier(1.0, 0.0, 1.0, -2.0);
    _acc += CubismMath.cardanoAlgorithmForBezier(0.0, 0.0, 0.0, 0.5);
    // Extra three-root case (the most expensive one — 5 libm calls).
    _acc += CubismMath.cardanoAlgorithmForBezier(1.0, -3.0, 2.0, -0.3);
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }
}

class _QuadraticBench extends CubismBenchmark {
  // One op = unrolled batch of 3 calls. Per-call cost = meanNs / 3.
  _QuadraticBench()
      : super(
          module: 'math',
          benchName: 'quadraticEquation',
          opKind: OpKind.callBatch,
          innerIterations: 100000,
        );

  double _acc = 0.0;

  @override
  void run() {
    _acc += CubismMath.quadraticEquation(1.0, -3.0, 2.0);
    _acc += CubismMath.quadraticEquation(2.0, 5.0, -3.0);
    _acc += CubismMath.quadraticEquation(0.0, 2.0, 4.0);
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }
}

class _EasingSineBench extends CubismBenchmark {
  // One op = unrolled batch of 5 calls. Per-call cost = meanNs / 5.
  _EasingSineBench()
      : super(
          module: 'math',
          benchName: 'getEasingSine',
          opKind: OpKind.callBatch,
          innerIterations: 100000,
        );

  double _acc = 0.0;

  @override
  void run() {
    _acc += CubismMath.getEasingSine(0.1);
    _acc += CubismMath.getEasingSine(0.3);
    _acc += CubismMath.getEasingSine(0.5);
    _acc += CubismMath.getEasingSine(0.7);
    _acc += CubismMath.getEasingSine(0.9);
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }
}

List<CubismBenchmark> all() => [
      _CardanoBench(),
      _QuadraticBench(),
      _EasingSineBench(),
    ];
