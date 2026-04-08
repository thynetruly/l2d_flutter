import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/framework/cubism_model_setting_json.dart';
import 'dart:io';
import '../helpers/golden_comparator.dart';

void main() {
  group('CubismModelSettingJson parity (vs C++ golden)', () {
    late Map<String, dynamic> golden;
    late CubismModelSettingJson settings;

    setUpAll(() {
      golden = GoldenComparator.loadGolden('model_setting_haru_golden.json');
      final json = File('${Directory.current.path}/Samples/Resources/Haru/Haru.model3.json')
          .readAsStringSync();
      settings = CubismModelSettingJson.fromString(json);
    });

    test('modelFileName matches C++', () {
      expect(settings.modelFileName, equals(golden['modelFileName']));
    });

    test('textureCount matches C++', () {
      expect(settings.textureCount, equals(golden['textureCount']));
    });

    test('physicsFileName matches C++', () {
      expect(settings.physicsFileName, equals(golden['physicsFileName']));
    });

    test('poseFileName matches C++', () {
      expect(settings.poseFileName, equals(golden['poseFileName']));
    });

    test('expressionCount matches C++', () {
      expect(settings.expressionCount, equals(golden['expressionCount']));
    });

    test('motionGroupCount matches C++', () {
      expect(settings.motionGroupCount, equals(golden['motionGroupCount']));
    });

    test('hitAreasCount matches C++', () {
      expect(settings.hitAreasCount, equals(golden['hitAreasCount']));
    });

    test('eyeBlinkParameterCount matches C++', () {
      expect(settings.eyeBlinkParameterCount,
          equals(golden['eyeBlinkParameterCount']));
    });

    test('lipSyncParameterCount matches C++', () {
      expect(settings.lipSyncParameterCount,
          equals(golden['lipSyncParameterCount']));
    });

    test('textures match C++', () {
      final textures = golden['textures'] as List;
      for (int i = 0; i < textures.length; i++) {
        expect(settings.getTextureFileName(i),
            equals((textures[i] as Map)['file']));
      }
    });

    test('expressions match C++', () {
      final expressions = golden['expressions'] as List;
      for (int i = 0; i < expressions.length; i++) {
        final m = expressions[i] as Map;
        expect(settings.getExpressionName(i), equals(m['name']));
        expect(settings.getExpressionFileName(i), equals(m['file']));
      }
    });

    test('motion groups match C++', () {
      final groups = golden['motionGroups'] as List;
      for (int i = 0; i < groups.length; i++) {
        final g = groups[i] as Map;
        final groupName = g['name'] as String;
        expect(settings.getMotionGroupName(i), equals(groupName));
        expect(settings.getMotionCount(groupName), equals(g['count']));

        final motions = g['motions'] as List;
        for (int j = 0; j < motions.length; j++) {
          final m = motions[j] as Map;
          expect(settings.getMotionFileName(groupName, j), equals(m['file']));
        }
      }
    });
  });
}
