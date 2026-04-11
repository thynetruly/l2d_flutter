// Entry point that runs every benchmark in the suite and writes results.json.
//
// Usage:
//   dart run benchmark/run_all.dart
//   dart run benchmark/run_all.dart --filter=math/cosf
//   dart run benchmark/run_all.dart --filter=pipeline
//   dart run --enable-vm-service --pause-isolates-on-exit=false \
//       benchmark/run_all.dart --alloc
//
// The orchestrator is kept deliberately simple: it enumerates every
// CubismBenchmark exposed by the benchmark modules, applies `--filter` on
// the canonical `module/name[@variant]` key, runs the survivors, and writes
// the aggregated output to `benchmark/results.json`. Alloc tracking, when
// enabled, runs each benchmark a second time under the VM service and
// merges the per-op byte counts in place.

import 'dart:io';

import 'alloc_tracker.dart';
import 'effect/breath.dart' as breath;
import 'effect/eye_blink.dart' as eye_blink;
import 'effect/look.dart' as look;
import 'effect/pose.dart' as pose;
import 'harness.dart';
import 'math/cardano.dart' as cardano;
import 'math/matrix.dart' as matrix;
import 'math/transcendentals.dart' as transcendentals;
import 'math/vector2.dart' as vector2;
import 'motion/curve_eval.dart' as curve_eval;
import 'motion/full_motion.dart' as full_motion;
import 'motion/queue_transition.dart' as queue_transition;
import 'physics/pendulum.dart' as pendulum;
import 'physics/pendulum_stress.dart' as pendulum_stress;
import 'pipeline/full_frame.dart' as full_frame;
import 'pipeline/model_scaling.dart' as model_scaling;
import 'pipeline/multi_instance.dart' as multi_instance;
import 'pipeline/multi_model.dart' as multi_model;
import 'rendering/cpu_draw.dart' as cpu_draw;
import 'stress/expression_storm.dart' as expression_storm;
import 'stress/gc_pressure.dart' as gc_pressure;
import 'stress/motion_spam.dart' as motion_spam;

Future<int> main(List<String> argv) async {
  final args = _Args.parse(argv);

  // Gather every benchmark. Each module returns a list of CubismBenchmark
  // instances that collectively cover its variants — e.g. transcendentals
  // returns one benchmark per function, each of which emits three variants
  // (default/isLeaf/dartMath) from its own `measureAndEmit` override.
  final benchmarks = <CubismBenchmark>[
    ...transcendentals.all(),
    ...cardano.all(),
    ...matrix.all(),
    ...vector2.all(),
    ...breath.all(),
    ...eye_blink.all(),
    ...look.all(),
    ...pose.all(),
    ...curve_eval.all(),
    ...full_motion.all(),
    ...queue_transition.all(),
    ...pendulum.all(),
    ...pendulum_stress.all(),
    ...full_frame.all(),
    ...multi_instance.all(),
    ...multi_model.all(),
    ...model_scaling.all(),
    ...cpu_draw.all(),
    ...motion_spam.all(),
    ...expression_storm.all(),
    ...gc_pressure.all(),
  ];

  // Apply --filter. Filter is a substring match on the canonical key prefix
  // `module/name` — variant suffixes are matched too, so --filter=cosf@isLeaf
  // works.
  final filtered = args.filter == null
      ? benchmarks
      : benchmarks
          .where((b) => b.name.contains(args.filter!))
          .toList(growable: false);

  if (filtered.isEmpty) {
    stderr.writeln('No benchmarks matched filter "${args.filter}".');
    return 2;
  }

  stdout.writeln('Running ${filtered.length} benchmark(s)...');

  // Timing pass — always.
  final reporter = BenchReporter(allocTrackingEnabled: args.alloc);
  for (final bench in filtered) {
    stdout.writeln('  ${bench.name}');
    bench.measureAndEmit(reporter.results);
  }

  // Alloc pass — optional, second run under VM service.
  // --alloc: basic whole-heap byte delta per benchmark.
  // --devtools: detailed per-class allocation breakdown (implies --alloc).
  if (args.alloc || args.devtools) {
    final tracker = await AllocTracker.connect();
    if (tracker == null) {
      warnAllocUnavailable();
    } else {
      stdout.writeln(args.devtools
          ? 'Running detailed allocation pass (per-class breakdown)...'
          : 'Running allocation pass...');
      final allocResults = <String, int>{};
      final detailedResults = <String, List<Map<String, Object>>>{};
      for (final bench in filtered) {
        try {
          bench.setup();
          try {
            if (args.devtools) {
              // Detailed: per-class instance/byte deltas.
              final detailed = await tracker.detailedSample(() {
                for (int i = 0; i < bench.innerIterations; i++) {
                  bench.run();
                }
              });
              final perOp = detailed.totalBytes ~/ bench.innerIterations;
              allocResults[bench.name] = perOp;
              if (detailed.topClasses.isNotEmpty) {
                detailedResults[bench.name] = detailed.topClassesToJson();
              }
            } else {
              // Basic: whole-heap delta.
              final sample = await tracker.sample(() {
                for (int i = 0; i < bench.innerIterations; i++) {
                  bench.run();
                }
              });
              allocResults[bench.name] = sample.bytes ~/ bench.innerIterations;
            }
          } finally {
            bench.teardown();
          }
        } catch (e) {
          stderr.writeln('  [alloc] ${bench.name}: $e');
        }
      }
      await tracker.dispose();

      // Merge alloc numbers into timing results by key.
      for (int i = 0; i < reporter.results.length; i++) {
        final r = reporter.results[i];
        final bytes = allocResults[r.key];
        if (bytes == null) continue;
        // Merge per-class alloc data into metadata if available.
        final meta = Map<String, Object?>.of(r.metadata);
        final classData = detailedResults[r.key];
        if (classData != null) {
          meta['allocProfile'] = classData;
        }
        reporter.results[i] = BenchResult(
          module: r.module,
          name: r.name,
          variant: r.variant,
          opKind: r.opKind,
          framesPerOp: r.framesPerOp,
          perFrameNs: r.perFrameNs,
          meanNs: r.meanNs,
          medianNs: r.medianNs,
          p95Ns: r.p95Ns,
          p99Ns: r.p99Ns,
          stddevNs: r.stddevNs,
          opsPerSec: r.opsPerSec,
          samples: r.samples,
          iterationsPerSample: r.iterationsPerSample,
          bytesAllocPerOp: bytes,
          gcCount: r.gcCount,
          metadata: meta,
        );
      }
    }
  }

  reporter.printSummary();
  final outPath = args.output ?? 'benchmark/results.json';
  reporter.writeJson(outPath);
  stdout.writeln('\nWrote ${reporter.results.length} results to $outPath');
  return 0;
}

class _Args {
  final String? filter;
  final bool alloc;
  final bool devtools;
  final String? output;

  const _Args({
    this.filter,
    required this.alloc,
    required this.devtools,
    this.output,
  });

  static _Args parse(List<String> argv) {
    String? filter;
    String? output;
    bool alloc = false;
    bool devtools = false;
    for (final a in argv) {
      if (a == '--alloc') {
        alloc = true;
      } else if (a == '--devtools') {
        devtools = true;
        alloc = true; // --devtools implies --alloc
      } else if (a.startsWith('--filter=')) {
        filter = a.substring('--filter='.length);
      } else if (a.startsWith('--output=')) {
        output = a.substring('--output='.length);
      } else if (a == '--help' || a == '-h') {
        _printHelp();
        exit(0);
      } else {
        stderr.writeln('Unknown argument: $a');
        _printHelp();
        exit(2);
      }
    }
    return _Args(
        filter: filter, alloc: alloc, devtools: devtools, output: output);
  }

  static void _printHelp() {
    stdout.writeln('''
Usage: dart run benchmark/run_all.dart [options]

Options:
  --filter=<substr>   Only run benchmarks whose key contains <substr>.
                      Matches against "module/name@variant".
  --alloc             Enable basic allocation profiling (whole-heap byte delta).
                      Requires: --enable-vm-service --pause-isolates-on-exit=false.
  --devtools          Enable all DevTools integrations: per-class allocation
                      breakdown (metadata.allocProfile), structured developer.log
                      events. Implies --alloc. Requires --enable-vm-service.
  --output=<path>     Write results to <path> (default: benchmark/results.json).
  --help, -h          Show this message.

DevTools integration:

  Basic:
    dart run --enable-vm-service --pause-isolates-on-exit=false \\
        benchmark/run_all.dart --alloc

  Full (per-class allocations + structured logging):
    dart run --enable-vm-service --pause-isolates-on-exit=false \\
        benchmark/run_all.dart --devtools

  CPU profiling + timeline (separate tool):
    dart run --enable-vm-service --pause-isolates-on-exit=false \\
        tool/profile_pipeline.dart
''');
  }
}
