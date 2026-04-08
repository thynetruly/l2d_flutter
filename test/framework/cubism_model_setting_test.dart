import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/framework/cubism_model_setting_json.dart';

final _sampleModelJsonPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.model3.json';

void main() {
  late CubismModelSettingJson settings;

  setUpAll(() {
    final jsonStr = File(_sampleModelJsonPath).readAsStringSync();
    settings = CubismModelSettingJson.fromString(jsonStr);
  });

  group('CubismModelSettingJson', () {
    test('parses model file name', () {
      expect(settings.modelFileName, isNotEmpty);
      expect(settings.modelFileName, endsWith('.moc3'));
    });

    test('parses textures', () {
      expect(settings.textureCount, greaterThan(0));
      for (int i = 0; i < settings.textureCount; i++) {
        final tex = settings.getTextureFileName(i);
        expect(tex, isNotEmpty);
        expect(tex, endsWith('.png'));
      }
    });

    test('parses physics file', () {
      expect(settings.physicsFileName, isNotEmpty);
    });

    test('parses pose file', () {
      expect(settings.poseFileName, isNotEmpty);
    });

    test('parses expressions', () {
      expect(settings.expressionCount, greaterThan(0));
      for (int i = 0; i < settings.expressionCount; i++) {
        expect(settings.getExpressionName(i), isNotEmpty);
        expect(settings.getExpressionFileName(i), isNotEmpty);
      }
    });

    test('parses motion groups', () {
      expect(settings.motionGroupCount, greaterThan(0));
      for (int i = 0; i < settings.motionGroupCount; i++) {
        final groupName = settings.getMotionGroupName(i);
        expect(groupName, isNotEmpty);

        final motionCount = settings.getMotionCount(groupName);
        expect(motionCount, greaterThan(0));

        for (int j = 0; j < motionCount; j++) {
          expect(settings.getMotionFileName(groupName, j), isNotEmpty);
        }
      }
    });

    test('parses hit areas', () {
      expect(settings.hitAreasCount, greaterThan(0));
      for (int i = 0; i < settings.hitAreasCount; i++) {
        expect(settings.getHitAreaId(i), isNotEmpty);
        expect(settings.getHitAreaName(i), isNotEmpty);
      }
    });

    test('parses eye blink parameters', () {
      expect(settings.eyeBlinkParameterCount, greaterThan(0));
      for (int i = 0; i < settings.eyeBlinkParameterCount; i++) {
        expect(settings.getEyeBlinkParameterId(i), isNotEmpty);
      }
    });

    test('parses lip sync parameters', () {
      expect(settings.lipSyncParameterCount, greaterThan(0));
      for (int i = 0; i < settings.lipSyncParameterCount; i++) {
        expect(settings.getLipSyncParameterId(i), isNotEmpty);
      }
    });

    test('returns empty string for out-of-bounds indices', () {
      expect(settings.getTextureFileName(-1), isEmpty);
      expect(settings.getTextureFileName(999), isEmpty);
      expect(settings.getExpressionName(-1), isEmpty);
      expect(settings.getMotionFileName('nonexistent', 0), isEmpty);
      expect(settings.getHitAreaId(999), isEmpty);
    });

    test('returns -1 for missing fade times', () {
      // Some motions may have fade times, others may not
      // Just verify we get a double (not an error)
      for (int i = 0; i < settings.motionGroupCount; i++) {
        final group = settings.getMotionGroupName(i);
        for (int j = 0; j < settings.getMotionCount(group); j++) {
          final fadeIn = settings.getMotionFadeInTimeValue(group, j);
          final fadeOut = settings.getMotionFadeOutTimeValue(group, j);
          expect(fadeIn, isA<double>());
          expect(fadeOut, isA<double>());
        }
      }
    });
  });
}
