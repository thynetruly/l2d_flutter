// Eye blink benchmark — 600 frames (10 s @ 60 fps) with deterministic RNG.
//
// Per the plan correction, CubismEyeBlink has NO libm FFI calls — it's a
// pure arithmetic state machine. This benchmark establishes the
// "almost-free" baseline against which the other effects are compared.
//
// Two variants:
//   steady     — RNG seed 42, 10s of running state machine.
//   transition — RNG seed 0, runs until the first blink completes (about
//                 1s of simulated time). Measures the closing/closed/opening
//                 transition cost in isolation from the idle interval loop.

import 'dart:math' as math;

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';

import '../fixtures.dart';
import '../harness.dart';

class _EyeBlinkBench extends CubismBenchmark {
  _EyeBlinkBench({required int frames, required int seed, required String variant})
      : _frames = frames,
        _seed = seed,
        super(
          module: 'effect',
          benchName: 'eyeBlink',
          variant: variant,
          innerIterations: 1,
          sampleCount: 30,
        );

  final int _frames;
  final int _seed;
  static const double _dt = 1.0 / 60.0;

  late ModelFixture _fixture;
  late CubismModel _model;
  late CubismEyeBlink _eye;

  @override
  void setup() {
    _fixture = Fixtures.haru();
    _model = _fixture.newModel();
    _eye = CubismEyeBlink(
      parameterIds: _fixture.settings.eyeBlinkParameterIds,
      random: math.Random(_seed),
      blinkingIntervalSeconds: 2.0,
    );
  }

  @override
  void run() {
    for (int i = 0; i < _frames; i++) {
      _eye.updateParameters(_model, _dt);
    }
  }

  @override
  void teardown() {
    _model.dispose();
    BenchSink.sink(_eye.state.index);
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
        'seed': _seed,
      };
}

List<CubismBenchmark> all() => [
      _EyeBlinkBench(frames: 600, seed: 42, variant: 'steady'),
      _EyeBlinkBench(frames: 60, seed: 0, variant: 'transition'),
    ];
