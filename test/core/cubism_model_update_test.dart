import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';

/// Path to the prebuilt Cubism Core shared library for Linux.
final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';

/// Path to a sample .moc3 file for testing.
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';

void main() {
  setUpAll(() {
    final library = DynamicLibrary.open(_coreSoPath);
    NativeLibrary.overrideBindings(CubismCoreBindings(library));
  });

  group('CubismModel – update & dynamic flags', () {
    late CubismMoc moc;
    late CubismModel model;

    setUp(() {
      final mocData = File(_sampleMocPath).readAsBytesSync();
      moc = CubismMoc.fromBytes(mocData);
      model = CubismModel.fromMoc(moc);
    });

    tearDown(() {
      model.dispose();
      moc.dispose();
    });

    test('can set parameter values and update', () {
      final angleX = model.getParameter('ParamAngleX');
      expect(angleX, isNotNull);

      final originalValue = angleX!.value;
      angleX.value = 15.0;
      expect(angleX.value, equals(15.0));

      // Update should not throw
      model.update();

      // Reset
      angleX.value = originalValue;
    });

    test('dynamic flags work after update', () {
      model.update();

      // After first update, some drawables should be visible
      final visibleCount =
          model.drawables.where((d) => d.isVisible).length;
      expect(visibleCount, greaterThan(0));

      model.resetDynamicFlags();
    });
  });
}
