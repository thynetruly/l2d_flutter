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

  group('CubismModel', () {
    late CubismMoc moc;

    setUp(() {
      final mocData = File(_sampleMocPath).readAsBytesSync();
      moc = CubismMoc.fromBytes(mocData);
    });

    tearDown(() {
      moc.dispose();
    });

    test('creates from moc successfully', () {
      final model = CubismModel.fromMoc(moc);
      expect(model.isDisposed, isFalse);
      expect(model.nativePointer, isNot(equals(nullptr)));
      model.dispose();
    });

    test('throws after dispose', () {
      final model = CubismModel.fromMoc(moc);
      model.dispose();
      expect(() => model.parameters, throwsA(isA<StateError>()));
      expect(() => model.update(), throwsA(isA<StateError>()));
    });

    test('can create multiple independent model instances from same moc', () {
      final model1 = CubismModel.fromMoc(moc);
      final model2 = CubismModel.fromMoc(moc);

      // Models should have the same structure
      expect(model1.parameterCount, equals(model2.parameterCount));
      expect(model1.partCount, equals(model2.partCount));
      expect(model1.drawableCount, equals(model2.drawableCount));

      // But independent parameter values
      final p1 = model1.parameters.first;
      final p2 = model2.parameters.first;
      p1.value = p1.minimumValue;
      p2.value = p2.maximumValue;
      expect(p1.value, isNot(equals(p2.value)));

      model1.dispose();
      model2.dispose();
    });
  });
}
