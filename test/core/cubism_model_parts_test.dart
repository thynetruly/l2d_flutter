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

  group('CubismModel – parts', () {
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

    test('has parts', () {
      expect(model.partCount, greaterThan(0));
      expect(model.parts, isNotEmpty);

      for (final part in model.parts) {
        expect(part.id, isNotEmpty);
        expect(part.opacity, greaterThanOrEqualTo(0.0));
        expect(part.opacity, lessThanOrEqualTo(1.0));
      }
    });

    test('can set part opacities', () {
      final part = model.parts.first;

      part.opacity = 0.5;
      expect(part.opacity, closeTo(0.5, 0.001));

      // Clamping
      part.opacity = 1.5;
      expect(part.opacity, equals(1.0));
      part.opacity = -0.5;
      expect(part.opacity, equals(0.0));
    });
  });
}
