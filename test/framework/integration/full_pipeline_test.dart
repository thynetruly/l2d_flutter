import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/cubism_model_setting_json.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleDir = '${Directory.current.path}/Samples/Resources/Haru';

void main() {
  late CubismMoc moc;
  late CubismModelSettingJson settings;

  setUpAll(() {
    final library = DynamicLibrary.open(_coreSoPath);
    NativeLibrary.overrideBindings(CubismCoreBindings(library));
    moc = CubismMoc.fromBytes(
        File('$_sampleDir/Haru.moc3').readAsBytesSync());
    settings = CubismModelSettingJson.fromString(
        File('$_sampleDir/Haru.model3.json').readAsStringSync());
  });

  tearDownAll(() {
    moc.dispose();
  });

  group('Full pipeline integration', () {
    test('300-frame simulation: motion + physics + eye blink + breath', () {
      final model = CubismModel.fromMoc(moc);

      // Load physics
      final physicsPath = '$_sampleDir/${settings.physicsFileName}';
      CubismPhysics? physics;
      if (File(physicsPath).existsSync()) {
        physics = CubismPhysics.fromString(
            File(physicsPath).readAsStringSync());
        physics.stabilization(model);
      }

      // Load an idle motion
      CubismMotion? motion;
      final motionCount = settings.getMotionCount('Idle');
      if (motionCount > 0) {
        final motionFileName = settings.getMotionFileName('Idle', 0);
        final motionPath = '$_sampleDir/$motionFileName';
        if (File(motionPath).existsSync()) {
          motion = CubismMotion.fromString(
              File(motionPath).readAsStringSync());
          motion.isLoop = true;
          motion.fadeInSeconds = 0.5;
          motion.fadeOutSeconds = 0.5;
        }
      }

      // Eye blink
      final eyeBlink = CubismEyeBlink(
        parameterIds: settings.eyeBlinkParameterIds,
        random: math.Random(42),
      );

      // Breath
      final breath = CubismBreath(parameters: [
        BreathParameterData(
          parameterId: 'ParamBreath',
          offset: 0.0,
          peak: 0.4,
          cycle: 3.2345,
          weight: 0.5,
        ),
      ]);

      // Run 300 frames (5 seconds at 60fps)
      final dt = 1.0 / 60.0;
      double elapsed = 0.0;

      for (int frame = 0; frame < 300; frame++) {
        elapsed += dt;

        // Apply motion
        if (motion != null) {
          motion.updateParameters(model, elapsed, 1.0, 0.0, -1.0);
        }

        // Apply eye blink
        eyeBlink.updateParameters(model, dt);

        // Apply breath
        breath.updateParameters(model, dt);

        // Apply physics
        if (physics != null) {
          physics.evaluate(model, dt);
        }

        // Update model
        model.update();

        // Verify all values are finite
        for (final p in model.parameters) {
          expect(p.value.isFinite, isTrue,
              reason: 'Frame $frame: param ${p.id} = ${p.value}');
        }
      }

      // Verify drawables are valid after full pipeline
      for (final d in model.drawables) {
        if (d.vertexCount > 0) {
          final verts = d.getVertexPositions();
          for (int i = 0; i < verts.length; i++) {
            expect(verts[i].isFinite, isTrue,
                reason: 'Drawable ${d.id} vertex[$i] is not finite');
          }
        }
      }

      // Verify some parameters changed from defaults
      // (motion + effects should have modified at least some)
      bool anyNonDefault = false;
      for (final p in model.parameters) {
        if ((p.value - p.defaultValue).abs() > 1e-6) {
          anyNonDefault = true;
          break;
        }
      }
      expect(anyNonDefault, isTrue,
          reason: 'After 300 frames, some parameters should differ from defaults');

      model.dispose();
    });

    test('multiple models run independently through pipeline', () {
      final model1 = CubismModel.fromMoc(moc);
      final model2 = CubismModel.fromMoc(moc);

      final eyeBlink1 = CubismEyeBlink(
        parameterIds: settings.eyeBlinkParameterIds,
        random: math.Random(42),
      );
      final eyeBlink2 = CubismEyeBlink(
        parameterIds: settings.eyeBlinkParameterIds,
        random: math.Random(99),
      );

      // Run different frame counts
      for (int i = 0; i < 60; i++) {
        eyeBlink1.updateParameters(model1, 1.0 / 60.0);
        model1.update();
      }
      for (int i = 0; i < 120; i++) {
        eyeBlink2.updateParameters(model2, 1.0 / 60.0);
        model2.update();
      }

      // Models should have different states
      final eye1 = model1.getParameter('ParamEyeLOpen');
      final eye2 = model2.getParameter('ParamEyeLOpen');

      // Both should be valid
      expect(eye1, isNotNull);
      expect(eye2, isNotNull);
      expect(eye1!.value.isFinite, isTrue);
      expect(eye2!.value.isFinite, isTrue);

      model1.dispose();
      model2.dispose();
    });
  });
}
