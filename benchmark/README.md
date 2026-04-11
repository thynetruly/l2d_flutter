# Cubism Framework performance benchmarks

Machine-readable performance suite for the Dart Cubism Framework port.
Every benchmark emits a `BenchResult` record with mean/median/p95/p99 ns/op
(plus per-frame ns for frame-loop benchmarks) and optional
bytes-allocated/op. Results land in `benchmark/results.json`, and
`compare_baseline.dart` gates regressions against `benchmark/baseline.json`.

## TL;DR

```
dart run benchmark/run_all.dart                   # full suite
dart run benchmark/run_all.dart --filter=math/cosf   # one function
dart run benchmark/compare_baseline.dart          # regression check
```

## Reading the numbers

**Every time value in this suite is reported as "time per op", and the
definition of "op" depends on the benchmark.** This is the #1 thing to get
right when reading results. The summary printer and `results.json` both
carry an explicit `opKind` tag so there's no ambiguity.

| `opKind` | "One op" means | Per-call / per-frame |
|---|---|---|
| `callBatch` | An unrolled batch of N calls (see benchmark docstring for the unroll factor). Used for math micro-benchmarks to amortise Stopwatch overhead. | Per-call ≈ `meanNs / N` |
| `singleCall` | One single function invocation. Used for matrix multiply, vector ops, etc. | `meanNs` IS per-call |
| `frameRun` | One full simulated frame loop (e.g. 300 frames of Haru physics). The result carries `framesPerOp` and a derived `perFrameNs` field. | Per-frame = `perFrameNs` |

### The summary printer

```
  benchmark/name                      per-op          per-frame            p95
  math/cosf                           74.7 ns/batch   —                    p95  81.8 ns
  math/matrixMultiply@aliased         56.3 ns/call    —                    p95  58.9 ns
  physics/pendulum@haru_8particles   547.0 µs/run    1.82 µs/frame         p95 574.0 µs
  pipeline/fullFrame@60fps            18.6 ms/run    62.0 µs/frame         p95  19.3 ms
```

- `per-op` is the raw mean. Its unit suffix (`/call`, `/batch`, `/run`)
  tells you what one op represents — don't confuse `/run` with `/frame`.
- `per-frame` is filled in only for `frameRun` benchmarks. When you see
  `18.6 ms/run` alongside `62.0 µs/frame`, it means one op ran 300 frames
  and took 18.6 ms total, averaging 62 µs per frame.
- `p95` is always the same scale as the `per-op` column (i.e. the p95 of
  the raw sample distribution, not derived per-frame).

### Common mistake

If you read `physics/pendulum@haru_8particles 547 µs` and think "ouch,
547 µs per frame" — **stop**. Check the `opKind`. It's `frameRun` with
`framesPerOp: 300`, so the per-frame cost is 547 ÷ 300 = 1.82 µs/frame.
Roughly 0.01% of a 60 fps frame budget. The printer shows both columns
so you don't have to do this arithmetic yourself — but if you're reading
`results.json` directly, look at `perFrameNs`, not `meanNs`.

### In `results.json`

```jsonc
{
  "module": "physics",
  "name": "pendulum",
  "variant": "haru_8particles",
  "opKind": "frameRun",        // how to interpret the numbers below
  "framesPerOp": 300,           // one op iterates 300 frames
  "meanNs": 546950.0,           // ns per full op = 547 µs per 300-frame run
  "perFrameNs": 1823.17,        // meanNs / framesPerOp = 1.82 µs/frame
  "p95Ns": 574000.0,
  ...
}
```

For `callBatch` and `singleCall` entries, `framesPerOp` and `perFrameNs`
are absent and the per-call cost is either `meanNs` directly (singleCall)
or `meanNs` divided by the unroll factor documented in the benchmark's
constructor comment (callBatch).

Allocation tracking and DevTools integration require the VM service:

```
# Basic allocation profiling (whole-heap byte delta per benchmark):
dart run --enable-vm-service --pause-isolates-on-exit=false \
    benchmark/run_all.dart --alloc

# Full DevTools integration (per-class allocation breakdown + structured
# developer.log events visible in DevTools Logging tab):
dart run --enable-vm-service --pause-isolates-on-exit=false \
    benchmark/run_all.dart --devtools

# Automated CPU profile + timeline export (separate tool):
dart run --enable-vm-service --pause-isolates-on-exit=false \
    tool/profile_pipeline.dart

# Interactive CPU profiling (manual DevTools connection):
dart run --enable-vm-service --pause-isolates-on-exit=false \
    tool/profile_pipeline.dart --interactive
```

## What's here

```
benchmark/
├── harness.dart              CubismBenchmark base + BenchResult + Reporter
├── alloc_tracker.dart        VM-service wrapper for per-op byte counts
├── fixtures.dart             Lazy loader for all 8 Samples/Resources/* models
├── run_all.dart              Orchestrator: enumerates, filters, runs, writes JSON
├── compare_baseline.dart     Regression gate
├── baseline.json             Committed perf contract (TEMPLATE — see below)
├── math/
│   ├── transcendentals.dart  LibM.cosf/sinf/... × {default, isLeaf, dartMath}
│   ├── cardano.dart          cardanoAlgorithmForBezier (5 branches)
│   ├── matrix.dart           CubismMatrix44 multiply / invert / translate
│   └── vector2.dart          CubismVector2 ops: addChain / length / normalize
├── effect/
│   ├── breath.dart           Haru breath, 360 frames
│   ├── eye_blink.dart        Pure arithmetic state machine (no FFI)
│   ├── look.dart             Linear-combination formula
│   └── pose.dart             Haru pose3.json, 120 frames
├── motion/
│   ├── curve_eval.dart       Synthetic one-curve motion, per segment type
│   ├── full_motion.dart      Haru idle motion, 600 frames
│   └── queue_transition.dart Priority crossfade, 120 frames
├── physics/
│   ├── pendulum.dart         Haru 8-particle pendulum, 300 frames
│   └── pendulum_stress.dart  Synthetic N rigs × M particles scaling curve
└── pipeline/
    ├── full_frame.dart       Headline metric: motion+eye+breath+physics+pose
    ├── multi_instance.dart   N × Haru (homogeneous) @ 60 & 120 fps
    └── multi_model.dart      2/4/8 distinct models @ 60 & 120 fps
```

## DevTools integration

The benchmark pipeline integrates with the following Dart DevTools
features. All of them work via the VM service — launch with
`--enable-vm-service --pause-isolates-on-exit=false`.

### CPU Profiler

`tool/profile_pipeline.dart` runs 600 frames of the full Haru pipeline
with `Timeline.startSync/finishSync` per phase, then:

- **Automated** (default): calls `VmService.getCpuSamples()` and writes
  `tool/cpu_profile.json`. Prints a top-10 function table to stdout.
- **Interactive** (`--interactive`): prints the VM Service URL so you
  can open DevTools, navigate to the CPU Profiler tab, and record
  manually. Waits for Enter before/after the loop.

The CPU profile JSON can be loaded into DevTools via the "Load" button
in the CPU Profiler tab, or analysed programmatically.

### Memory view (per-class allocation)

`--devtools` on `run_all.dart` captures per-class allocation breakdowns
via `AllocationProfile.members`. Each benchmark's `results.json` entry
gets an `allocProfile` key in `metadata`:

```jsonc
"metadata": {
  "allocProfile": [
    {"className": "CubismVector2", "instancesDelta": 750, "bytesDelta": 12000},
    {"className": "Float32List", "instancesDelta": 160, "bytesDelta": 10240},
    ...
  ]
}
```

This answers "which types are driving GC pressure?" without opening
DevTools Memory view manually.

### Timeline / Performance view

`tool/profile_pipeline.dart` calls `VmService.getVMTimeline()` and
writes `tool/timeline.json` in Chrome trace format. Open it in:
- `chrome://tracing` (paste the file)
- DevTools → Performance tab → Load

The per-phase summary printed to stdout shows total and per-frame
duration for each pipeline phase (motion, physics, eye_blink, etc.).

### Logging view

When running under the VM service, every benchmark emits structured
`developer.log()` events with category `cubism.benchmark`:

```jsonc
{"event": "start", "key": "physics/pendulum@haru_8particles"}
{"event": "result", "key": "physics/pendulum@haru_8particles", "meanNs": 547000, "perFrameNs": 1823}
```

These appear in the DevTools Logging tab and can be filtered by the
`cubism.benchmark` category. They coexist with the existing stdout
printing — BenchLog is a parallel channel, not a replacement.

### Not integrated (Flutter-only)

- **Performance view frame timing** — requires a Flutter app to capture
  `FrameTiming` build/raster splits. Will be added in the Flutter
  benchmark app (Phase 2).
- **Flutter inspector** — widget rebuild counts, repaint boundaries.
  Same: requires a Flutter app.
- **App size tool** — compile-time analysis, not runtime perf.
- **Debugger** — interactive, not automatable.

## Capturing a baseline

`benchmark/baseline.json` ships as a **template** with placeholder comments
but no numeric thresholds. On first use:

1. Run the full suite on your dev machine:
   ```
   dart run benchmark/run_all.dart
   ```
   This writes `benchmark/results.json`.

2. For each benchmark you care about, copy the observed `meanNs` into the
   matching entry in `baseline.json` as:
   ```json
   "math/cosf@default": {
     "prevMeanNs": 45.2,
     "maxMeanNs": 60
   }
   ```
   * `prevMeanNs` — the current "known good" number. Used for percent-
     regression gating (default 20% tolerance, see `defaults` at the top
     of `baseline.json`).
   * `maxMeanNs` — hard ceiling. Use only when you have a clear target
     (e.g. "this should never exceed X ns" for a known-cheap op).

3. For frame-time benchmarks (`pipeline/fullFrame`, `multiInstance`,
   `multiModel`), use `maxMsPerFrame` instead of `maxMeanNs`. The
   comparator divides by `metadata.frames` automatically.

4. For allocation-sensitive benchmarks (`math/matrixMultiply`,
   `math/vector2.addChain`), first capture a byte count via:
   ```
   dart run --enable-vm-service --pause-isolates-on-exit=false \
       benchmark/run_all.dart --alloc --filter=math
   ```
   then add `"maxBytesPerOp": N` to the baseline entry.

5. Commit the updated `baseline.json`.

## Interpreting a run

`run_all.dart` prints a one-line summary per benchmark. Each line shows:

```
  math/cosf@isLeaf          24.1 ns   p95=25.8ns
  physics/pendulum@haru...  2.34 ms   p95=2.51ms
  pipeline/fullFrame@60fps  0.51 ms   p95=0.58ms   (per-frame)
```

### When to open `results.json`

- **p95 >> mean** (e.g. p95 is 3× the mean): GC pause or FFI outlier.
  Usually benign if consistent across runs; investigate if the p95 grows
  over time.
- **`motion/fullMotion` metadata `segments > 300`**: motion is large; any
  per-segment optimisation wins compound.
- **`pipeline/multiModel` per-model `*_us` splits varying by >3×**:
  informational warning about which character is the bottleneck.
- **`pipeline/fullFrame@120fps` meanNs >> `@60fps` meanNs**: per-dt
  sub-stepping is scaling badly; physics needs investigation.

### Deciding whether to optimise

See `docs/PERFORMANCE.md` (Optimization tiers) for the decision rules.
The short version is: **no `lib/` edits until a benchmark justifies them**.

### Escalation path

When a benchmark flags "this is slow" but doesn't say why, use the
DevTools CPU sampler via:

```
dart run --enable-vm-service --profile-period=100 \
    --pause-isolates-on-exit=false tool/profile_pipeline.dart
```

The script prints a VM Service URI. Open DevTools, connect, and capture a
CPU profile during the 600-frame loop. Export as flame graph.

## Adding a new benchmark

1. Create a file under the appropriate module directory.
2. Extend `CubismBenchmark` from `harness.dart`. Implement `run()` and,
   when the measurement needs state, `setup()` and `teardown()`.
3. For multi-variant benchmarks (default vs isLeaf etc.) override
   `measureAndEmit` and call `runOne(overrideVariant: 'foo')` per variant.
4. Export a top-level `all()` function returning a list of benchmark
   instances, and add `import '...' as foo;` + `...foo.all(),` in
   `run_all.dart`.
5. Add a placeholder entry in `baseline.json` with a `_note`.
6. Re-run `dart run benchmark/run_all.dart --filter=your/new/bench` to
   sanity-check the output.

## Running tests

The benchmark suite is pure Dart. It requires the native Cubism Core
library on the same path the existing tests use (`Core/dll/linux/x86_64/
libLive2DCubismCore.so` on Linux; see `fixtures.dart:_corePath` for
platform mappings). `dart run benchmark/run_all.dart` loads the library
on first fixture access; no flutter harness is involved.
