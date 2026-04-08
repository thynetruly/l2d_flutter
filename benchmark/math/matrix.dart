// CubismMatrix44 benchmarks — focuses on the allocations flagged in the plan.
//
// `multiply` allocates a fresh `Float32List(16)` scratch buffer on every call
// (cubism_matrix44.dart:166). `translateRelative` and `scaleRelative` each
// allocate *another* `Float32List(16)` (lines 64, 85) before calling into
// multiply, so each relative transform pays for two 64-byte lists. This
// benchmark measures both the aliased path (dst == b) and the non-aliased
// path because the scratch-buffer cost is the same but the inner loop layout
// differs.

import 'dart:typed_data';

import 'package:l2d_flutter_plugin/src/framework/math/cubism_matrix44.dart';

import '../harness.dart';

class _MultiplyBench extends CubismBenchmark {
  // One op = one CubismMatrix44.multiply call. meanNs is directly per-call.
  _MultiplyBench({bool aliased = false})
      : _aliased = aliased,
        super(
          module: 'math',
          benchName: 'matrixMultiply',
          variant: aliased ? 'aliased' : 'nonAliased',
          opKind: OpKind.singleCall,
          innerIterations: 100000,
        );

  final bool _aliased;

  late Float32List _a;
  late Float32List _b;
  late Float32List _dst;

  @override
  void setup() {
    _a = Float32List.fromList(List.generate(16, (i) => (i + 1) * 0.125));
    _b = Float32List.fromList(List.generate(16, (i) => (i * 2 + 1) * 0.0625));
    _dst = _aliased ? _b : Float32List(16);
  }

  @override
  void run() {
    CubismMatrix44.multiply(_a, _b, _dst);
  }

  @override
  void teardown() {
    BenchSink.sink(_dst[0] + _dst[15]);
  }
}

class _TranslateRelativeBench extends CubismBenchmark {
  // One op = 2 translateRelative calls (alternating sign). Per-call = meanNs/2.
  _TranslateRelativeBench()
      : super(
          module: 'math',
          benchName: 'translateRelative',
          opKind: OpKind.callBatch,
          innerIterations: 100000,
        );

  late CubismMatrix44 _m;

  @override
  void setup() {
    _m = CubismMatrix44();
  }

  @override
  void run() {
    // Alternating sign so the matrix doesn't drift and break the bench.
    _m.translateRelative(0.001, 0.002);
    _m.translateRelative(-0.001, -0.002);
  }

  @override
  void teardown() {
    BenchSink.sink(_m.translateX);
  }
}

class _ScaleRelativeBench extends CubismBenchmark {
  // One op = 2 scaleRelative calls (alternating factors). Per-call = meanNs/2.
  _ScaleRelativeBench()
      : super(
          module: 'math',
          benchName: 'scaleRelative',
          opKind: OpKind.callBatch,
          innerIterations: 100000,
        );

  late CubismMatrix44 _m;

  @override
  void setup() {
    _m = CubismMatrix44();
  }

  @override
  void run() {
    _m.scaleRelative(1.0001, 0.9999);
    _m.scaleRelative(0.9999, 1.0001);
  }

  @override
  void teardown() {
    BenchSink.sink(_m.scaleX);
  }
}

class _GetInvertBench extends CubismBenchmark {
  // One op = one getInvert() call. meanNs is directly per-call.
  _GetInvertBench()
      : super(
          module: 'math',
          benchName: 'getInvert',
          opKind: OpKind.singleCall,
          innerIterations: 10000,
        );

  late CubismMatrix44 _m;
  double _acc = 0.0;

  @override
  void setup() {
    _m = CubismMatrix44();
    _m.translate(0.5, -0.3);
    _m.scale(1.25, 0.75);
  }

  @override
  void run() {
    final inv = _m.getInvert();
    _acc += inv.translateX;
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }
}

List<CubismBenchmark> all() => [
      _MultiplyBench(aliased: false),
      _MultiplyBench(aliased: true),
      _TranslateRelativeBench(),
      _ScaleRelativeBench(),
      _GetInvertBench(),
    ];
