// CubismVector2 benchmark — measures the hot operators and alloc cost.
//
// The plan identified CubismVector2 as the #1 per-frame allocation source
// (~750 instances per Haru frame: ~560 from physics sub-stepping, ~40 from
// motion, ~120 from the renderer). `operator +`, `operator -`, `operator *`
// all return new instances, so each call is a heap allocation on the hot
// path.
//
// This benchmark times the common op sequences used in physics
// `_updateParticles` (`a + b * s`) and the `length` / `distanceTo`
// operations that call into LibM.sqrtf / LibM.powf.

import 'package:l2d_flutter_plugin/src/framework/math/cubism_vector2.dart';

import '../harness.dart';

class _AddChainBench extends CubismBenchmark {
  _AddChainBench()
      : super(
          module: 'math',
          benchName: 'vector2.addChain',
          innerIterations: 100000,
        );

  late CubismVector2 _a;
  late CubismVector2 _b;
  late CubismVector2 _c;
  double _accX = 0.0;

  @override
  void setup() {
    _a = CubismVector2(1.0, 2.0);
    _b = CubismVector2(0.5, -0.5);
    _c = CubismVector2(-0.25, 0.75);
  }

  @override
  void run() {
    // Mimics the per-particle physics hot path:
    //   particle.position = particle.position + velocity * dt + force * (dt*dt)
    // Each `+` and `*` allocates a new CubismVector2. 5 allocations per run.
    final r = _a + _b * 0.016 + _c * (0.016 * 0.016);
    _accX += r.x;
  }

  @override
  void teardown() {
    BenchSink.sink(_accX);
  }
}

class _LengthBench extends CubismBenchmark {
  _LengthBench()
      : super(
          module: 'math',
          benchName: 'vector2.length',
          innerIterations: 100000,
        );

  late CubismVector2 _v;
  double _acc = 0.0;

  @override
  void setup() {
    _v = CubismVector2(3.14, -2.71);
  }

  @override
  void run() {
    // One LibM.sqrtf call per invocation.
    _acc += _v.length;
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }
}

class _DistanceToBench extends CubismBenchmark {
  _DistanceToBench()
      : super(
          module: 'math',
          benchName: 'vector2.distanceTo',
          innerIterations: 100000,
        );

  late CubismVector2 _a;
  late CubismVector2 _b;
  double _acc = 0.0;

  @override
  void setup() {
    _a = CubismVector2(1.0, 2.0);
    _b = CubismVector2(4.0, 6.0);
  }

  @override
  void run() {
    _acc += _a.distanceTo(_b);
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }
}

class _NormalizeBench extends CubismBenchmark {
  _NormalizeBench()
      : super(
          module: 'math',
          benchName: 'vector2.normalize',
          innerIterations: 100000,
        );

  late CubismVector2 _v;

  @override
  void setup() {
    _v = CubismVector2(3.0, 4.0);
  }

  @override
  void run() {
    // Uses LibM.powf(..., 0.5) internally (not sqrtf — see cubism_vector2.dart).
    // Keep the length stable by re-setting every call so normalize doesn't
    // collapse to zero after accumulated float drift.
    _v.x = 3.0;
    _v.y = 4.0;
    _v.normalize();
  }

  @override
  void teardown() {
    BenchSink.sink(_v.x + _v.y);
  }
}

class _DotBench extends CubismBenchmark {
  _DotBench()
      : super(
          module: 'math',
          benchName: 'vector2.dot',
          innerIterations: 1000000,
        );

  late CubismVector2 _a;
  late CubismVector2 _b;
  double _acc = 0.0;

  @override
  void setup() {
    _a = CubismVector2(1.5, -2.25);
    _b = CubismVector2(3.0, 1.75);
  }

  @override
  void run() {
    // Pure Dart — no FFI, no allocation. Baseline for "fastest possible" op.
    _acc += _a.dot(_b);
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }
}

List<CubismBenchmark> all() => [
      _AddChainBench(),
      _LengthBench(),
      _DistanceToBench(),
      _NormalizeBench(),
      _DotBench(),
    ];
