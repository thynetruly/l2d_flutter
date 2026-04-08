import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
final _samplePhysicsPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.physics3.json';

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

  group('CubismPhysics', () {
    test('parses a physics3.json file', () {
      final physicsJson = File(_samplePhysicsPath).readAsStringSync();
      final physics = CubismPhysics.fromString(physicsJson);
      expect(physics, isNotNull);
      expect(physics.options.gravity.y, lessThan(0.0)); // Gravity points down
    });

    test('reset does not throw', () {
      final physicsJson = File(_samplePhysicsPath).readAsStringSync();
      final physics = CubismPhysics.fromString(physicsJson);
      expect(() => physics.reset(), returnsNormally);
    });

    test('stabilization runs without error', () {
      final model = CubismModel.fromMoc(moc);
      final physicsJson = File(_samplePhysicsPath).readAsStringSync();
      final physics = CubismPhysics.fromString(physicsJson);

      expect(() => physics.stabilization(model), returnsNormally);
      model.dispose();
    });

    test('evaluate runs for multiple frames without error', () {
      final model = CubismModel.fromMoc(moc);
      final physicsJson = File(_samplePhysicsPath).readAsStringSync();
      final physics = CubismPhysics.fromString(physicsJson);

      // Initialize
      physics.stabilization(model);

      // Run physics for 60 frames (1 second at 60fps)
      // Physics modifies parameters via interpolation; verify no exceptions
      for (int i = 0; i < 60; i++) {
        expect(() => physics.evaluate(model, 1.0 / 60.0), returnsNormally);
        model.update();
      }

      // All values should remain finite
      for (final p in model.parameters) {
        expect(p.value.isFinite, isTrue,
            reason: 'Parameter ${p.id} has non-finite value after physics');
      }

      model.dispose();
    });

    test('evaluate handles zero delta time', () {
      final model = CubismModel.fromMoc(moc);
      final physicsJson = File(_samplePhysicsPath).readAsStringSync();
      final physics = CubismPhysics.fromString(physicsJson);

      physics.stabilization(model);
      expect(() => physics.evaluate(model, 0.0), returnsNormally);

      model.dispose();
    });

    test('evaluate handles large delta time (overflow protection)', () {
      final model = CubismModel.fromMoc(moc);
      final physicsJson = File(_samplePhysicsPath).readAsStringSync();
      final physics = CubismPhysics.fromString(physicsJson);

      physics.stabilization(model);
      // Delta > MaxDeltaTime (5.0s) should be handled gracefully
      expect(() => physics.evaluate(model, 10.0), returnsNormally);

      model.dispose();
    });

    test('300-frame simulation produces finite values', () {
      final model = CubismModel.fromMoc(moc);
      final physicsJson = File(_samplePhysicsPath).readAsStringSync();
      final physics = CubismPhysics.fromString(physicsJson);

      physics.stabilization(model);

      // Run 300 frames (5 seconds at 60fps)
      for (int i = 0; i < 300; i++) {
        physics.evaluate(model, 1.0 / 60.0);
        model.update();
      }

      // All parameter values should be finite
      for (final p in model.parameters) {
        expect(p.value.isFinite, isTrue,
            reason: 'Parameter ${p.id} has non-finite value: ${p.value}');
      }

      model.dispose();
    });

    test('all sample physics files parse without error', () {
      final physicsFiles = [
        'Samples/Resources/Haru/Haru.physics3.json',
        'Samples/Resources/Hiyori/Hiyori.physics3.json',
        'Samples/Resources/Natori/Natori.physics3.json',
        'Samples/Resources/Mark/Mark.physics3.json',
      ];

      for (final path in physicsFiles) {
        final fullPath = '${Directory.current.path}/$path';
        if (!File(fullPath).existsSync()) continue;

        expect(
          () => CubismPhysics.fromString(File(fullPath).readAsStringSync()),
          returnsNormally,
          reason: 'Failed to parse: $path',
        );
      }
    });
  });
}
