// DevTools CPU profiler + timeline exporter for the full Cubism pipeline.
//
// Runs the full Haru pipeline (motion + eye blink + breath + physics +
// pose + model.update) for 600 frames with Timeline instrumentation, then
// programmatically captures:
//
//   1. CPU profile via VmService.getCpuSamples() → tool/cpu_profile.json
//      Top-10 functions by inclusive ticks printed to stdout.
//
//   2. Timeline events via VmService.getVMTimeline() → tool/timeline.json
//      Chrome trace format — openable in chrome://tracing or DevTools
//      Performance tab. Per-phase duration summary printed to stdout.
//
// Usage:
//
//   # Automated (default): captures CPU profile + timeline, writes JSON, exits.
//   dart run --enable-vm-service --pause-isolates-on-exit=false \
//       tool/profile_pipeline.dart
//
//   # Interactive: prints VM Service URL for manual DevTools connection,
//   # waits before/after the loop so you can record in the UI.
//   dart run --enable-vm-service --pause-isolates-on-exit=false \
//       tool/profile_pipeline.dart --interactive

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/framework/cubism_model_setting_json.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';
import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> argv) async {
  final interactive = argv.contains('--interactive');

  // -----------------------------------------------------------------------
  // Load model
  // -----------------------------------------------------------------------
  final cwd = Directory.current.path;
  final coreSoPath = '$cwd/Core/dll/linux/x86_64/libLive2DCubismCore.so';
  try {
    NativeLibrary.bindings;
  } catch (_) {
    NativeLibrary.overrideBindings(
      CubismCoreBindings(DynamicLibrary.open(coreSoPath)),
    );
  }

  final sampleDir = '$cwd/Samples/Resources/Haru';
  final moc =
      CubismMoc.fromBytes(File('$sampleDir/Haru.moc3').readAsBytesSync());
  final settings = CubismModelSettingJson.fromString(
      File('$sampleDir/Haru.model3.json').readAsStringSync());
  final model = CubismModel.fromMoc(moc);

  CubismPhysics? physics;
  final physicsPath = '$sampleDir/${settings.physicsFileName}';
  if (File(physicsPath).existsSync()) {
    physics = CubismPhysics.fromString(File(physicsPath).readAsStringSync());
    physics.stabilization(model);
  }

  CubismPose? pose;
  final posePath = '$sampleDir/${settings.poseFileName}';
  if (settings.poseFileName.isNotEmpty && File(posePath).existsSync()) {
    pose = CubismPose.fromString(File(posePath).readAsStringSync());
  }

  CubismMotion? motion;
  if (settings.getMotionCount('Idle') > 0) {
    final motionFile = settings.getMotionFileName('Idle', 0);
    final motionPath = '$sampleDir/$motionFile';
    if (File(motionPath).existsSync()) {
      motion = CubismMotion.fromString(File(motionPath).readAsStringSync());
      motion.isLoop = true;
      motion.fadeInSeconds = 0.5;
      motion.fadeOutSeconds = 0.5;
    }
  }

  final eye = CubismEyeBlink(
    parameterIds: settings.eyeBlinkParameterIds,
    random: math.Random(42),
  );
  final breath = CubismBreath(parameters: const [
    BreathParameterData(
      parameterId: 'ParamBreath',
      offset: 0.0,
      peak: 0.4,
      cycle: 3.2345,
      weight: 0.5,
    ),
  ]);

  // -----------------------------------------------------------------------
  // Connect to VM service
  // -----------------------------------------------------------------------
  VmService? vmService;
  String? isolateId;
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri != null) {
    stdout.writeln('VM Service: $uri');
    try {
      final wsUri = uri.replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: uri.path.endsWith('/') ? '${uri.path}ws' : '${uri.path}/ws',
      );
      vmService = await vmServiceConnectUri(wsUri.toString());
      final vm = await vmService.getVM();
      isolateId = vm.isolates?.first.id;
    } catch (e) {
      stderr.writeln('Warning: could not connect to VM service: $e');
    }
  } else {
    stderr.writeln('VM service not available — relaunch with:');
    stderr.writeln('  dart run --enable-vm-service '
        '--pause-isolates-on-exit=false tool/profile_pipeline.dart');
  }

  // Enable Dart timeline recording for automated capture.
  if (vmService != null && !interactive) {
    try {
      await vmService.setVMTimelineFlags(['Dart']);
    } catch (e) {
      stderr.writeln('Warning: could not enable timeline recording: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Interactive mode: wait for user to start DevTools recording
  // -----------------------------------------------------------------------
  if (interactive) {
    stdout.writeln('');
    stdout.writeln('[interactive] Open the VM Service URL above in DevTools.');
    stdout.writeln('[interactive] Start recording in CPU Profiler or Timeline,');
    stdout.writeln('[interactive] then press Enter to begin the frame loop.');
    stdin.readLineSync();
  }

  // -----------------------------------------------------------------------
  // Frame loop (600 frames, 10 s at 60 fps)
  // -----------------------------------------------------------------------
  const dt = 1.0 / 60.0;
  double elapsed = 0.0;
  final loopSw = Stopwatch()..start();

  for (int f = 0; f < 600; f++) {
    elapsed += dt;

    developer.Timeline.startSync('motion');
    motion?.updateParameters(model, elapsed, 1.0, 0.0, -1.0,
        userTimeSeconds: elapsed);
    developer.Timeline.finishSync();

    developer.Timeline.startSync('eye_blink');
    eye.updateParameters(model, dt);
    developer.Timeline.finishSync();

    developer.Timeline.startSync('breath');
    breath.updateParameters(model, dt);
    developer.Timeline.finishSync();

    developer.Timeline.startSync('physics');
    physics?.evaluate(model, dt);
    developer.Timeline.finishSync();

    developer.Timeline.startSync('pose');
    pose?.updateParameters(model, dt);
    developer.Timeline.finishSync();

    developer.Timeline.startSync('model_update');
    model.update();
    developer.Timeline.finishSync();
  }

  loopSw.stop();
  final loopMs = loopSw.elapsedMilliseconds;
  stdout.writeln('');
  stdout.writeln('Frame loop done: 600 frames in ${loopMs}ms '
      '(${(loopMs / 600.0).toStringAsFixed(2)}ms/frame avg)');

  // -----------------------------------------------------------------------
  // Interactive mode: wait for user to stop recording
  // -----------------------------------------------------------------------
  if (interactive) {
    stdout.writeln('');
    stdout.writeln('[interactive] Stop your DevTools recording, then press '
        'Enter to exit.');
    stdin.readLineSync();
    model.dispose();
    moc.dispose();
    await vmService?.dispose();
    return;
  }

  // -----------------------------------------------------------------------
  // Automated: capture CPU profile
  // -----------------------------------------------------------------------
  if (vmService != null && isolateId != null) {
    stdout.writeln('');

    // CPU samples
    try {
      final cpuSamples = await vmService.getCpuSamples(isolateId, 0, ~0 >>> 1);
      final cpuJson = jsonEncode(cpuSamples.json);
      final cpuFile = File('tool/cpu_profile.json');
      cpuFile.writeAsStringSync(cpuJson);
      stdout.writeln('Wrote CPU profile to ${cpuFile.path} '
          '(${cpuSamples.samples?.length ?? 0} samples)');

      // Print top 10 functions by inclusive ticks.
      final functions = cpuSamples.functions;
      if (functions != null && functions.isNotEmpty) {
        final sorted = [...functions]
          ..sort((a, b) =>
              (b.inclusiveTicks ?? 0).compareTo(a.inclusiveTicks ?? 0));
        stdout.writeln('');
        stdout.writeln('Top 10 functions by inclusive CPU ticks:');
        stdout.writeln('${'Ticks'.padLeft(8)}  ${'Excl'.padLeft(6)}  Function');
        stdout.writeln('${'─' * 8}  ${'─' * 6}  ${'─' * 50}');
        for (int i = 0; i < math.min(10, sorted.length); i++) {
          final f = sorted[i];
          // f.function is dynamic — may be a FuncRef with a .name, or a
          // raw map. Handle both.
          final fn = f.function;
          final name = fn is Map ? (fn['name'] ?? '?') : (fn?.name ?? '?');
          stdout.writeln(
            '${(f.inclusiveTicks ?? 0).toString().padLeft(8)}  '
            '${(f.exclusiveTicks ?? 0).toString().padLeft(6)}  '
            '$name',
          );
        }
      }
    } catch (e) {
      stderr.writeln('Warning: CPU profile capture failed: $e');
    }

    // Timeline
    try {
      final timeline = await vmService.getVMTimeline();
      final traceEvents = timeline.traceEvents;
      if (traceEvents != null && traceEvents.isNotEmpty) {
        final traceJson = jsonEncode(
            traceEvents.map((e) => e.json).toList());
        final tlFile = File('tool/timeline.json');
        tlFile.writeAsStringSync(traceJson);
        stdout.writeln('');
        stdout.writeln('Wrote timeline to ${tlFile.path} '
            '(${traceEvents.length} events)');

        // Summarise per-phase durations from the timeline events.
        _printTimelineSummary(traceEvents);
      } else {
        stdout.writeln('Timeline: no events captured.');
      }
    } catch (e) {
      stderr.writeln('Warning: timeline capture failed: $e');
    }

    await vmService.dispose();
  }

  model.dispose();
  moc.dispose();
}

/// Parses Complete ('X') events from the timeline and prints per-phase
/// totals. Timeline events from Timeline.startSync/finishSync show up as
/// Duration events (ph: 'B'/'E') or Complete events (ph: 'X') depending
/// on the Dart VM version.
void _printTimelineSummary(List<TimelineEvent> events) {
  final phaseTotals = <String, int>{}; // phase name → total µs
  for (final event in events) {
    final json = event.json;
    if (json == null) continue;
    final ph = json['ph'] as String?;
    final name = json['name'] as String?;
    if (name == null) continue;

    if (ph == 'X') {
      // Complete event: has 'dur' in µs.
      final dur = json['dur'] as int? ?? 0;
      phaseTotals[name] = (phaseTotals[name] ?? 0) + dur;
    }
  }

  // Also handle B/E pairs if the VM uses duration events.
  final openStarts = <String, int>{}; // name → start timestamp µs
  for (final event in events) {
    final json = event.json;
    if (json == null) continue;
    final ph = json['ph'] as String?;
    final name = json['name'] as String?;
    final ts = json['ts'] as int?;
    if (name == null || ts == null) continue;

    if (ph == 'B') {
      openStarts[name] = ts;
    } else if (ph == 'E') {
      final start = openStarts.remove(name);
      if (start != null) {
        phaseTotals[name] = (phaseTotals[name] ?? 0) + (ts - start);
      }
    }
  }

  if (phaseTotals.isEmpty) {
    stdout.writeln('Timeline: no phase events found.');
    return;
  }

  stdout.writeln('');
  stdout.writeln('Per-phase timeline totals (600 frames):');
  stdout.writeln('${'Phase'.padRight(20)}  ${'Total'.padLeft(10)}  Per-frame');
  stdout.writeln('${'─' * 20}  ${'─' * 10}  ${'─' * 12}');
  final sorted = phaseTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted) {
    final totalUs = entry.value;
    final perFrameUs = totalUs / 600.0;
    stdout.writeln(
      '${entry.key.padRight(20)}  '
      '${_fmtUs(totalUs).padLeft(10)}  '
      '${_fmtUs(perFrameUs.round()).padLeft(12)}',
    );
  }
}

String _fmtUs(int us) {
  if (us < 1000) return '$us µs';
  if (us < 1000000) return '${(us / 1000).toStringAsFixed(2)} ms';
  return '${(us / 1000000).toStringAsFixed(2)} s';
}
