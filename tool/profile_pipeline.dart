// DevTools CPU-profile entrypoint for the full Cubism pipeline.
//
// Run this when a benchmark flags a slowdown but can't explain it. The
// program loads Haru, wraps each pipeline phase in
// `dart:developer.Timeline.startSync/finishSync`, and runs 600 frames
// in a tight loop. Launched under the VM service, it prints a URL that
// DevTools can connect to, captures a CPU profile, and exits.
//
// Usage:
//
//   dart run --enable-vm-service --profile-period=100 \
//       --pause-isolates-on-exit=false tool/profile_pipeline.dart
//
// Then open the printed VM Service URL in DevTools, switch to the CPU
// profiler tab, and record while the script runs.

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

Future<void> main() async {
  // Load native core once.
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

  // Load physics.
  CubismPhysics? physics;
  final physicsPath = '$sampleDir/${settings.physicsFileName}';
  if (File(physicsPath).existsSync()) {
    physics = CubismPhysics.fromString(File(physicsPath).readAsStringSync());
    physics.stabilization(model);
  }

  // Load pose.
  CubismPose? pose;
  final posePath = '$sampleDir/${settings.poseFileName}';
  if (settings.poseFileName.isNotEmpty && File(posePath).existsSync()) {
    pose = CubismPose.fromString(File(posePath).readAsStringSync());
  }

  // Load idle motion.
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

  // Print the VM service URL so DevTools can connect.
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri != null) {
    stdout.writeln('');
    stdout.writeln('VM Service: $uri');
    stdout.writeln('Open DevTools → CPU Profiler tab → Record, then wait '
        'for "done".');
    stdout.writeln('');
  } else {
    stderr.writeln('VM service not available — relaunch with:');
    stderr.writeln('  dart run --enable-vm-service '
        '--pause-isolates-on-exit=false tool/profile_pipeline.dart');
  }

  // 10-second grace window so you can start the recording before the loop
  // runs.
  stdout.writeln('Starting profile loop in 10 seconds...');
  await Future.delayed(const Duration(seconds: 10));

  // 600 frames (10 s at 60 fps). Each phase is wrapped in a Timeline
  // segment so DevTools' Timeline tab can visualise phase splits.
  const dt = 1.0 / 60.0;
  double elapsed = 0.0;

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

  stdout.writeln('done (600 frames).');
  stdout.writeln('Extract profile from DevTools before this process exits.');
  // Give DevTools a moment to pull the final samples.
  await Future.delayed(const Duration(seconds: 5));

  model.dispose();
  moc.dispose();
}
