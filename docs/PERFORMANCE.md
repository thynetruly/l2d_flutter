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

### Tier 1 — `isLeaf: true` on LibM bindings

**Candidate:** add `isLeaf: true` to all 12 FFI bindings in
`lib/src/framework/math/libm.dart:73-103`.

**How to decide:**

1. Run `dart run benchmark/run_all.dart --filter=math/transcendentals`.
2. Compare `math/cosf@isLeaf` mean to `math/cosf@default` mean.
3. If the `isLeaf` variant is faster by ≥10%, it's worth landing. Repeat
   for every function that shows the improvement.
4. Apply the hint to `libm.dart` (one-line change per binding).
5. Re-run the suite. `physics/pendulum` and `motion/fullMotion` should
   both improve by roughly the ratio of their FFI count × (default - isLeaf)
   / total frame time.
6. Run `dart test` + `flutter test test/widgets/` to confirm bit-exact
   parity is preserved. `isLeaf` is safe for pure libm functions (no Dart
   heap access, no callback into Dart).

**Expected:** ~15–20 µs/frame reduction (~10–15% of FFI overhead shaved).
**Risk:** near zero.

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
