// Regression gate: compares benchmark/results.json against benchmark/baseline.json.
//
// Exits 0 if every result is within tolerance. Exits 1 (and prints a table
// of violations) if any benchmark regressed beyond its configured limit.
//
// Per-benchmark limits in baseline.json:
//
//   {
//     "benchmarks": {
//       "math/cosf": { "maxMeanNs": 60 },
//       "physics/pendulum@haru_8particles": { "maxMsPerFrame": 0.5 },
//       "pipeline/fullFrame@60fps": { "maxMsPerFrame": 16.6 },
//       "math/matrixMultiply@aliased": { "maxBytesPerOp": 0 }
//     },
//     "defaults": {
//       "regressionTolerancePct": 20,
//       "multiInstanceScalingMaxSuperlinearityPct": 30,
//       "multiModelPerModelWarnVariance": 3.0
//     }
//   }
//
// Unspecified benchmarks use only the defaults (percent regression against
// the previous committed baseline's meanNs). Informational gates (such as
// multiModelPerModelWarnVariance) print warnings but never fail the build.

import 'dart:convert';
import 'dart:io';

Future<int> main(List<String> argv) async {
  final resultsPath = argv.isNotEmpty ? argv[0] : 'benchmark/results.json';
  const baselinePath = 'benchmark/baseline.json';

  final resultsFile = File(resultsPath);
  if (!resultsFile.existsSync()) {
    stderr.writeln('Results file not found: $resultsPath');
    stderr.writeln('Run: dart run benchmark/run_all.dart');
    return 2;
  }
  final baselineFile = File(baselinePath);
  if (!baselineFile.existsSync()) {
    stdout.writeln('No baseline file at $baselinePath — skipping comparison.');
    stdout.writeln('To create one, copy results.json:');
    stdout.writeln('  cp $resultsPath $baselinePath');
    return 0;
  }

  final results =
      jsonDecode(resultsFile.readAsStringSync()) as Map<String, dynamic>;
  final baseline =
      jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>;

  final benches = (baseline['benchmarks'] as Map<String, dynamic>?) ?? const {};
  final defaults =
      (baseline['defaults'] as Map<String, dynamic>?) ?? const {};
  final tolPct =
      (defaults['regressionTolerancePct'] as num?)?.toDouble() ?? 20.0;
  final scalingPct =
      (defaults['multiInstanceScalingMaxSuperlinearityPct'] as num?)
              ?.toDouble() ??
          30.0;
  final varianceFactor =
      (defaults['multiModelPerModelWarnVariance'] as num?)?.toDouble() ?? 3.0;

  // Build a lookup from results.
  final byKey = <String, Map<String, dynamic>>{};
  for (final r in (results['results'] as List)) {
    final rec = r as Map<String, dynamic>;
    final module = rec['module'] as String;
    final name = rec['name'] as String;
    final variant = rec['variant'] as String? ?? 'default';
    final key = variant == 'default' ? '$module/$name' : '$module/$name@$variant';
    byKey[key] = rec;
  }

  final violations = <String>[];
  final warnings = <String>[];

  // --- Per-benchmark limits ---
  for (final entry in benches.entries) {
    final key = entry.key;
    final limits = entry.value as Map<String, dynamic>;
    final rec = byKey[key];
    if (rec == null) {
      warnings.add('Baseline references "$key" but results.json has no such '
          'benchmark. Did you add --filter?');
      continue;
    }

    final meanNs = (rec['meanNs'] as num).toDouble();
    final maxMeanNs = (limits['maxMeanNs'] as num?)?.toDouble();
    if (maxMeanNs != null && meanNs > maxMeanNs) {
      violations.add('$key: meanNs=$meanNs > max=$maxMeanNs');
    }

    // Per-frame limit — uses the perFrameNs field populated by the harness
    // for frameRun benchmarks. Falls back to dividing meanNs by the frame
    // count in metadata for older results.json files.
    final msPerFrameLimit =
        (limits['maxMsPerFrame'] as num?)?.toDouble();
    if (msPerFrameLimit != null) {
      double? msPerFrame;
      final perFrameNs = (rec['perFrameNs'] as num?)?.toDouble();
      if (perFrameNs != null) {
        msPerFrame = perFrameNs / 1e6;
      } else {
        final framesPerOp = (rec['framesPerOp'] as num?)?.toInt();
        final fromMeta =
            ((rec['metadata'] as Map<String, dynamic>?)?['frames'] as num?)
                ?.toInt();
        final frames = framesPerOp ?? fromMeta ?? 1;
        msPerFrame = (meanNs / 1e6) / frames;
      }
      if (msPerFrame > msPerFrameLimit) {
        violations.add('$key: ms/frame=${msPerFrame.toStringAsFixed(3)} '
            '> max=${msPerFrameLimit.toStringAsFixed(3)}');
      }
    }

    final bytes = rec['bytesAllocPerOp'];
    final maxBytes = (limits['maxBytesPerOp'] as num?)?.toInt();
    if (maxBytes != null && bytes != null && (bytes as num).toInt() > maxBytes) {
      violations.add('$key: bytes/op=$bytes > max=$maxBytes');
    }
  }

  // --- Percent regression against last committed baseline values ---
  // Treat baseline.benchmarks[*].prevMeanNs as the previous baseline mean.
  // When absent, percent-regression gating is skipped for that entry.
  for (final entry in benches.entries) {
    final key = entry.key;
    final limits = entry.value as Map<String, dynamic>;
    final prev = (limits['prevMeanNs'] as num?)?.toDouble();
    if (prev == null) continue;
    final rec = byKey[key];
    if (rec == null) continue;
    final mean = (rec['meanNs'] as num).toDouble();
    final delta = (mean - prev) / prev * 100.0;
    if (delta > tolPct) {
      violations.add(
          '$key: meanNs regression ${delta.toStringAsFixed(1)}% (${prev.toStringAsFixed(1)} '
          '→ ${mean.toStringAsFixed(1)}) > tolerance ${tolPct.toStringAsFixed(0)}%');
    }
  }

  // --- multi_instance superlinearity gate ---
  // Uses perFrameNs from the harness when present; falls back to dividing
  // meanNs by metadata.frames for older results.json files.
  final mi60 = <int, double>{};
  final mi120 = <int, double>{};
  for (final rec in byKey.values) {
    if (rec['module'] != 'pipeline' || rec['name'] != 'multiInstance') continue;
    final variant = rec['variant'] as String;
    final match = RegExp(r'^(\d+)x(\d+)fps$').firstMatch(variant);
    if (match == null) continue;
    final n = int.parse(match.group(1)!);
    final fps = int.parse(match.group(2)!);
    double msPerFrame;
    final perFrameNs = (rec['perFrameNs'] as num?)?.toDouble();
    if (perFrameNs != null) {
      msPerFrame = perFrameNs / 1e6;
    } else {
      final framesPerOp = (rec['framesPerOp'] as num?)?.toInt() ??
          ((rec['metadata'] as Map<String, dynamic>?)?['frames'] as num?)
              ?.toInt() ??
          1;
      msPerFrame = (rec['meanNs'] as num) / 1e6 / framesPerOp;
    }
    final perInstance = msPerFrame / n;
    (fps == 60 ? mi60 : mi120)[n] = perInstance;
  }
  for (final mi in [mi60, mi120]) {
    final n1 = mi[1];
    final n8 = mi[8];
    if (n1 != null && n8 != null && n1 > 0) {
      final ratio = n8 / n1;
      final allowed = 1.0 + scalingPct / 100.0;
      if (ratio > allowed) {
        violations.add('pipeline/multiInstance scaling: '
            'ms/frame/instance @8x is ${ratio.toStringAsFixed(2)}× of @1x '
            '(allowed ${allowed.toStringAsFixed(2)}×)');
      }
    }
  }

  // --- multi_model informational variance gate ---
  for (final rec in byKey.values) {
    if (rec['module'] != 'pipeline' || rec['name'] != 'multiModel') continue;
    final variant = rec['variant'] as String;
    if (!variant.startsWith('8models')) continue;
    final meta = rec['metadata'] as Map<String, dynamic>;
    final splits = <double>[];
    for (final entry in meta.entries) {
      if (entry.key.endsWith('_us') && entry.value is num) {
        splits.add((entry.value as num).toDouble());
      }
    }
    if (splits.length >= 2) {
      splits.sort();
      final fastest = splits.first;
      final slowest = splits.last;
      if (fastest > 0 && slowest / fastest > varianceFactor) {
        warnings.add('pipeline/multiModel@$variant per-model variance '
            '${(slowest / fastest).toStringAsFixed(1)}× '
            '(warn threshold ${varianceFactor.toStringAsFixed(1)}×) — '
            'slowest/fastest spread; optimisation signal, not a regression');
      }
    }
  }

  // --- Output ---
  stdout.writeln('');
  stdout.writeln('Regression check against $baselinePath');
  stdout.writeln('  results: $resultsPath');
  stdout.writeln('  benches checked: ${benches.length}');
  stdout.writeln('  tolerance: ${tolPct.toStringAsFixed(0)}%');
  stdout.writeln('');
  for (final w in warnings) {
    stdout.writeln('[warn] $w');
  }
  if (violations.isEmpty) {
    stdout.writeln('OK: no regressions detected.');
    return 0;
  }
  stdout.writeln('FAIL: ${violations.length} regression(s):');
  for (final v in violations) {
    stdout.writeln('  - $v');
  }
  return 1;
}
