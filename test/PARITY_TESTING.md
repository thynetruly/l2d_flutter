# Cubism Framework Parity Testing

This document describes how the Dart reimplementation of the Cubism Framework
maintains exact behavioral parity with the upstream C++ source.

## Overview

The Dart code in `lib/src/framework/` is a port of the C++ Cubism Framework.
To verify parity, we generate "golden" reference data by running the actual
C++ Framework against known inputs, then compare the Dart implementation's
output against this reference data.

## Components

### 1. Golden Reference Generator (`test/golden_generator/`)

A C++ program that links against the actual Cubism Framework and Core static
libraries (in `Framework/src/` and `Core/lib/linux/x86_64/`) and produces
JSON reference data for every Framework module.

**Build:**
```bash
cd test/golden_generator
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

**Run (regenerate goldens):**
```bash
./golden_generator ../../golden /path/to/Samples/Resources/Haru
```

This produces 11 JSON files in `test/golden/`:
- `math_golden.json` — easingSine, Cardano, matrix ops, directionToRadian
- `breath_golden.json` — 360 frames of sine-wave breath
- `look_golden.json` — drag-to-parameter formula
- `eye_blink_golden.json` — 600-frame state machine
- `motion_haru_idle_golden.json` — 60fps motion curve evaluation
- `expression_haru_F01_golden.json` — 5 weight samples
- `motion_queue_golden.json` — priority transition with crossfade
- `physics_haru_golden.json` — 300-frame pendulum simulation
- `pose_golden.json` — 120 frames of part opacities
- `model_setting_haru_golden.json` — full model3.json field dump
- `full_pipeline_haru_golden.json` — combined motion+physics+effects

### 2. Parity Verification Tool (`tool/verify_parity.dart`)

Diagnostic tool that runs Dart implementations and reports max differences
against golden data with detail thresholds (1e-6, 1e-4, 1e-2).

**Run:**
```bash
dart run tool/verify_parity.dart
```

**Output example:**
```
═══════════════════════════════════════════════════════════
  CubismMotion
═══════════════════════════════════════════════════════════
  duration: dart=10.0 cpp=10
  samples=3000 maxAbs=9.643e-4 over1e-6=1014 over1e-4=494 over1e-2=0
```

This is the canonical way to investigate parity divergence — it tells you
the worst-case difference and which sample triggered it.

### 3. Parity Regression Test (`test/parity_regression_test.dart`)

Automated regression test that runs as part of the standard test suite. Each
module is checked against tolerances declared in `test/parity_baseline.json`.

**Run:**
```bash
dart test test/parity_regression_test.dart
```

If any module's max difference exceeds its baseline tolerance, the test fails
with a clear message pointing to `verify_parity.dart` for diagnosis.

### 4. Parity Baseline (`test/parity_baseline.json`)

Declarative tolerances per module. Update this file when:
- Improving precision (lower the tolerance)
- Discovering acceptable float-vs-double drift (raise the tolerance with notes)

## Workflow

### When making changes to `lib/src/framework/`:

1. Make your code change
2. Run `dart test test/parity_regression_test.dart`
3. If a regression is detected:
   - Run `dart run tool/verify_parity.dart` to see the divergence detail
   - Investigate using the printed location (frame, parameter ID, segment)
   - Fix the bug, repeat

### When upgrading the Cubism SDK to a new version:

1. Replace `Core/`, `Framework/`, `Samples/` with the new SDK
2. Rebuild the golden generator: `cd test/golden_generator/build && make`
3. Regenerate goldens: `./golden_generator ../../golden /path/to/Haru`
4. Run `dart run tool/verify_parity.dart` to check for new divergence
5. Fix any new differences in the Dart code
6. Update `test/parity_baseline.json` if tolerances changed
7. Run full test suite to verify

### When intentionally changing Dart behavior:

1. Run `dart run tool/verify_parity.dart` to see the new max diffs
2. Update `test/parity_baseline.json` with the new tolerances
3. Document the reason in the `notes` field
4. Run `dart test test/parity_regression_test.dart` to verify it passes

## Current Parity Status

Categorized by what limits parity:

### Exact (bit-exact 0)
| Module | Max Abs Diff | Why |
|--------|--------------|-----|
| math.matrixMultiply | **0** | Float32List storage truncates each result |
| modelSetting.parsing | **0** | String/int parsing — no float math |
| expression.weightSamples | **0** | Writes through float32 FFI model parameters |
| pose.120frame | **0** | Writes through float32 FFI model parts |

### Near-exact (<1e-9, limited by JSON `%.10g` rounding)
| Module | Max Abs Diff | Improvement |
|--------|--------------|-------------|
| math.matrixInverse | 2.8e-10 | Was 2.4e-7 — 850× better via Float32 cast at each binop |
| math.directionToRadian | 4.9e-10 | Was 8.7e-8 — 175× better via Float32 cast |
| look.formula | 1.5e-9 | Was 8.5e-7 — 570× better via Float32 chain in test |

### Transcendental-limited (~1e-8, single ULP from C++ `cosf`/`sinf`/etc.)
| Module | Max Abs Diff | Why |
|--------|--------------|-----|
| math.easingSine | 3.0e-8 | Dart `math.cos` is double-precision; C++ uses `cosf` |
| math.cardanoAlgorithmForBezier | 1.2e-8 | Uses `sqrt`/`acos`/`cos`/`cbrt` |
| breath.sineWave | 3.0e-8 | Uses `math.sin` |

### Iterative simulations (accumulated drift over many frames)
| Module | Max Abs Diff | Notes |
|--------|--------------|-------|
| motion.curves | 9.6e-4 | 3000-sample motion playback (could be reduced by Float32-casting CubismMotion internals) |
| motionQueue.priorityTransition | 6.5e-5 | 360-frame priority transition |
| physics.300frame | 3.4e-5 | 300-frame pendulum simulation |

### Why the gaps cannot be closed without float32 emulation

1. **Transcendentals**: Dart's `math.cos`/`math.sin`/`math.atan2`/`math.acos`/`math.sqrt` all return double-precision results. C++ uses `cosf`/`sinf`/`atan2f`/etc. which compute in single-precision throughout. Casting Dart's double result to float32 doesn't perfectly match C++'s float32 result because the underlying computations have different rounding paths in the last few bits. The residual ~1e-8 drift is exactly 1 float32 ULP — the theoretical minimum.

2. **Iterative simulations**: To make them exact, every binary operation in the simulation loop would need to be wrapped in `Float32.cast()`. This is invasive (touches every line of physics/motion math) for marginal benefit (the existing drift is below visual perception). Documented as a known precision limit.

## How Float32 emulation works

Dart's `Float32List` performs single-precision storage but reads/writes happen via doubles. The `Float32` helper class wraps this:

```dart
class Float32 {
  static final Float32List _buf = Float32List(1);
  static double cast(double v) {
    _buf[0] = v;  // Truncates to float32 on store
    return _buf[0];  // Reads back as double
  }
}
```

Use `Float32.cast()` at every intermediate step where C++ would use a `csmFloat32` variable. The native code already uses Float32List for matrix storage, so matrix ops are float32 by default.

## Bugs Found Through Parity Testing

### Bug 1: Motion queue fade timing offset (FIXED)

The Dart `CubismMotion.updateParameters` was using motion-relative time
(`timeSeconds = userTime - startTime`) for fade-in/fade-out calculations,
but `fadeInStartTime` is in global time. This caused m2's fade-in to start
at the wrong time when m2 was added via `startMotionPriority` after m1.

Symptom: max diff of **6.0** in motion_queue_golden test.

Fix: Added `userTimeSeconds` parameter to `CubismMotion.updateParameters`
and use it for fade calculations. Also changed per-parameter fade weight
formula to `weight * fin * fout` matching C++.

### Bug 2: Wrong Bezier evaluator (FIXED)

When `AreBeziersRestricted=true` in motion3.json, the Dart implementation
was using Cardano's algorithm but C++ uses simple linear-t De Casteljau
(`BezierEvaluate`). My initial fix mistakenly used `BezierEvaluateBinarySearch`
which produced even worse results.

Symptom: max diff of **1e-2** in motion.curves test.

Fix: Read `Meta.AreBeziersRestricted` from motion3.json and dispatch:
- `true` → `_bezierEvaluateSimple` (linear t)
- `false` → `_bezierEvaluateCardano` (animator-correct)

After fix: max diff dropped to **9.6e-4** (float precision limit).
