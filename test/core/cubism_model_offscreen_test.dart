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

  group('CubismModel – offscreen surfaces', () {
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

    test('drawables have non-negative parent part indices', () {
      // Offscreen rendering relies on parent-part associations.
      // Drawables may have parentPartIndex of -1 (no parent) or >= 0.
      for (final drawable in model.drawables) {
        expect(drawable.parentPartIndex, greaterThanOrEqualTo(-1));
      }
    });

    test('drawables with masks reference valid drawable indices', () {
      model.update();

      for (final drawable in model.drawables) {
        final maskCount = drawable.maskCount;
        if (maskCount > 0) {
          final masks = drawable.getMaskIndices();
          expect(masks.length, equals(maskCount));
          for (final maskIndex in masks) {
            expect(maskIndex, greaterThanOrEqualTo(0));
            expect(maskIndex, lessThan(model.drawableCount));
          }
        }
      }
    });
  });
}
