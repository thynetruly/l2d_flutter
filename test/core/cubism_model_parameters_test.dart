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

  group('CubismModel – parameters', () {
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

    test('has parameters', () {
      expect(model.parameterCount, greaterThan(0));
      expect(model.parameters, isNotEmpty);

      // Each parameter should have a non-empty ID
      for (final param in model.parameters) {
        expect(param.id, isNotEmpty);
        expect(param.minimumValue, lessThanOrEqualTo(param.maximumValue));
      }
    });

    test('can get parameter by ID', () {
      // Haru model should have standard parameters
      final angleX = model.getParameter('ParamAngleX');
      expect(angleX, isNotNull);
      expect(angleX!.id, equals('ParamAngleX'));
    });

    test('parameter values are clamped to min/max', () {
      final param = model.parameters.first;

      param.value = param.maximumValue + 100;
      expect(param.value, equals(param.maximumValue));

      param.value = param.minimumValue - 100;
      expect(param.value, equals(param.minimumValue));
    });
  });
}
