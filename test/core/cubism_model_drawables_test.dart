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

  group('CubismModel – drawables', () {
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

    test('has drawables', () {
      expect(model.drawableCount, greaterThan(0));
      expect(model.drawables, isNotEmpty);

      for (final drawable in model.drawables) {
        expect(drawable.id, isNotEmpty);
        expect(drawable.vertexCount, greaterThanOrEqualTo(0));
        expect(drawable.textureIndex, greaterThanOrEqualTo(0));
      }
    });

    test('can read drawable vertex data', () {
      model.update();

      // Find a drawable with vertices
      final drawable =
          model.drawables.firstWhere((d) => d.vertexCount > 0);
      final positions = drawable.getVertexPositions();
      expect(positions.length, equals(drawable.vertexCount * 2));

      final uvs = drawable.getVertexUvs();
      expect(uvs.length, equals(drawable.vertexCount * 2));

      final indices = drawable.getIndices();
      expect(indices.length, equals(drawable.indexCount));
      // Indices should be valid (< vertex count)
      for (final idx in indices) {
        expect(idx, lessThan(drawable.vertexCount));
      }
    });

    test('render orders are valid', () {
      model.update();

      final orders = model.renderOrders;
      expect(orders.length, equals(model.drawableCount));
    });
  });
}
