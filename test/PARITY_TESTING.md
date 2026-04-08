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

| Module | Max Abs Diff | Notes |
|--------|--------------|-------|
| math.easingSine | 9.6e-8 | Float vs double precision |
| math.cardanoAlgorithmForBezier | 6.0e-8 | Float vs double precision |
| math.matrixMultiply | 0 | Exact match |
| math.matrixInverse | 2.4e-7 | Float vs double precision |
| math.directionToRadian | 8.7e-8 | Float vs double precision |
| breath.sineWave | 1.4e-5 | Float vs double in cycle ratio |
| look.formula | 8.5e-7 | Float vs double precision |
| modelSetting.parsing | 0 | Exact string/int match |
| expression.weightSamples | 0 | Exact match |
| motion.curves | 9.6e-4 | Float vs double in BezierEvaluate |
| motionQueue.priorityTransition | 6.5e-5 | Float precision |
| physics.300frame | 3.4e-5 | Float precision over 300 iterations |
| pose.120frame | 0 | Exact match |

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
