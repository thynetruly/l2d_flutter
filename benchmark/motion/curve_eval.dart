// Curve evaluation micro-benchmark.
//
// Exercises the 3 segment types in cubism_motion.dart directly by building
// a synthetic MotionData in memory (no JSON parsing, no file IO). Each
// variant measures one segment kind so the relative cost is visible:
//
//   linear  — `_linearEvaluate`: 2 point lookups, 1 subtract, 1 multiply.
//   restrictedBezier — `_bezierEvaluateSimple`: 5× MotionPoint.lerp, no
//             libm. Matches the SDK's R2-compatible path.
//   cardano — `_bezierEvaluateCardano`: 5× MotionPoint.lerp + one full
//             cardanoAlgorithmForBezier call. Matches the animator-correct
//             path Haru actually uses.
//
// This benchmark accesses `evaluateCurve` via the public symbol on
// CubismMotion — not directly, since `_bezierEvaluateCardano` is private.
// To get clean curve-level timings we build a MotionData by hand with a
// single curve of the target segment type and a synthetic time sweep.

import 'dart:convert';

import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';

import '../harness.dart';

/// Builds a minimal motion3.json string containing a single parameter curve
/// of the requested segment type, then parses it via CubismMotion.fromString.
/// This is the only way to construct a MotionData without touching private
/// constructors.
CubismMotion _buildSyntheticMotion({required int segmentType, bool restrictedBeziers = false}) {
  // 8 segments so the curve is long enough that the sweep hits many of them.
  // segmentType: 0=linear, 1=bezier, 2=stepped, 3=inverseStepped.
  final segments = <num>[0.0, 0.0]; // First point (t=0, v=0)
  double t = 0.0;
  double v = 0.0;
  for (int i = 0; i < 8; i++) {
    segments.add(segmentType);
    switch (segmentType) {
      case 0: // linear — 1 point
      case 2: // stepped — 1 point
      case 3: // inverseStepped — 1 point
        t += 0.25;
        v = (i % 2 == 0) ? 1.0 : -1.0;
        segments.addAll([t, v]);
      case 1: // bezier — 3 points (two control, one end)
        // Control points offset from the straight line to force the curve
        // to have non-trivial curvature — keeps Cardano out of degenerate
        // cases.
        final cx1 = t + 0.08;
        final cy1 = v + 0.5;
        final cx2 = t + 0.17;
        final cy2 = v - 0.5;
        t += 0.25;
        v = (i % 2 == 0) ? 1.0 : -1.0;
        segments.addAll([cx1, cy1, cx2, cy2, t, v]);
    }
  }

  final motionJson = {
    'Version': 3,
    'Meta': {
      'Duration': 2.0,
      'Fps': 30.0,
      'Loop': true,
      'AreBeziersRestricted': restrictedBeziers,
      'CurveCount': 1,
      'TotalSegmentCount': 8,
      'TotalPointCount': segments.length ~/ 2,
      'UserDataCount': 0,
      'TotalUserDataSize': 0,
    },
    'Curves': [
      {
        'Target': 'Parameter',
        'Id': 'BenchCurve',
        'FadeInTime': 0.5,
        'FadeOutTime': 0.5,
        'Segments': segments,
      },
    ],
  };

  return CubismMotion.fromString(jsonEncode(motionJson));
}

class _CurveEvalBench extends CubismBenchmark {
  // One op = unrolled batch of 8 evaluateCurve calls at different times.
  // Per-call cost = meanNs / 8.
  _CurveEvalBench({
    required String variantName,
    required int segmentType,
    required bool restrictedBeziers,
  })  : _segmentType = segmentType,
        _restricted = restrictedBeziers,
        super(
          module: 'motion',
          benchName: 'curveEval',
          variant: variantName,
          opKind: OpKind.callBatch,
          innerIterations: 10000,
        );

  final int _segmentType;
  final bool _restricted;

  late CubismMotion _motion;
  double _acc = 0.0;

  @override
  void setup() {
    _motion = _buildSyntheticMotion(
      segmentType: _segmentType,
      restrictedBeziers: _restricted,
    );
  }

  @override
  void run() {
    // Sweep 8 time points per inner iteration — one per segment — so every
    // segment in the curve contributes to the averaged timing.
    final data = _motion.data;
    _acc += evaluateCurve(data, 0, 0.10);
    _acc += evaluateCurve(data, 0, 0.35);
    _acc += evaluateCurve(data, 0, 0.60);
    _acc += evaluateCurve(data, 0, 0.85);
    _acc += evaluateCurve(data, 0, 1.10);
    _acc += evaluateCurve(data, 0, 1.35);
    _acc += evaluateCurve(data, 0, 1.60);
    _acc += evaluateCurve(data, 0, 1.85);
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }
}

List<CubismBenchmark> all() => [
      _CurveEvalBench(
          variantName: 'linear', segmentType: 0, restrictedBeziers: false),
      _CurveEvalBench(
          variantName: 'bezierCardano', segmentType: 1, restrictedBeziers: false),
      _CurveEvalBench(
          variantName: 'bezierRestricted', segmentType: 1, restrictedBeziers: true),
      _CurveEvalBench(
          variantName: 'stepped', segmentType: 2, restrictedBeziers: false),
    ];
