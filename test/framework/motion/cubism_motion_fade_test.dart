import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_math.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
final _sampleMotionDir =
    '${Directory.current.path}/Samples/Resources/Haru/motions';

void main() {
  late CubismMoc moc;

  setUpAll(() {
    final library = DynamicLibrary.open(_coreSoPath);
    NativeLibrary.overrideBindings(CubismCoreBindings(library));
    moc = CubismMoc.fromBytes(File(_sampleMocPath).readAsBytesSync());
  });

  tearDownAll(() {
    moc.dispose();
  });

  group('CubismMotion fade-in weight', () {
    late CubismMotion motion;

    setUp(() {
      final motionFiles = Directory(_sampleMotionDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.motion3.json'))
          .toList();
      motion = CubismMotion.fromString(motionFiles.first.readAsStringSync());
      motion.fadeInSeconds = 0.5;
      motion.fadeOutSeconds = -1.0; // No fade-out for fade-in tests
    });

    test('at t=0 fade-in weight should be ~0', () {
      final model = CubismModel.fromMoc(moc);

      // Record initial values
      final initialValues = <String, double>{};
      for (final p in model.parameters) {
        initialValues[p.id] = p.value;
      }

      // Apply motion at t=0 with fadeInStartTime=0, no endTime
      // fadeIn weight = getEasingSine((0.0 - 0.0) / 0.5) = getEasingSine(0) = 0
      motion.updateParameters(model, 0.0, 1.0, 0.0, -1.0);

      // With fade-in weight of 0, parameters should remain near their initial values
      // because: param.value = sourceValue + (curveValue - sourceValue) * 0 = sourceValue
      for (final p in model.parameters) {
        final initial = initialValues[p.id] ?? 0.0;
        expect(p.value, closeTo(initial, 1e-4),
            reason: 'Parameter ${p.id} should stay near initial at t=0 fade-in');
      }

      model.dispose();
    });

    test('at t=0.25 fade-in weight should be ~0.5 (eased)', () {
      // fadeIn = getEasingSine(0.25 / 0.5) = getEasingSine(0.5) ~ 0.5
      final expectedWeight = CubismMath.getEasingSine(0.5);
      expect(expectedWeight, closeTo(0.5, 0.05),
          reason: 'getEasingSine(0.5) should be approximately 0.5');

      final model = CubismModel.fromMoc(moc);

      // Record initial parameter values
      final initialValues = <String, double>{};
      for (final p in model.parameters) {
        initialValues[p.id] = p.value;
      }

      // Apply at t=0.25, fadeInStartTime=0
      motion.updateParameters(model, 0.25, 1.0, 0.0, -1.0);

      // With partial fade weight, at least some parameters should have
      // moved partway from initial toward their curve values
      bool anyPartiallyBlended = false;
      for (final p in model.parameters) {
        final initial = initialValues[p.id] ?? 0.0;
        final diff = (p.value - initial).abs();
        if (diff > 1e-6) {
          anyPartiallyBlended = true;
          break;
        }
      }
      expect(anyPartiallyBlended, isTrue,
          reason: 'Some parameters should be partially blended at 50% fade-in');

      model.dispose();
    });

    test('at t=0.5 fade-in weight should be ~1.0', () {
      // fadeIn = getEasingSine(0.5 / 0.5) = getEasingSine(1.0) = 1.0
      final expectedWeight = CubismMath.getEasingSine(1.0);
      expect(expectedWeight, closeTo(1.0, 1e-6));

      final model = CubismModel.fromMoc(moc);
      final modelForReference = CubismModel.fromMoc(moc);

      // Apply with full fade at t=0.5
      motion.updateParameters(model, 0.5, 1.0, 0.0, -1.0);

      // Apply the same motion without any fade (fadeInSeconds = -1 disables fade)
      final motionNoFade = CubismMotion.fromString(
        File(Directory(_sampleMotionDir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.motion3.json'))
            .first
            .path)
            .readAsStringSync(),
      );
      motionNoFade.fadeInSeconds = -1.0;
      motionNoFade.fadeOutSeconds = -1.0;
      motionNoFade.updateParameters(modelForReference, 0.5, 1.0, 0.0, -1.0);

      // With fade-in complete (weight ~1.0), result should match the no-fade case
      for (final p in model.parameters) {
        final refParam = modelForReference.getParameter(p.id);
        if (refParam != null) {
          expect(p.value, closeTo(refParam.value, 1e-4),
              reason: 'Parameter ${p.id} should match no-fade result when fade-in is complete');
        }
      }

      model.dispose();
      modelForReference.dispose();
    });
  });

  group('CubismMotion fade-out weight', () {
    test('weight decreases as endTime approaches', () {
      final motionFiles = Directory(_sampleMotionDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.motion3.json'))
          .toList();

      final motion = CubismMotion.fromString(motionFiles.first.readAsStringSync());
      motion.fadeInSeconds = -1.0; // No fade-in
      motion.fadeOutSeconds = 0.5;

      final endTime = 2.0;

      // At t=1.0, still far from end: fadeOut = getEasingSine((2.0-1.0)/0.5) = getEasingSine(2.0) = 1.0
      final modelEarly = CubismModel.fromMoc(moc);
      final initialEarly = <String, double>{};
      for (final p in modelEarly.parameters) {
        initialEarly[p.id] = p.value;
      }
      motion.updateParameters(modelEarly, 1.0, 1.0, 0.0, endTime);

      // At t=1.75, close to end: fadeOut = getEasingSine((2.0-1.75)/0.5) = getEasingSine(0.5) ~ 0.5
      final modelLate = CubismModel.fromMoc(moc);
      final initialLate = <String, double>{};
      for (final p in modelLate.parameters) {
        initialLate[p.id] = p.value;
      }
      motion.updateParameters(modelLate, 1.75, 1.0, 0.0, endTime);

      // At t=2.0 (at endTime): fadeOut = getEasingSine((2.0-2.0)/0.5) = getEasingSine(0) = 0
      final modelEnd = CubismModel.fromMoc(moc);
      final initialEnd = <String, double>{};
      for (final p in modelEnd.parameters) {
        initialEnd[p.id] = p.value;
      }
      motion.updateParameters(modelEnd, 2.0, 1.0, 0.0, endTime);

      // At endTime, fade-out weight is 0, so parameters should be near initial
      for (final p in modelEnd.parameters) {
        final initial = initialEnd[p.id] ?? 0.0;
        expect(p.value, closeTo(initial, 1e-4),
            reason: 'Parameter ${p.id} should return to initial at endTime');
      }

      // Compare against no-fade reference: with fadeOut applied, the displacement
      // should equal (curveValue - initial) * fadeWeight. So the ratio of actual
      // displacement to no-fade displacement should equal fadeWeight.
      // At t=1.75, fadeOutWeight = getEasingSine(0.5) = 0.5
      // So displacement should be ~50% of no-fade.
      final modelLateNoFade = CubismModel.fromMoc(moc);
      final motionNoFade = CubismMotion.fromString(motionFiles.first.readAsStringSync());
      motionNoFade.fadeInSeconds = -1.0;
      motionNoFade.fadeOutSeconds = -1.0; // No fade-out
      motionNoFade.updateParameters(modelLateNoFade, 1.75, 1.0, 0.0, endTime);

      // For at least one parameter, verify the fade ratio
      bool foundChangedParam = false;
      for (final p in modelLate.parameters) {
        final initial = initialLate[p.id] ?? 0.0;
        final disp = (p.value - initial).abs();
        final noFadeP = modelLateNoFade.getParameter(p.id);
        if (noFadeP == null) continue;
        final noFadeDisp = (noFadeP.value - initial).abs();

        if (noFadeDisp > 1e-4) {
          // At t=1.75: fadeOut = getEasingSine(0.5) = 0.5 - 0.5*cos(pi/2) = 0.5
          final ratio = disp / noFadeDisp;
          expect(ratio, closeTo(0.5, 0.05),
              reason: 'Param ${p.id} fade ratio at t=1.75 should be ~0.5');
          foundChangedParam = true;
          break;
        }
      }
      expect(foundChangedParam, isTrue,
          reason: 'Should find at least one parameter affected by motion');

      modelLateNoFade.dispose();

      modelEarly.dispose();
      modelLate.dispose();
      modelEnd.dispose();
    });

    test('fade-out weight formula matches getEasingSine', () {
      // Verify the expected fade-out formula values
      // fadeOut = getEasingSine((endTime - timeSeconds) / fadeOutSeconds)
      final fadeOutSeconds = 0.5;
      final endTime = 2.0;

      // At various time points:
      final fadeAtT1_5 = CubismMath.getEasingSine((endTime - 1.5) / fadeOutSeconds);
      expect(fadeAtT1_5, closeTo(1.0, 1e-6),
          reason: 'At t=1.5 (1.0s before end), fade weight should be 1.0');

      final fadeAtT1_75 = CubismMath.getEasingSine((endTime - 1.75) / fadeOutSeconds);
      expect(fadeAtT1_75, closeTo(0.5, 0.05),
          reason: 'At t=1.75 (0.25s before end), fade weight should be ~0.5');

      final fadeAtT2_0 = CubismMath.getEasingSine((endTime - 2.0) / fadeOutSeconds);
      expect(fadeAtT2_0, closeTo(0.0, 1e-6),
          reason: 'At endTime, fade weight should be 0');
    });
  });
}
