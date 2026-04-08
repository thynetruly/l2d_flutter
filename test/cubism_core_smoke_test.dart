import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_core.dart';
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
    // Load the Cubism Core library directly from the extracted SDK.
    final library = DynamicLibrary.open(_coreSoPath);
    NativeLibrary.overrideBindings(CubismCoreBindings(library));
  });

  group('CubismCore', () {
    test('version returns a non-zero packed version number', () {
      final version = CubismCore.version;
      expect(version, isNonZero);

      // Version should decode to reasonable values
      final major = (version >> 24) & 0xFF;
      final minor = (version >> 16) & 0xFF;
      expect(major, greaterThanOrEqualTo(4),
          reason: 'Expected SDK major version >= 4');
      expect(minor, greaterThanOrEqualTo(0));
    });

    test('versionString returns a formatted version string', () {
      final versionStr = CubismCore.versionString;
      expect(versionStr, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });

    test('latestMocVersion returns a valid moc version constant', () {
      final mocVer = CubismCore.latestMocVersion;
      // Should be one of the defined csmMocVersion_* constants (1-6)
      expect(mocVer, greaterThanOrEqualTo(csmMocVersion_30));
      expect(mocVer, lessThanOrEqualTo(csmMocVersion_53));
    });
  });

  group('CubismMoc', () {
    late Uint8List mocData;

    setUpAll(() {
      final file = File(_sampleMocPath);
      if (!file.existsSync()) {
        fail('Sample MOC file not found at $_sampleMocPath');
      }
      mocData = file.readAsBytesSync();
    });

    test('loads a valid .moc3 file', () {
      final moc = CubismMoc.fromBytes(mocData);
      expect(moc.isDisposed, isFalse);
      expect(moc.nativePointer, isNot(equals(nullptr)));
      moc.dispose();
      expect(moc.isDisposed, isTrue);
    });

    test('reports modelSize > 0', () {
      final moc = CubismMoc.fromBytes(mocData);
      expect(moc.modelSize, greaterThan(0));
      moc.dispose();
    });

    test('reports a valid mocVersion', () {
      final moc = CubismMoc.fromBytes(mocData);
      expect(moc.mocVersion, greaterThanOrEqualTo(csmMocVersion_30));
      moc.dispose();
    });

    test('throws on empty data', () {
      expect(
        () => CubismMoc.fromBytes(Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on invalid data', () {
      expect(
        () => CubismMoc.fromBytes(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<StateError>()),
      );
    });

    test('throws after dispose', () {
      final moc = CubismMoc.fromBytes(mocData);
      moc.dispose();
      expect(() => moc.nativePointer, throwsA(isA<StateError>()));
    });
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

    test('has parameters', () {
      final model = CubismModel.fromMoc(moc);
      expect(model.parameterCount, greaterThan(0));
      expect(model.parameters, isNotEmpty);

      // Each parameter should have a non-empty ID
      for (final param in model.parameters) {
        expect(param.id, isNotEmpty);
        expect(param.minimumValue, lessThanOrEqualTo(param.maximumValue));
      }
      model.dispose();
    });

    test('has parts', () {
      final model = CubismModel.fromMoc(moc);
      expect(model.partCount, greaterThan(0));
      expect(model.parts, isNotEmpty);

      for (final part in model.parts) {
        expect(part.id, isNotEmpty);
        expect(part.opacity, greaterThanOrEqualTo(0.0));
        expect(part.opacity, lessThanOrEqualTo(1.0));
      }
      model.dispose();
    });

    test('has drawables', () {
      final model = CubismModel.fromMoc(moc);
      expect(model.drawableCount, greaterThan(0));
      expect(model.drawables, isNotEmpty);

      for (final drawable in model.drawables) {
        expect(drawable.id, isNotEmpty);
        expect(drawable.vertexCount, greaterThanOrEqualTo(0));
        expect(drawable.textureIndex, greaterThanOrEqualTo(0));
      }
      model.dispose();
    });

    test('has valid canvas info', () {
      final model = CubismModel.fromMoc(moc);
      expect(model.canvas.width, greaterThan(0));
      expect(model.canvas.height, greaterThan(0));
      expect(model.canvas.pixelsPerUnit, greaterThan(0));
      model.dispose();
    });

    test('can get parameter by ID', () {
      final model = CubismModel.fromMoc(moc);
      // Haru model should have standard parameters
      final angleX = model.getParameter('ParamAngleX');
      expect(angleX, isNotNull);
      expect(angleX!.id, equals('ParamAngleX'));
      model.dispose();
    });

    test('can set parameter values and update', () {
      final model = CubismModel.fromMoc(moc);
      final angleX = model.getParameter('ParamAngleX');
      expect(angleX, isNotNull);

      final originalValue = angleX!.value;
      angleX.value = 15.0;
      expect(angleX.value, equals(15.0));

      // Update should not throw
      model.update();

      // Reset
      angleX.value = originalValue;
      model.dispose();
    });

    test('parameter values are clamped to min/max', () {
      final model = CubismModel.fromMoc(moc);
      final param = model.parameters.first;

      param.value = param.maximumValue + 100;
      expect(param.value, equals(param.maximumValue));

      param.value = param.minimumValue - 100;
      expect(param.value, equals(param.minimumValue));

      model.dispose();
    });

    test('can read drawable vertex data', () {
      final model = CubismModel.fromMoc(moc);
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

      model.dispose();
    });

    test('dynamic flags work after update', () {
      final model = CubismModel.fromMoc(moc);
      model.update();

      // After first update, some drawables should be visible
      final visibleCount =
          model.drawables.where((d) => d.isVisible).length;
      expect(visibleCount, greaterThan(0));

      model.resetDynamicFlags();
      model.dispose();
    });

    test('can set part opacities', () {
      final model = CubismModel.fromMoc(moc);
      final part = model.parts.first;

      part.opacity = 0.5;
      expect(part.opacity, closeTo(0.5, 0.001));

      // Clamping
      part.opacity = 1.5;
      expect(part.opacity, equals(1.0));
      part.opacity = -0.5;
      expect(part.opacity, equals(0.0));

      model.dispose();
    });

    test('render orders are valid', () {
      final model = CubismModel.fromMoc(moc);
      model.update();

      final orders = model.renderOrders;
      expect(orders.length, equals(model.drawableCount));

      model.dispose();
    });

    test('throws after dispose', () {
      final model = CubismModel.fromMoc(moc);
      model.dispose();
      expect(() => model.parameters, throwsA(isA<StateError>()));
      expect(() => model.update(), throwsA(isA<StateError>()));
    });
  });

  group('Multiple models from same moc', () {
    test('can create multiple independent model instances', () {
      final mocData = File(_sampleMocPath).readAsBytesSync();
      final moc = CubismMoc.fromBytes(mocData);

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
      moc.dispose();
    });
  });
}
