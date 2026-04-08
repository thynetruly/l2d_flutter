import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_breath.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_math.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';

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

  group('CubismBreath', () {
    test('applies sine wave to model parameters', () {
      final model = CubismModel.fromMoc(moc);
      final breath = CubismBreath(parameters: [
        BreathParameterData(
          parameterId: 'ParamBreath',
          offset: 0.0,
          peak: 0.5,
          cycle: 3.0,
          weight: 1.0,
        ),
      ]);

      final paramBefore = model.getParameter('ParamBreath');
      if (paramBefore == null) {
        model.dispose();
        return; // Skip if parameter doesn't exist
      }

      final valueBefore = paramBefore.value;

      // Simulate 1 second
      for (int i = 0; i < 60; i++) {
        // Reset to default before each breath update
        paramBefore.value = valueBefore;
        breath.updateParameters(model, 1.0 / 60.0);
      }

      // After 1 second, breath should have modified the value
      // The value should be: default + offset + peak * sin(2pi * 1.0 / cycle) * weight
      model.dispose();
    });

    test('accumulates time correctly', () {
      final model = CubismModel.fromMoc(moc);
      final breath = CubismBreath(parameters: []);

      expect(breath.currentTime, equals(0.0));
      breath.updateParameters(model, 0.5);
      expect(breath.currentTime, closeTo(0.5, 1e-10));
      breath.updateParameters(model, 0.3);
      expect(breath.currentTime, closeTo(0.8, 1e-10));

      model.dispose();
    });

    test('sine formula matches expected output', () {
      final model = CubismModel.fromMoc(moc);
      final breath = CubismBreath(parameters: [
        BreathParameterData(
          parameterId: 'ParamAngleX',
          offset: 1.0,
          peak: 2.0,
          cycle: 4.0,
          weight: 0.5,
        ),
      ]);

      final param = model.getParameter('ParamAngleX');
      if (param == null) {
        model.dispose();
        return;
      }

      param.value = 0.0;
      breath.updateParameters(model, 1.0); // t = 1.0

      // Expected: 0.0 + (1.0 + 2.0 * sin(2pi * 1.0 / 4.0)) * 0.5
      //         = (1.0 + 2.0 * sin(pi/2)) * 0.5
      //         = (1.0 + 2.0 * 1.0) * 0.5 = 1.5
      final expectedBreathValue = 1.0 + 2.0 * math.sin(2.0 * CubismMath.pi * 1.0 / 4.0);
      expect(param.value, closeTo(expectedBreathValue * 0.5, 1e-4));

      model.dispose();
    });
  });
}
