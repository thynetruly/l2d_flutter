// Transcendental-function micro-benchmark.
//
// This is the single most important benchmark in the suite — it decides
// whether Tier-1 optimization (`isLeaf: true` on every LibM FFI binding) is
// worth landing. For each function, we measure three variants in isolation:
//
//   default — LibM.* as it ships today. No isLeaf hint on the FFI call.
//   isLeaf  — a LOCAL FFI lookup with isLeaf: true. lib/src/framework/math/
//             libm.dart is NOT modified. This lets us quantify the saving
//             before touching production code.
//   dartMath — dart:math equivalent (double-precision, not bit-exact with
//             the C++ SDK). Baseline only — we cannot ship this, but it
//             tells us how much FFI overhead we're paying for parity.
//
// Each variant runs 10 unrolled calls with slightly varying inputs per
// inner iteration so libm's fast paths for special values (0, 1, π) don't
// skew the number. The accumulator is written to [BenchSink] in teardown
// to defeat dead-code elimination.

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:l2d_flutter_plugin/src/framework/math/libm.dart';

import '../harness.dart';

typedef _F1 = double Function(double);
typedef _F2 = double Function(double, double);

// ---------------------------------------------------------------------------
// Local isLeaf-enabled bindings. These do NOT touch lib/src/framework/math/
// libm.dart — the whole point is to measure whether isLeaf helps before
// applying it library-wide.
// ---------------------------------------------------------------------------

class _LeafBindings {
  static DynamicLibrary? _lib;
  static DynamicLibrary get _libm {
    if (_lib != null) return _lib!;
    if (Platform.isLinux) {
      _lib = DynamicLibrary.open('libm.so.6');
    } else if (Platform.isAndroid) {
      try {
        _lib = DynamicLibrary.open('libm.so');
      } catch (_) {
        _lib = DynamicLibrary.process();
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      _lib = DynamicLibrary.process();
    } else if (Platform.isWindows) {
      try {
        _lib = DynamicLibrary.open('ucrtbase.dll');
      } catch (_) {
        _lib = DynamicLibrary.open('msvcrt.dll');
      }
    } else {
      throw UnsupportedError('libm not available');
    }
    return _lib!;
  }

  static final _F1 cosf = _libm.lookupFunction<Float Function(Float),
      double Function(double)>('cosf', isLeaf: true);
  static final _F1 sinf = _libm.lookupFunction<Float Function(Float),
      double Function(double)>('sinf', isLeaf: true);
  static final _F1 tanf = _libm.lookupFunction<Float Function(Float),
      double Function(double)>('tanf', isLeaf: true);
  static final _F2 atan2f = _libm.lookupFunction<
      Float Function(Float, Float),
      double Function(double, double)>('atan2f', isLeaf: true);
  static final _F1 sqrtf = _libm.lookupFunction<Float Function(Float),
      double Function(double)>('sqrtf', isLeaf: true);
  static final _F1 cbrtf = _libm.lookupFunction<Float Function(Float),
      double Function(double)>('cbrtf', isLeaf: true);
  static final _F2 powf = _libm.lookupFunction<
      Float Function(Float, Float),
      double Function(double, double)>('powf', isLeaf: true);
  static final _F1 acos = _libm.lookupFunction<Double Function(Double),
      double Function(double)>('acos', isLeaf: true);
  static final _F1 cbrt = _libm.lookupFunction<Double Function(Double),
      double Function(double)>('cbrt', isLeaf: true);
}

// ---------------------------------------------------------------------------
// Benchmark runners: each benchmark owns a funcName and emits three variants
// by swapping which callable the inner loop uses.
// ---------------------------------------------------------------------------

abstract class _Transcendental1 extends CubismBenchmark {
  // One op = an unrolled batch of 10 calls to the target function with
  // varied inputs. Per-call cost is meanNs / 10 (see run() body).
  _Transcendental1(String funcName)
      : super(
          module: 'math',
          benchName: funcName,
          opKind: OpKind.callBatch,
          innerIterations: 10000,
        );

  double _acc = 0.0;
  _F1? _activeFn;

  _TranscendentalBindings1 get bindings;

  /// Default to the shipped LibM binding so that bare `bench.run()` calls
  /// (e.g. from the alloc-tracking pass in run_all.dart) exercise the real
  /// production path, not whichever variant happened to run last.
  /// [_runVariant] sets [_activeFn] before calling into [runOne] so this
  /// only kicks in for the first-ever setup and for external callers.
  @override
  void setup() {
    _activeFn ??= bindings.defaultFn;
  }

  @override
  void measureAndEmit(List<BenchResult> into) {
    final b = bindings;
    _runVariant(into, 'default', b.defaultFn);
    _runVariant(into, 'isLeaf', b.leafFn);
    if (b.dartMathFn != null) {
      _runVariant(into, 'dartMath', b.dartMathFn!);
    }
    // Reset so a subsequent alloc-tracking pass uses the shipped default
    // binding, not whichever variant happened to run last.
    _activeFn = null;
  }

  @override
  void run() {
    // 10 unrolled calls with varied inputs to avoid special-value fast paths.
    final f = _activeFn!;
    _acc += f(0.12);
    _acc += f(0.37);
    _acc += f(0.54);
    _acc += f(0.73);
    _acc += f(0.91);
    _acc += f(1.13);
    _acc += f(1.42);
    _acc += f(1.78);
    _acc += f(2.19);
    _acc += f(2.55);
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }

  void _runVariant(List<BenchResult> into, String variant, _F1 fn) {
    _activeFn = fn;
    into.add(runOne(overrideVariant: variant));
  }
}

/// Holder for the three variants of a single-arg transcendental function.
class _TranscendentalBindings1 {
  final _F1 defaultFn;
  final _F1 leafFn;
  final _F1? dartMathFn;
  const _TranscendentalBindings1({
    required this.defaultFn,
    required this.leafFn,
    required this.dartMathFn,
  });
}

// Concrete benchmarks. Each one is tiny — it exists solely to name the
// function and wire up the three variants.

class _CosfBench extends _Transcendental1 {
  _CosfBench() : super('cosf');
  @override
  _TranscendentalBindings1 get bindings => _TranscendentalBindings1(
        defaultFn: LibM.cosf,
        leafFn: _LeafBindings.cosf,
        dartMathFn: math.cos,
      );
}

class _SinfBench extends _Transcendental1 {
  _SinfBench() : super('sinf');
  @override
  _TranscendentalBindings1 get bindings => _TranscendentalBindings1(
        defaultFn: LibM.sinf,
        leafFn: _LeafBindings.sinf,
        dartMathFn: math.sin,
      );
}

class _TanfBench extends _Transcendental1 {
  _TanfBench() : super('tanf');
  @override
  _TranscendentalBindings1 get bindings => _TranscendentalBindings1(
        defaultFn: LibM.tanf,
        leafFn: _LeafBindings.tanf,
        dartMathFn: math.tan,
      );
}

class _SqrtfBench extends _Transcendental1 {
  _SqrtfBench() : super('sqrtf');
  @override
  _TranscendentalBindings1 get bindings => _TranscendentalBindings1(
        defaultFn: LibM.sqrtf,
        leafFn: _LeafBindings.sqrtf,
        dartMathFn: math.sqrt,
      );
}

class _CbrtfBench extends _Transcendental1 {
  _CbrtfBench() : super('cbrtf');
  @override
  _TranscendentalBindings1 get bindings => _TranscendentalBindings1(
        defaultFn: LibM.cbrtf,
        leafFn: _LeafBindings.cbrtf,
        // dart:math has no cbrt; use pow(x, 1/3) as a stand-in so we have
        // *something* to compare FFI cost against.
        dartMathFn: (x) => math.pow(x, 1.0 / 3.0).toDouble(),
      );
}

class _AcosBench extends _Transcendental1 {
  _AcosBench() : super('acos');
  @override
  _TranscendentalBindings1 get bindings => _TranscendentalBindings1(
        defaultFn: LibM.acos,
        leafFn: _LeafBindings.acos,
        dartMathFn: math.acos,
      );
}

class _CbrtBench extends _Transcendental1 {
  _CbrtBench() : super('cbrt');
  @override
  _TranscendentalBindings1 get bindings => _TranscendentalBindings1(
        defaultFn: LibM.cbrt,
        leafFn: _LeafBindings.cbrt,
        dartMathFn: (x) => math.pow(x, 1.0 / 3.0).toDouble(),
      );
}

// Two-argument bench: atan2f and powf share the same pattern.

abstract class _Transcendental2 extends CubismBenchmark {
  // One op = an unrolled batch of 10 calls. Per-call cost = meanNs / 10.
  _Transcendental2(String funcName)
      : super(
          module: 'math',
          benchName: funcName,
          opKind: OpKind.callBatch,
          innerIterations: 10000,
        );

  double _acc = 0.0;
  _F2? _activeFn;

  @override
  void setup() {
    _activeFn ??= bindings.defaultFn;
  }

  @override
  void measureAndEmit(List<BenchResult> into) {
    final b = bindings;
    _runVariant(into, 'default', b.defaultFn);
    _runVariant(into, 'isLeaf', b.leafFn);
    if (b.dartMathFn != null) {
      _runVariant(into, 'dartMath', b.dartMathFn!);
    }
    _activeFn = null;
  }

  @override
  void run() {
    final f = _activeFn!;
    _acc += f(0.12, 0.71);
    _acc += f(0.37, 1.28);
    _acc += f(0.54, 1.93);
    _acc += f(0.73, 2.17);
    _acc += f(0.91, 2.44);
    _acc += f(1.13, 2.81);
    _acc += f(1.42, 3.03);
    _acc += f(1.78, 0.44);
    _acc += f(2.19, 0.19);
    _acc += f(2.55, 0.08);
  }

  @override
  void teardown() {
    BenchSink.sink(_acc);
  }

  void _runVariant(List<BenchResult> into, String variant, _F2 fn) {
    _activeFn = fn;
    into.add(runOne(overrideVariant: variant));
  }

  _TranscendentalBindings2 get bindings;
}

class _TranscendentalBindings2 {
  final _F2 defaultFn;
  final _F2 leafFn;
  final _F2? dartMathFn;
  const _TranscendentalBindings2({
    required this.defaultFn,
    required this.leafFn,
    required this.dartMathFn,
  });
}

class _Atan2fBench extends _Transcendental2 {
  _Atan2fBench() : super('atan2f');
  @override
  _TranscendentalBindings2 get bindings => _TranscendentalBindings2(
        defaultFn: LibM.atan2f,
        leafFn: _LeafBindings.atan2f,
        dartMathFn: math.atan2,
      );
}

class _PowfBench extends _Transcendental2 {
  _PowfBench() : super('powf');
  @override
  _TranscendentalBindings2 get bindings => _TranscendentalBindings2(
        defaultFn: LibM.powf,
        leafFn: _LeafBindings.powf,
        dartMathFn: (x, y) => math.pow(x, y).toDouble(),
      );
}

/// All transcendental benchmarks, wired up for [run_all.dart].
List<CubismBenchmark> all() => [
      _CosfBench(),
      _SinfBench(),
      _TanfBench(),
      _SqrtfBench(),
      _CbrtfBench(),
      _AcosBench(),
      _CbrtBench(),
      _Atan2fBench(),
      _PowfBench(),
    ];
