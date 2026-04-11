// Shared benchmark harness for the Cubism Framework performance suite.
//
// Every benchmark extends [CubismBenchmark], which overrides the default
// `benchmark_harness` measurement cycle with a sample-based collector that
// produces mean/median/p95/p99/stddev instead of a single mean. Results are
// emitted as [BenchResult] records, aggregated by [BenchReporter], and
// written to `benchmark/results.json` — one machine-readable contract
// consumed by `compare_baseline.dart`.
//
// Why not just use BenchmarkBase?
//   - BenchmarkBase returns a single averaged ns/op. We want percentiles so
//     regressions caused by GC pauses or FFI jitter are visible.
//   - We want multiple variants per benchmark (default vs isLeaf vs dartMath)
//     sharing the same setup/teardown path.
//   - We want machine-readable output at the end of a run, not lines printed
//     to stdout that need parsing.
//
// ---------------------------------------------------------------------------
// Reading the numbers
// ---------------------------------------------------------------------------
// Every measurement is reported as "time per op". The definition of "op"
// depends on the benchmark's [opKind]:
//
//   OpKind.callBatch — one op is a short unrolled batch of function calls
//                      (e.g. math/cosf runs 10 cosf calls per op). The
//                      division is inside run() so meanNs is "ns per full
//                      run() body" — divide further only if you want
//                      per-call cost and you know the unroll factor.
//
//   OpKind.frameRun  — one op is the full simulated frame loop the
//                      benchmark encapsulates. [framesPerOp] tells you how
//                      many frames the loop iterated. The reporter computes
//                      `perFrameNs = meanNs / framesPerOp` automatically
//                      and prints BOTH total-per-op and per-frame columns.
//
//   OpKind.singleCall — one op is a single function invocation with no
//                      unrolling and no inner loop. Used for one-shot
//                      benchmarks like CubismMatrix44.multiply where a
//                      single call is the thing we're measuring.
//
// Pipeline, effect, motion, and physics benchmarks are OpKind.frameRun.
// Raw math micro-benchmarks are OpKind.callBatch (unrolled to amortise
// Stopwatch overhead). Matrix/vector ops are OpKind.singleCall.

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:benchmark_harness/benchmark_harness.dart';

/// What a single "op" means for a benchmark. Determines how the reporter
/// prints the result and whether per-frame columns are included.
enum OpKind {
  /// One op = one unrolled batch of N function calls (math micro-benchmarks).
  /// meanNs is "ns per full run() body". The benchmark's docstring should
  /// note the unroll factor if per-call cost matters downstream.
  callBatch,

  /// One op = one single function invocation (matrix multiply, vector dot).
  /// meanNs is directly "ns per call".
  singleCall,

  /// One op = one full simulated frame loop. [BenchResult.framesPerOp]
  /// records how many frames one op ran, and [BenchResult.perFrameNs] is
  /// the derived per-frame cost. The summary printer shows both.
  frameRun,
}

/// Machine-readable result for a single (module, name, variant) measurement.
///
/// All time fields are nanoseconds-per-op. For [OpKind.frameRun] the
/// [framesPerOp] field is non-null and [perFrameNs] = meanNs / framesPerOp.
class BenchResult {
  final String module;
  final String name;
  final String variant;

  /// What one "op" means for this benchmark. See [OpKind] docstrings.
  final OpKind opKind;

  /// Number of frames simulated per op. Non-null when [opKind] is
  /// [OpKind.frameRun], null otherwise.
  final int? framesPerOp;

  /// Convenience: meanNs / framesPerOp. Null when [framesPerOp] is null.
  /// Populated automatically so readers scanning results.json can see
  /// per-frame cost without having to do the division.
  final double? perFrameNs;

  final double meanNs;
  final double medianNs;
  final double p95Ns;
  final double p99Ns;
  final double stddevNs;
  final double opsPerSec;

  final int samples;
  final int iterationsPerSample;

  /// Bytes allocated per logical operation, if allocation tracking was enabled
  /// for this run. `null` when the VM service was not available.
  final int? bytesAllocPerOp;

  /// Number of GC events observed during the allocation-tracking run.
  final int? gcCount;

  /// Benchmark-specific extra data (per-phase splits, counts, etc.).
  final Map<String, Object?> metadata;

  const BenchResult({
    required this.module,
    required this.name,
    required this.variant,
    required this.opKind,
    required this.meanNs,
    required this.medianNs,
    required this.p95Ns,
    required this.p99Ns,
    required this.stddevNs,
    required this.opsPerSec,
    required this.samples,
    required this.iterationsPerSample,
    this.framesPerOp,
    this.perFrameNs,
    this.bytesAllocPerOp,
    this.gcCount,
    this.metadata = const {},
  });

  /// Canonical key used to join timing/alloc runs and look up baseline
  /// thresholds: `module/name[@variant]`.
  String get key => variant == 'default'
      ? '$module/$name'
      : '$module/$name@$variant';

  Map<String, Object?> toJson() => {
        'module': module,
        'name': name,
        'variant': variant,
        'opKind': opKind.name,
        if (framesPerOp != null) 'framesPerOp': framesPerOp,
        'meanNs': _round(meanNs),
        if (perFrameNs != null) 'perFrameNs': _round(perFrameNs!),
        'medianNs': _round(medianNs),
        'p95Ns': _round(p95Ns),
        'p99Ns': _round(p99Ns),
        'stddevNs': _round(stddevNs),
        'opsPerSec': opsPerSec.round(),
        'samples': samples,
        'iterationsPerSample': iterationsPerSample,
        if (bytesAllocPerOp != null) 'bytesAllocPerOp': bytesAllocPerOp,
        if (gcCount != null) 'gcCount': gcCount,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}

/// Base class for every benchmark in the suite.
///
/// A single subclass can emit multiple [BenchResult] records by calling
/// [emit] once per variant. The default behaviour is to call [emit] once
/// from [measureAndEmit] using [runOne].
abstract class CubismBenchmark extends BenchmarkBase {
  final String module;
  final String benchName;
  final String variant;

  /// What one "op" means for this benchmark. Used by the reporter to pick
  /// the right units in the summary and to decide whether to emit a
  /// per-frame column.
  final OpKind opKind;

  /// Number of frames a single op iterates. Only meaningful when
  /// [opKind] is [OpKind.frameRun]; ignored otherwise.
  final int framesPerOp;

  /// Iterations per sample. Adaptive for sub-microsecond ops — override
  /// when the default (1) is too few to amortise Stopwatch overhead.
  final int innerIterations;

  /// Number of samples to collect (default 50). Each sample runs
  /// [innerIterations] times.
  final int sampleCount;

  /// Minimum warmup time in ms (default 200).
  final int warmupMs;

  CubismBenchmark({
    required this.module,
    required this.benchName,
    this.variant = 'default',
    this.opKind = OpKind.singleCall,
    this.framesPerOp = 0,
    this.innerIterations = 1,
    this.sampleCount = 50,
    this.warmupMs = 200,
  }) : super(_makeName(module, benchName, variant));

  /// Canonical `(module, name, variant)` key. Matches [BenchResult.key] so
  /// that tooling (alloc tracker, compare_baseline) can merge records
  /// without the two sources drifting apart.
  static String _makeName(String module, String benchName, String variant) =>
      variant == 'default'
          ? '$module/$benchName'
          : '$module/$benchName@$variant';

  /// One logical operation. Subclasses must override this. It will be
  /// invoked [innerIterations] times inside a timed batch. The default
  /// implementation throws to make missing overrides loud instead of
  /// silently measuring a no-op (which would produce nonsense ns/op).
  @override
  void run() {
    throw UnimplementedError('$runtimeType must override run()');
  }

  /// Hook for benchmarks that want to add metadata (per-phase splits,
  /// FFI call counts, etc.) to the emitted result.
  Map<String, Object?> get metadata => const {};

  /// Measures this benchmark and appends one or more [BenchResult] records
  /// to [into].
  ///
  /// Default: runs a single timing pass and emits one record. Override
  /// for benchmarks that need to emit multiple variants (e.g. the
  /// transcendentals benchmark running the same set of ops under
  /// default, isLeaf, and dartMath bindings).
  void measureAndEmit(List<BenchResult> into) {
    into.add(runOne());
  }

  /// Runs one timing pass and returns a single result. Subclasses that
  /// override [measureAndEmit] call this for each variant they want to emit.
  BenchResult runOne({String? overrideVariant, Map<String, Object?>? meta}) {
    final variantKey = _makeName(
        module, benchName, overrideVariant ?? variant);
    BenchLog.benchStart(variantKey);
    setup();
    try {
      _warmup();
      final samples = _collectSamples();
      final result = _statsFromSamples(
        samples,
        overrideVariant ?? variant,
        meta ?? metadata,
      );
      BenchLog.benchResult(result);
      return result;
    } catch (e) {
      BenchLog.error(variantKey, e);
      rethrow;
    } finally {
      teardown();
    }
  }

  void _warmup() {
    // Warm the JIT until we've spent at least [warmupMs] or run at least
    // 5 batches — whichever takes longer. This is the single biggest source
    // of noise if skipped.
    final sw = Stopwatch()..start();
    int batches = 0;
    while (sw.elapsedMilliseconds < warmupMs || batches < 5) {
      for (int i = 0; i < innerIterations; i++) {
        run();
      }
      batches++;
    }
  }

  List<double> _collectSamples() {
    final samples = List<double>.filled(sampleCount, 0.0);
    final sw = Stopwatch();
    for (int s = 0; s < sampleCount; s++) {
      sw.reset();
      sw.start();
      for (int i = 0; i < innerIterations; i++) {
        run();
      }
      sw.stop();
      // Convert to ns per op.
      samples[s] = sw.elapsedMicroseconds * 1000.0 / innerIterations;
    }
    return samples;
  }

  BenchResult _statsFromSamples(
    List<double> samples,
    String variant,
    Map<String, Object?> meta,
  ) {
    final sorted = [...samples]..sort();
    final n = sorted.length;
    final sum = sorted.fold<double>(0.0, (a, b) => a + b);
    final mean = sum / n;
    final median = sorted[n ~/ 2];
    final p95 = sorted[((n - 1) * 0.95).floor()];
    final p99 = sorted[((n - 1) * 0.99).floor()];
    double variance = 0.0;
    for (final v in sorted) {
      variance += (v - mean) * (v - mean);
    }
    variance /= n;
    final stddev = math.sqrt(variance);
    final opsPerSec = mean > 0 ? 1e9 / mean : 0.0;

    final isFrameRun = opKind == OpKind.frameRun && framesPerOp > 0;
    return BenchResult(
      module: module,
      name: benchName,
      variant: variant,
      opKind: opKind,
      framesPerOp: isFrameRun ? framesPerOp : null,
      perFrameNs: isFrameRun ? mean / framesPerOp : null,
      meanNs: mean,
      medianNs: median,
      p95Ns: p95,
      p99Ns: p99,
      stddevNs: stddev,
      opsPerSec: opsPerSec,
      samples: n,
      iterationsPerSample: innerIterations,
      metadata: meta,
    );
  }
}

/// Aggregates [BenchResult] records and serialises them to disk.
class BenchReporter {
  final List<BenchResult> results = [];
  final DateTime startedAt;
  final bool allocTrackingEnabled;

  BenchReporter({
    DateTime? startedAt,
    this.allocTrackingEnabled = false,
  }) : startedAt = startedAt ?? DateTime.now().toUtc();

  void add(BenchResult r) => results.add(r);
  void addAll(Iterable<BenchResult> rs) => results.addAll(rs);

  /// Prints a compact summary per result to stdout with explicit units.
  ///
  /// Layout:
  ///
  ///   name                           per-op          per-frame       p95
  ///   math/cosf                      74.7 ns/call    —               81.8 ns
  ///   physics/pendulum@haru_8part    547.0 µs/run    1.82 µs/frame   574.0 µs
  ///   pipeline/fullFrame@60fps       18.61 ms/run    62.0 µs/frame   19.31 ms
  ///
  /// The `per-op` column unit suffix tells you what one op means:
  ///   `/call` — single function invocation (OpKind.singleCall)
  ///   `/batch` — unrolled call batch (OpKind.callBatch; see benchmark
  ///              docstring for unroll factor)
  ///   `/run`  — one full frame-loop op (OpKind.frameRun); per-frame
  ///              column shows meanNs / framesPerOp
  void printSummary() {
    stdout.writeln('');
    stdout.writeln('─' * 92);
    stdout.writeln(
        '  Cubism Framework benchmark summary (${results.length} results)');
    stdout.writeln('─' * 92);
    stdout.writeln('  Columns: per-op = time for one benchmark op');
    stdout.writeln('           per-frame = meanNs / framesPerOp (only for '
        'frameRun benchmarks)');
    stdout.writeln('           op suffix: /call = single invocation, '
        '/batch = unrolled batch,');
    stdout.writeln('                      /run = one full frame-loop run');
    stdout.writeln('─' * 92);

    final nameWidth = results.fold<int>(
      30,
      (w, r) => math.max(w, r.key.length),
    );

    for (final r in results) {
      final perOp = _fmtTime(r.meanNs) + _opUnitSuffix(r.opKind);
      final perFrame = r.perFrameNs != null
          ? '${_fmtTime(r.perFrameNs!)}/frame'
          : '—';
      final p95 = _fmtTime(r.p95Ns);
      final alloc = r.bytesAllocPerOp != null
          ? '  ${r.bytesAllocPerOp}B/op'
          : '';

      stdout.writeln(
        '  ${r.key.padRight(nameWidth)}  '
        '${perOp.padLeft(14)}  '
        '${perFrame.padLeft(18)}  '
        'p95 ${p95.padLeft(10)}$alloc',
      );
    }
    stdout.writeln('─' * 92);
  }

  /// Formats a nanosecond value with an auto-scaled unit. No unit suffix
  /// indicating what an "op" is — [_opUnitSuffix] adds that separately.
  static String _fmtTime(double ns) {
    if (ns < 1e3) return '${ns.toStringAsFixed(1)} ns';
    if (ns < 1e6) return '${(ns / 1e3).toStringAsFixed(2)} µs';
    return '${(ns / 1e6).toStringAsFixed(2)} ms';
  }

  static String _opUnitSuffix(OpKind kind) {
    switch (kind) {
      case OpKind.singleCall:
        return '/call';
      case OpKind.callBatch:
        return '/batch';
      case OpKind.frameRun:
        return '/run';
    }
  }

  /// Serialises all collected results to `benchmark/results.json`.
  void writeJson(String path) {
    final doc = {
      'schemaVersion': 1,
      'runStartedAt': startedAt.toIso8601String(),
      'platform': {
        'os': Platform.operatingSystem,
        'arch': _arch(),
        'dartVersion': Platform.version.split(' ').first,
      },
      'allocTrackingEnabled': allocTrackingEnabled,
      'results': results.map((r) => r.toJson()).toList(),
    };
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(doc));
  }

  static String _arch() {
    if (Platform.isWindows) {
      return Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'unknown';
    }
    try {
      final r = Process.runSync('uname', ['-m']);
      if (r.exitCode == 0) {
        return (r.stdout as String).trim();
      }
    } catch (_) {}
    return 'unknown';
  }
}

/// Utility: prevent the JIT from dead-code-eliminating the benchmarked
/// expression. Every [run] body should end with `sink(...)` or write into
/// a field that escapes. `sink` is a no-op from the compiler's perspective
/// (it's a static field write), but the write itself has observable effects.
class BenchSink {
  BenchSink._();
  // ignore: unused_field
  static Object? _last;
  static void sink(Object? v) {
    _last = v;
  }
}

// ---------------------------------------------------------------------------
// Structured logging for DevTools Logging view
// ---------------------------------------------------------------------------

/// Emits structured JSON events via [developer.log] so benchmark lifecycle
/// is visible in the DevTools Logging tab. All events use the category name
/// `cubism.benchmark`, which can be filtered in the Logging view.
///
/// These coexist with the existing `stdout` printing — `BenchLog` is a
/// parallel channel for DevTools, not a replacement for console output.
class BenchLog {
  BenchLog._();

  static const String _name = 'cubism.benchmark';

  /// Logs the start of a benchmark.
  static void benchStart(String key) {
    developer.log(
      jsonEncode({'event': 'start', 'key': key}),
      name: _name,
    );
  }

  /// Logs a condensed result for a completed benchmark.
  static void benchResult(BenchResult r) {
    final payload = <String, Object?>{
      'event': 'result',
      'key': r.key,
      'opKind': r.opKind.name,
      'meanNs': (r.meanNs * 100).roundToDouble() / 100,
      if (r.perFrameNs != null)
        'perFrameNs': (r.perFrameNs! * 100).roundToDouble() / 100,
      if (r.bytesAllocPerOp != null) 'bytesAllocPerOp': r.bytesAllocPerOp,
    };
    developer.log(jsonEncode(payload), name: _name);
  }

  /// Logs an error during benchmark execution.
  static void error(String key, Object error) {
    developer.log(
      jsonEncode({'event': 'error', 'key': key, 'error': '$error'}),
      name: _name,
      level: 1000, // severe
    );
  }
}
