# Cubism Framework performance benchmarks

Machine-readable performance suite for the Dart Cubism Framework port.
Every benchmark emits a `BenchResult` record with mean/median/p95/p99 ns/op
and optional bytes-allocated/op. Results land in `benchmark/results.json`,
and `compare_baseline.dart` gates regressions against
`benchmark/baseline.json`.

## TL;DR

```
dart run benchmark/run_all.dart                   # full suite
dart run benchmark/run_all.dart --filter=math/cosf   # one function
dart run benchmark/compare_baseline.dart          # regression check
```

Allocation tracking requires launching under the VM service:

```
dart run --enable-vm-service --pause-isolates-on-exit=false \
    benchmark/run_all.dart --alloc
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
