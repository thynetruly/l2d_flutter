import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_look.dart';

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

  group('CubismLook', () {
    test('applies drag to parameters', () {
      final model = CubismModel.fromMoc(moc);
      final look = CubismLook(parameters: [
        LookParameterData(
          parameterId: 'ParamAngleX',
          factorX: 30.0,
          factorY: 0.0,
          factorXY: 0.0,
        ),
        LookParameterData(
          parameterId: 'ParamAngleY',
          factorX: 0.0,
          factorY: 30.0,
          factorXY: 0.0,
        ),
      ]);

      final paramX = model.getParameter('ParamAngleX');
      final paramY = model.getParameter('ParamAngleY');
      if (paramX == null || paramY == null) {
        model.dispose();
        return;
      }

      paramX.value = 0.0;
      paramY.value = 0.0;

      look.updateParameters(model, 0.5, 0.3);

      expect(paramX.value, closeTo(30.0 * 0.5, 1e-6));
      expect(paramY.value, closeTo(30.0 * 0.3, 1e-6));

      model.dispose();
    });

    test('factorXY produces cross-term', () {
      final model = CubismModel.fromMoc(moc);
      final look = CubismLook(parameters: [
        LookParameterData(
          parameterId: 'ParamAngleX',
          factorX: 0.0,
          factorY: 0.0,
          factorXY: 10.0,
        ),
      ]);

      final param = model.getParameter('ParamAngleX');
      if (param == null) {
        model.dispose();
        return;
      }

      param.value = 0.0;
      look.updateParameters(model, 0.5, 0.4);

      // Expected: 10.0 * 0.5 * 0.4 = 2.0
      expect(param.value, closeTo(2.0, 1e-6));

      model.dispose();
    });
  });
}
