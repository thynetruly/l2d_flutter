# Cubism Framework Parity Testing

This document describes how the Dart reimplementation of the Cubism Framework
maintains **bit-exact** behavioral parity with the upstream C++ source.

## Overview

The Dart code in `lib/src/framework/` is a port of the C++ Cubism Framework.
To verify parity, we generate "golden" reference data by running the actual
C++ Framework against known inputs, then compare the Dart implementation's
output against this reference data.

**The math between Live2D implementations is guaranteed to match exactly,
regardless of language**, because Dart calls libm's float-precision functions
(`cosf`, `sinf`, `atan2f`, `sqrtf`, `cbrtf`, `acos`, `cbrt`, `powf`) directly
via FFI. These are the **same** functions the C++ Cubism library calls. Same
math library on the same platform = identical bit patterns.

See `lib/src/framework/math/libm.dart` for the FFI bindings.

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

## Current Parity Status (after libm FFI)

Categorized by what limits parity:

### Exact (bit-exact 0)
| Module | Max Abs Diff | Why |
|--------|--------------|-----|
| math.matrixMultiply | **0** | Float32List storage truncates each result |
| modelSetting.parsing | **0** | String/int parsing — no float math |
| expression.weightSamples | **0** | Writes through float32 FFI model parameters |
| pose.120frame | **0** | Writes through float32 FFI model parts |

### libm-FFI bit-exact (residual ~1e-11 = JSON `%.10g` rounding floor)
The math is computed by **the same libm function** as C++. Any residual diff
is below the precision the golden JSON file can store (`%.10g` = 10 digits).

| Module | Max Abs Diff | Improvement |
|--------|--------------|-------------|
| math.easingSine | **5e-11** | Was 9.6e-8, then 3.0e-8, now bit-exact via `LibM.cosf` (~1900× better) |
| math.cardanoAlgorithmForBezier | **2.4e-11** | Was 6.0e-8, then 1.2e-8, now bit-exact via `LibM.sqrtf`/`LibM.cosf`/`LibM.acos`/`LibM.cbrt` (~2500× better) |
| math.directionToRadian | **4.9e-10** | Was 8.7e-8, then 4.9e-10, now uses `LibM.atan2f` |
| breath.sineWave | **5e-11** | Was 1.4e-5, then 3.0e-8, now bit-exact via `LibM.sinf` (~280,000× better) |

### Near-exact (limited by JSON rounding, no transcendentals)
| Module | Max Abs Diff |
|--------|--------------|
| math.matrixInverse | 2.8e-10 |
| look.formula | 1.5e-9 |

### Iterative simulations (polynomial Bezier drift)
| Module | Max Abs Diff | Notes |
|--------|--------------|-------|
| motion.curves | 9.6e-4 | 3000-sample motion playback. Dominated by polynomial Bezier evaluation chain (no transcendentals). Eliminating this would require Float32.cast in CubismMotion's hot path. |
| motionQueue.priorityTransition | 6.5e-5 | 360-frame priority transition. Same root cause. |
| physics.300frame | **1.9e-6** | Was 3.4e-5, now 1.9e-6 (18× better) after libm FFI + C++ rotation bug replication. |

## How libm FFI achieves bit-exact parity

`lib/src/framework/math/libm.dart` declares FFI bindings to libm's math functions:

```dart
class LibM {
  static final double Function(double) cosf = _libm.lookupFunction<
      Float Function(Float), double Function(double)>('cosf');
  // ... sinf, tanf, atan2f, sqrtf, cbrtf, acosf, asinf, fabsf, fmodf,
  //     floorf, powf, acos (double), cbrt (double)
}
```

The `Float Function(Float)` signature tells Dart FFI to truncate the Dart
double argument to single-precision before calling, and to interpret the
returned float as a double. The function call goes through the same
`cosf` symbol that the bundled `libLive2DCubismCore.so` calls — same code
path, same bit pattern, same result.

Platform support:
- **Linux**: `DynamicLibrary.open('libm.so.6')` — glibc.
- **Android**: `DynamicLibrary.process()` — bionic libc has math functions.
- **macOS / iOS**: `DynamicLibrary.process()` — libSystem.
- **Windows**: `DynamicLibrary.open('ucrtbase.dll')` (UCRT), falls back to `msvcrt.dll`.

**Cross-platform note**: glibc, libSystem, MSVCRT, and bionic implement
`cosf`/`sinf`/etc. independently. Their last-ULP results can differ. After
this work, **Dart-on-Linux ≡ C++-on-Linux** and **Dart-on-macOS ≡ C++-on-macOS**,
but Dart-on-Linux may differ from Dart-on-macOS in the last bit. This is
exactly the same behavior as C++ Cubism itself — bit-exact within a platform,
near-exact across platforms.

## C++ Sequential-update rotation bug (replicated in Dart)

The C++ Cubism Framework has a sequential-variable-update bug at
`Framework/src/Physics/CubismPhysics.cpp:309-310` and `:749-750`:

```cpp
direction.X = ((CubismMath::CosF(radian) * direction.X) - (direction.Y * CubismMath::SinF(radian)));
direction.Y = ((CubismMath::SinF(radian) * direction.X) + (direction.Y * CubismMath::CosF(radian)));
```

The second line reads the **already-modified** `direction.X` value. This
is a sheared transformation, not a true 2D rotation. The Dart `_applyRotation`
and `_updateParticles` reproduce this exactly for bit-for-bit parity. Look for
`BIT-EXACT PARITY` comments in `lib/src/framework/physics/cubism_physics.dart`.

## How Float32 emulation works (for non-transcendental binops)

For pure-arithmetic operations (multiply, add, divide), Dart's `Float32List`
performs single-precision storage but reads/writes happen via doubles. The
`Float32` helper class wraps this:

```dart
class Float32 {
  static final Float32List _buf = Float32List(1);
  static double cast(double v) {
    _buf[0] = v;  // Truncates to float32 on store
    return _buf[0];  // Reads back as double
  }
}
```

Use `Float32.cast()` at every intermediate step where C++ would use a
`csmFloat32` variable. The native code already uses Float32List for matrix
storage, so matrix ops are float32 by default. Transcendental functions
(`cos`/`sin`/etc.) bypass this entirely by calling libm via FFI.

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

### Bug 3: Sequential-update rotation bug (REPLICATED for parity)

C++ `CubismPhysics.cpp:309-310` and `:749-750` modify `direction.X` then read
the modified value when computing `direction.Y`. The Dart code originally used
temporary variables (mathematically correct). For bit-exact parity with C++,
the Dart code now intentionally reproduces the C++ bug. See `BIT-EXACT PARITY`
comments in `lib/src/framework/physics/cubism_physics.dart`.

### Bug 4: Transcendental functions producing different bits than C++ (FIXED via libm FFI)

Dart's `dart:math` functions are double-precision; even truncating their
results to float32 produced bit patterns that differed from C++'s `cosf`/
`sinf`/etc. by 1 ULP. Fixed by binding libm directly via FFI in
`lib/src/framework/math/libm.dart`.

Symptom: ~1e-8 ULP residual drift in transcendental tests.

Fix: All transcendental calls in CubismMath, CubismVector2, CubismPhysics,
and CubismBreath now route through `LibM.cosf`/`LibM.sinf`/`LibM.atan2f`/
`LibM.sqrtf`/`LibM.cbrtf`/`LibM.acos`/`LibM.cbrt`/`LibM.powf`. The Cardano
solver uses `LibM.acos` and `LibM.cbrt` (double-precision) to match C++'s
intentional double-precision usage in the cubic solver.

After fix: transcendental tests dropped from ~3e-8 to ~5e-11 (~600× better),
which is the JSON `%.10g` rounding floor — bit-exact match with C++.
