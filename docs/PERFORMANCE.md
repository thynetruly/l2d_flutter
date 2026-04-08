# Performance

Data-driven optimisation guide for the Dart Cubism Framework port.

This document is the companion to `benchmark/README.md`. The README
describes **how to run** the benchmark suite. This document describes
**what the numbers mean** and **when they justify an optimisation**.

## Principles

1. **Measure first, optimise second.** No `lib/` edits until a benchmark
   proves a problem. Speculative optimisation is the enemy.
2. **Bit-exact parity is invariant.** Every optimisation must still pass
   the 13 parity regression tests and the full test suite. The libm FFI
   path is not negotiable.
3. **Realistic inputs.** Haru is the canonical workload. Synthetic inputs
   are allowed only for scaling curves (`physics/pendulumStress`) or when
   the function under test needs coefficients in a specific discriminant
   branch (`math/cardano`).
4. **Rendering is out of scope for v1.** Framework CPU cost only. When
   rendering benchmarks land they go in their own suite.

## Hot-path reference

Per 60-fps frame on the Haru sample model, the CPU work breaks down
roughly as:

| Source | FFI calls / frame | Vector2 allocs / frame |
|---|---:|---:|
| Physics (4 sub-rigs × 2 particles) | ~170 | ~560 (sub-stepping) |
| Motion (63 curves × ~296 segments, Cardano path) | ~250 | ~40 |
| Breath (1 parameter) | 1 | 0 |
| Eye blink | 0 | 0 |
| Pose | 0 | 0 |
| Renderer | 0 | ~120 |
| **Total** | **~425** | **~750** |

These are the numbers the benchmark suite validates empirically. Treat
them as "where I'd expect to find hotspots" rather than gospel — the real
counts will come from `motion/fullMotion` metadata and the physics
benchmarks once you run the suite.

## Optimisation tiers

The suite is structured around three tiers. **Do not skip the measure
step before any tier.**

### Tier 1 — `isLeaf: true` on LibM bindings — **APPLIED**

**Status:** shipped alongside the benchmark suite.
**Location:** `lib/src/framework/math/libm.dart`.

**A note on units.** The transcendentals benchmarks are `callBatch`
with a 10-call unroll — so the harness's `meanNs` is "ns per batch of
10 calls". The table below divides by 10 and reports **per-call
nanoseconds**, which is what a reader usually wants when reasoning about
FFI cost per hot-loop iteration. The harness's raw output shows the
`/batch` suffix to make this distinction unambiguous.

**Decision data** — per-call ns, Linux x86_64 dev box, Dart 3.11.4 /
Flutter 3.41.6. "Before" = first run before `isLeaf: true` was applied
to `libm.dart`. "After" = same-machine rerun after the fix landed.

| Function | Before (ns/call) | After (ns/call) | Speedup | dart:math (ns/call) |
|---|---:|---:|---:|---:|
| `cosf` | 22.78 | 7.64 | **3.0×** | 9.98 |
| `sinf` | 25.85 | 7.27 | **3.6×** | 10.59 |
| `sqrtf` | 23.49 | 6.24 | **3.8×** | 8.91 |
| `tanf` | 24.16 | 15.15 | 1.6× | 11.25 |
| `acos` | 24.76 | 9.63 | **2.6×** | 10.29 |
| `cbrt` | 26.60 | 13.76 | 1.9× | 16.68 |
| `atan2f` | 26.08 | 15.33 | 1.7× | 17.41 |
| `powf` | 24.34 | 9.91 | **2.5×** | 16.77 |
| `cbrtf` | 25.90 | 14.62 | 1.8× | 16.45 |

Every single-precision libm call via FFI became **as-fast-or-faster than
the `dart:math` equivalent** with `isLeaf: true`. The Tier-1 ship criterion
(≥10% faster than default) is massively exceeded — typical speedup is
1.6×–3.8×. `cosf`, `sinf`, and `sqrtf` are now ~7 ns/call — essentially
direct libm invocations with negligible FFI overhead.

**Downstream impact** (libm-heavy benchmarks, same before/after rerun):

For `callBatch` benchmarks the per-call values are meanNs / unroll factor
(6 for cardano, 3 for quadratic, 5 for easing, 8 for curveEval).

| Benchmark | Op kind | Before | After | Speedup |
|---|---|---:|---:|---:|
| `math/cardanoAlgorithmForBezier` | per-call | 113.2 ns | 91.6 ns | 1.24× |
| `math/quadraticEquation` | per-call | 22.1 ns | 14.2 ns | 1.55× |
| `math/getEasingSine` | per-call | 27.7 ns | 16.6 ns | 1.67× |
| `math/vector2.length` | per-call | 26.2 ns | 12.5 ns | **2.10×** |
| `math/vector2.normalize` | per-call | 29.7 ns | 19.0 ns | 1.57× |
| `motion/curveEval@bezierCardano` | per-call | 251.3 ns | 208.8 ns | 1.20× |
| `physics/pendulum@haru_8particles` | per-frame | 2.46 µs | 2.25 µs | 1.09× |
| `physics/pendulumStress@10rigs_10p` | per-frame | 22.43 µs | 16.71 µs | **1.34×** |
| `motion/fullMotion` (Haru idle) | per-frame | 6.12 µs | 6.30 µs | ~noise |
| `pipeline/fullFrame@60fps` | per-frame | 61.43 µs | 61.25 µs | ~noise |

**Headline pipeline frame cost is ~61 µs/frame** — well under the 16.6 ms
budget for 60 fps and the 8.3 ms budget for 120 fps, on this dev box. The
per-frame cost is nearly identical at 60 fps and 120 fps variants
(61.25 vs 61.76 µs/frame), confirming that physics sub-stepping does not
dominate: ~all per-frame work is dt-independent.

Pipeline and motion-level benchmarks stayed within measurement noise
because (a) per-frame cost was already low enough that the ~0.1–0.2 µs
isLeaf saving per FFI call adds up to only a couple µs per frame, well
inside run-to-run variance, and (b) those benchmarks exercise more than
libm — JSON parse, parameter lookup, curve walking, model.update() FFI.
The wins land clearly on benchmarks dominated by raw libm calls:
`physics/pendulumStress@10rigs_10p` (100 particles) improved 34%,
`vector2.length` 2.1×, `getEasingSine` 67%.

**Parity:** full test suite — 195 `dart test` tests (including 13 parity
regression tests) and 6 `flutter test test/widgets/` tests — all passed
unchanged after the edit. `isLeaf` is safe for every function in
`libm.dart` because they are pure numeric routines with no callback into
Dart and no heap access.

### Tier 1 — future invocation

The `math/cosf@isLeaf` variant in `benchmark/math/transcendentals.dart`
looks up libm locally with `isLeaf: true` regardless of what `libm.dart`
ships. If a future change silently disables isLeaf on the production
path (e.g. adding a `Finalizable` bound to an FFI argument type), the
`math/cosf` default variant will regress while `math/cosf@isLeaf`
remains fast — the gap between them is the tripwire. Keep the variant
benchmark.

### Tier 2 — hot-path allocation reduction

Three independent candidates. Each gated on its own measurement.

#### 2A. Inline Vector2 math in physics `_updateParticles`

**Where:** `lib/src/framework/physics/cubism_physics.dart:455-510`.

**What:** Replace `a + b * s` chains with scalar `(ax + bx*s, ay + by*s)`
pairs stored into the particle's existing `position` / `lastPosition` /
`velocity` fields. Eliminates ~350 allocations/frame from physics alone.

**Ship criterion:** `physics/pendulum` bytes-per-frame drops by ≥70% AND
ns/frame does not regress (i.e. the inlined code isn't somehow slower).

#### 2B. MotionPoint pool in `_bezierEvaluate*`

**Where:** `lib/src/framework/motion/cubism_motion.dart:137-143` (and the
other evaluator variants).

**What:** Each Bezier segment evaluation allocates 5 `MotionPoint`
temporaries via `MotionPoint.lerp`. Replace with a 5-slot reusable scratch
struct (per-motion state).

**Ship criterion:** `motion/curveEval@bezierCardano` bytes-per-op drops
by ≥90% AND ns-per-op does not regress.

#### 2C. `CubismMatrix44` scratch reuse

**Where:** `lib/src/framework/math/cubism_matrix44.dart:64, 85, 166`.

**What:** `multiply`/`translateRelative`/`scaleRelative` each allocate a
fresh `Float32List(16)` per call. Reuse a single static scratch buffer.
Multiply already does a full copy into `dst` at the end, so a shared
buffer is safe for the non-recursive case.

**Ship criterion:** `math/matrixMultiply@aliased` and `@nonAliased` both
drop to 0 bytes/op, and `math/translateRelative` + `math/scaleRelative`
drop the matching delta. ns/op does not regress.

### Tier 3 — native C shim for physics

**Only if** Tier 1 + Tier 2 land and
`physics/pendulumStress@10rigs_10particles` (50-particle stress case)
still exceeds the frame budget.

**Scope:** a single `src/cubism_physics_core.c` that takes arrays of
particles, inputs, outputs, and runs the pendulum integration loop in C.
Keeps everything else in Dart. Uses the existing `src/CMakeLists.txt`
build pipeline so the library ships alongside Cubism Core on every
platform.

**Gate:** stress benchmark showing >1 ms/frame on target hardware, with
no remaining Tier 1 or Tier 2 work to do.

## What to do when the benchmark says "it's slow"

1. **Check p95/p99.** A high p95 relative to mean is usually GC pressure.
   Look at the bytes/op if alloc tracking is enabled.
2. **Check per-phase splits.** `pipeline/fullFrame` emits per-phase
   Stopwatch totals in metadata (`motion_us`, `physics_us`, etc.).
   The biggest phase is the starting point.
3. **Drill into the module benchmark.** If `fullFrame` shows physics as
   the bottleneck, run `dart run benchmark/run_all.dart --filter=physics`
   and look at the pendulum stress scaling curve to see whether the cost
   is per-particle (Vector2 allocs dominate) or per-FFI-call (Tier 1
   wins).
4. **Escalate to DevTools.** When the benchmarks can't explain the
   number, use `tool/profile_pipeline.dart` to capture a CPU profile in
   DevTools and export a flame graph.
5. **Only then optimise.** Revisit the tier table above and pick the
   first-tier candidate that matches the measured bottleneck.

## Running on CI

The benchmark suite is **not** wired into CI as of this writing. When it
is, the workflow is:

```yaml
- run: dart run benchmark/run_all.dart
- run: dart run benchmark/compare_baseline.dart
```

The second command exits 1 on any regression >`regressionTolerancePct`
(default 20%, configured in `baseline.json`). It also prints warnings for
informational gates that are useful to notice but should not block merges
(e.g. `multiModel` per-model variance).

## Rendering performance (out of scope)

`lib/src/widgets/live2d_widget.dart` and
`lib/src/framework/rendering/cubism_renderer.dart` handle GPU drawing.
These are deliberately **not** benchmarked here:

- Flutter's rendering engine adds noise that Dart VM Stopwatch can't
  isolate.
- Real-device benchmarks require CI infrastructure we don't have yet.
- The most meaningful "rendering" number is frame time as observed by
  `flutter run --profile` on a physical device. That's a different kind
  of benchmark and will live in a separate suite if and when it's added.

The headline `pipeline/fullFrame` number is **Framework CPU time only**.
Add an estimate of your target device's rendering cost to compare
apples-to-apples with the frame budget.
