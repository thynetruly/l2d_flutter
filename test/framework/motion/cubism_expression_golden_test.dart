import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_expression_motion.dart';
import '../../helpers/golden_comparator.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
final _expressionPath =
    '${Directory.current.path}/Samples/Resources/Haru/expressions/F01.exp3.json';

void main() {
  late CubismMoc moc;
  late Map<String, dynamic> golden;
  late CubismExpressionMotion expression;

  setUpAll(() {
    final library = DynamicLibrary.open(_coreSoPath);
    NativeLibrary.overrideBindings(CubismCoreBindings(library));
    moc = CubismMoc.fromBytes(File(_sampleMocPath).readAsBytesSync());
    golden = GoldenComparator.loadGolden('expression_haru_F01_golden.json');
    expression = CubismExpressionMotion.fromString(
        File(_expressionPath).readAsStringSync());
  });

  tearDownAll(() {
    moc.dispose();
  });

  group('CubismExpressionMotion parity (vs C++ golden)', () {
    test('fadeInTime matches C++', () {
      expect(expression.fadeInTime, equals((golden['fadeInTime'] as num).toDouble()));
    });

    test('fadeOutTime matches C++', () {
      expect(expression.fadeOutTime, equals((golden['fadeOutTime'] as num).toDouble()));
    });

    test('expression parameters match C++', () {
      final goldenParams =
          (golden['expressionParameters'] as List).cast<Map<String, dynamic>>();
      expect(expression.parameters.length, equals(goldenParams.length));
      for (int i = 0; i < goldenParams.length; i++) {
        expect(expression.parameters[i].parameterId,
            equals(goldenParams[i]['id']));
        expect(expression.parameters[i].value,
            closeTo((goldenParams[i]['value'] as num).toDouble(), 1e-6));
      }
    });

    test('parameter values at multiple weights match C++', () {
      final samples =
          (golden['weightSamples'] as List).cast<Map<String, dynamic>>();

      for (final sample in samples) {
        final weight = (sample['weight'] as num).toDouble();
        final goldenParams = (sample['params'] as List).cast<Map<String, dynamic>>();

        // Reset model parameters to defaults
        final model = CubismModel.fromMoc(moc);
        for (final p in model.parameters) {
          p.value = p.defaultValue;
        }

        // Apply expression at the given weight
        expression.applyParameters(model, weight);

        // Compare each parameter
        for (final gp in goldenParams) {
          final dartParam = model.getParameter(gp['id'] as String);
          if (dartParam == null) continue;
          final expected = (gp['value'] as num).toDouble();
          expect(dartParam.value, closeTo(expected, 1e-5),
              reason: 'weight=$weight param=${gp['id']}');
        }

        model.dispose();
      }
    });
  });
}
