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

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:benchmark_harness/benchmark_harness.dart';

/// Machine-readable result for a single (module, name, variant) measurement.
class BenchResult {
  final String module;
  final String name;
  final String variant;

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
    required this.meanNs,
    required this.medianNs,
    required this.p95Ns,
    required this.p99Ns,
    required this.stddevNs,
    required this.opsPerSec,
    required this.samples,
    required this.iterationsPerSample,
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
        'meanNs': _round(meanNs),
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
    setup();
    try {
      _warmup();
      final samples = _collectSamples();
      return _statsFromSamples(
        samples,
        overrideVariant ?? variant,
        meta ?? metadata,
      );
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

    return BenchResult(
      module: module,
      name: benchName,
      variant: variant,
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

  /// Prints a compact one-line summary per result to stdout.
  void printSummary() {
    stdout.writeln('');
    stdout.writeln('─' * 78);
    stdout.writeln('  Cubism Framework benchmark summary (${results.length} results)');
    stdout.writeln('─' * 78);
    final nameWidth = results.fold<int>(
      24,
      (w, r) => math.max(w, r.key.length),
    );
    for (final r in results) {
      final ns = r.meanNs;
      final unit = ns < 1e3
          ? '${ns.toStringAsFixed(1)} ns'
          : ns < 1e6
              ? '${(ns / 1e3).toStringAsFixed(2)} µs'
              : '${(ns / 1e6).toStringAsFixed(3)} ms';
      final alloc = r.bytesAllocPerOp != null
          ? '  ${r.bytesAllocPerOp}B/op'
          : '';
      stdout.writeln(
        '  ${r.key.padRight(nameWidth)}  ${unit.padLeft(12)}'
        '  p95=${_fmtNs(r.p95Ns).padLeft(10)}$alloc',
      );
    }
    stdout.writeln('─' * 78);
  }

  static String _fmtNs(double ns) {
    if (ns < 1e3) return '${ns.toStringAsFixed(1)}ns';
    if (ns < 1e6) return '${(ns / 1e3).toStringAsFixed(2)}µs';
    return '${(ns / 1e6).toStringAsFixed(2)}ms';
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
