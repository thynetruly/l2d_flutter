// Live2D Flutter frame rendering benchmark.
//
// Measures the full Flutter rendering pipeline: Ticker → controller.update →
// CubismRenderer.drawModel(canvas) → canvas.drawVertices + ImageShader →
// compositing. This is the GPU-side cost that the pure-Dart benchmark suite
// at benchmark/ cannot measure.
//
// Scenarios:
//   single_model        — 1 × Live2DWidget with Haru + textures + physics.
//   two_models          — 2 × Live2DWidget side-by-side in a Row.
//   four_models         — 2×2 grid of Live2DWidgets.
//   single_model_no_tex — 1 × Live2DWidget without textures (isolates
//                          vertex submission cost from texture/shader cost).
//
// Each scenario warms up for 30 frames, then measures 300 frames via
// watchPerformance (under flutter drive --profile) or manual FrameTiming
// collection (under flutter test).
//
// Run:
//   flutter test integration_test/live2d_benchmark_test.dart
//   flutter drive --driver=test_driver/perf_test.dart \
//       --target=integration_test/live2d_benchmark_test.dart --profile

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:l2d_flutter_plugin/l2d_flutter_plugin.dart';

import 'benchmark_helpers.dart';

const int _warmupFrames = 30;
const int _measureFrames = 300;
const Duration _frameDuration = Duration(milliseconds: 16);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Live2D frame rendering benchmark', () {
    testWidgets('single_model — 300 frames', (tester) async {
      final controller = await createHaruController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: Live2DWidget(
                controller: controller,
                autoUpdate: true,
                backgroundColor: const Color(0xFF808080),
              ),
            ),
          ),
        ),
      );

      // Warmup: let JIT + shader compilation settle.
      for (int i = 0; i < _warmupFrames; i++) {
        await tester.pump(_frameDuration);
      }

      // Measure with watchPerformance (captures FrameTiming under profile
      // mode). Falls back gracefully under debug/test mode.
      await _measureFrames300(binding, tester, 'single_model');

      controller.dispose();
    });

    testWidgets('two_models — 300 frames', (tester) async {
      final c1 = await createHaruController();
      final c2 = await createHaruController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: Live2DWidget(
                      controller: c1,
                      autoUpdate: true,
                      backgroundColor: const Color(0xFF808080)),
                ),
                Expanded(
                  child: Live2DWidget(
                      controller: c2,
                      autoUpdate: true,
                      backgroundColor: const Color(0xFF909090)),
                ),
              ],
            ),
          ),
        ),
      );

      for (int i = 0; i < _warmupFrames; i++) {
        await tester.pump(_frameDuration);
      }

      await _measureFrames300(binding, tester, 'two_models');

      c1.dispose();
      c2.dispose();
    });

    testWidgets('four_models — 300 frames', (tester) async {
      final controllers = <Live2DController>[];
      for (int i = 0; i < 4; i++) {
        controllers.add(await createHaruController());
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      for (int i = 0; i < 2; i++)
                        Expanded(
                          child: Live2DWidget(
                              controller: controllers[i],
                              autoUpdate: true,
                              backgroundColor: const Color(0xFF808080)),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      for (int i = 2; i < 4; i++)
                        Expanded(
                          child: Live2DWidget(
                              controller: controllers[i],
                              autoUpdate: true,
                              backgroundColor: const Color(0xFF909090)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      for (int i = 0; i < _warmupFrames; i++) {
        await tester.pump(_frameDuration);
      }

      await _measureFrames300(binding, tester, 'four_models');

      for (final c in controllers) {
        c.dispose();
      }
    });

    testWidgets('single_model_no_texture — 300 frames', (tester) async {
      // Load controller WITHOUT textures — isolates vertex transform +
      // blend mode cost from ImageShader + texture sampling cost. The
      // delta between this and single_model is the per-frame texture cost.
      ensureCoreLoaded();
      final controller = Live2DController();
      controller.loadFromBytes(
        mocBytes: File('$projectRoot/Samples/Resources/Haru/Haru.moc3')
            .readAsBytesSync(),
        settingsJson:
            File('$projectRoot/Samples/Resources/Haru/Haru.model3.json')
                .readAsStringSync(),
      );
      final physPath =
          '$projectRoot/Samples/Resources/Haru/Haru.physics3.json';
      if (File(physPath).existsSync()) {
        controller.loadPhysics(File(physPath).readAsStringSync());
      }
      final motionPath =
          '$projectRoot/Samples/Resources/Haru/motions/haru_g_idle.motion3.json';
      if (File(motionPath).existsSync()) {
        controller.startMotion(File(motionPath).readAsStringSync());
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: Live2DWidget(
                controller: controller,
                autoUpdate: true,
                backgroundColor: const Color(0xFF808080),
              ),
            ),
          ),
        ),
      );

      for (int i = 0; i < _warmupFrames; i++) {
        await tester.pump(_frameDuration);
      }

      await _measureFrames300(binding, tester, 'single_model_no_texture');

      controller.dispose();
    });
  });
}

/// Runs 300 frames under watchPerformance when available, falling back to
/// manual FrameTiming collection otherwise.
Future<void> _measureFrames300(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String reportKey,
) async {
  try {
    await binding.watchPerformance(() async {
      for (int i = 0; i < _measureFrames; i++) {
        await tester.pump(_frameDuration);
      }
    }, reportKey: reportKey);
  } catch (_) {
    // watchPerformance failed (e.g. no VM service under flutter test).
    // Fall back to manual FrameTiming collection.
    final timings = <FrameTiming>[];
    void timingsCallback(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(timingsCallback);

    for (int i = 0; i < _measureFrames; i++) {
      await tester.pump(_frameDuration);
    }
    // Wait for any remaining batched FrameTiming reports.
    await tester.pump(const Duration(seconds: 2));

    SchedulerBinding.instance.removeTimingsCallback(timingsCallback);

    // Summarise and report.
    if (timings.isNotEmpty) {
      final buildTimesUs = timings
          .map((t) => t.buildDuration.inMicroseconds)
          .toList()
        ..sort();
      final rasterTimesUs = timings
          .map((t) => t.rasterDuration.inMicroseconds)
          .toList()
        ..sort();

      final summary = {
        'frame_count': timings.length,
        'average_frame_build_time_millis':
            _mean(buildTimesUs) / 1000.0,
        '90th_percentile_frame_build_time_millis':
            _percentile(buildTimesUs, 0.90) / 1000.0,
        '99th_percentile_frame_build_time_millis':
            _percentile(buildTimesUs, 0.99) / 1000.0,
        'worst_frame_build_time_millis':
            buildTimesUs.last / 1000.0,
        'average_frame_rasterizer_time_millis':
            _mean(rasterTimesUs) / 1000.0,
        '90th_percentile_frame_rasterizer_time_millis':
            _percentile(rasterTimesUs, 0.90) / 1000.0,
        '99th_percentile_frame_rasterizer_time_millis':
            _percentile(rasterTimesUs, 0.99) / 1000.0,
        'worst_frame_rasterizer_time_millis':
            rasterTimesUs.last / 1000.0,
      };

      binding.reportData ??= {};
      binding.reportData![reportKey] = summary;

      // Also print to stdout for flutter test runs where reportData
      // isn't collected by a driver.
      // ignore: avoid_print
      print('[$reportKey] ${jsonEncode(summary)}');
    } else {
      // ignore: avoid_print
      print('[$reportKey] No FrameTiming data captured.');
    }
  }
}

double _mean(List<int> sorted) =>
    sorted.fold<int>(0, (a, b) => a + b) / sorted.length;

int _percentile(List<int> sorted, double p) =>
    sorted[((sorted.length - 1) * p).floor()];
