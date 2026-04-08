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

**Decision data** (Linux x86_64 dev box, Dart 3.11.4 / Flutter 3.41.6):

| Function | default (ns) | `isLeaf` (ns) | Speedup | dart:math (ns) |
|---|---:|---:|---:|---:|
| `cosf` | 227.8 | 75.1 | **3.0×** | 96.0 |
| `sinf` | 258.5 | 70.7 | **3.7×** | 94.1 |
| `sqrtf` | 234.9 | 64.2 | **3.7×** | 86.9 |
| `acos` | 247.6 | 95.9 | **2.6×** | 96.0 |
| `cbrt` | 266.0 | 135.8 | **2.0×** | 161.1 |
| `atan2f` | 260.8 | 131.4 | **2.0×** | 171.8 |
| `powf` | 243.4 | 105.3 | **2.3×** | 182.0 |

Every single-precision libm call via FFI became **faster than `dart:math`**
with `isLeaf: true`. The Tier-1 ship criterion (≥10% faster than default)
is massively exceeded — typical speedup is 2–4×.

**Downstream impact** measured on the same run, after applying the hint to
all 12 bindings:

| Benchmark | Before isLeaf | After isLeaf | Speedup |
|---|---:|---:|---:|
| `math/cardanoAlgorithmForBezier` | 678.9 ns | 559.6 ns | 1.21× |
| `math/quadraticEquation` | 66.2 ns | 42.6 ns | 1.55× |
| `math/getEasingSine` | 138.5 ns | 82.1 ns | 1.69× |
| `math/vector2.length` | 26.2 ns | 12.4 ns | 2.11× |
| `math/vector2.normalize` | 29.7 ns | 18.9 ns | 1.57× |
| `motion/curveEval@bezierCardano` | 2.01 µs | 1.65 µs | 1.22× |
| `physics/pendulum@haru_8particles` | 738 µs | 547 µs | **1.35×** |
| `physics/pendulumStress@10rigs_10p` | 6.73 ms | 4.72 ms | 1.43× |

Pipeline-level benchmarks (`pipeline/fullFrame`, `multiInstance`, `multiModel`)
stayed within measurement noise on this dev box because the **per-frame cost
is already ~60 µs — well under the 16.6 ms budget** — so the ~5 µs/frame
isLeaf saving is lost in run-to-run variance. The wins show up more clearly
on libm-heavy slices: physics improved 26–43% depending on particle count,
Cardano improved 22%, getEasingSine 69%.

**Parity:** full test suite — 195 `dart test` tests (including 13 parity
regression tests) and 6 `flutter test test/widgets/` tests — all passed
unchanged after the edit. `isLeaf` is safe for every function in
`libm.dart` because they are pure numeric routines with no callback into
Dart and no heap access.

### Tier 1 — future invocation

The `math/cosf@isLeaf` variant in `benchmark/math/transcendentals.dart` is
still wired up so a future regression that reverts or contaminates the
FFI path (e.g. someone adds a `Finalizable` bound to a libm argument,
which disables isLeaf) will show as a large slowdown in the default
variant vs the local `isLeaf` variant. Keep the variant benchmark.

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
