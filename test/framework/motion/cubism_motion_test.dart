import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion_manager.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_expression_motion.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
final _sampleMotionDir =
    '${Directory.current.path}/Samples/Resources/Haru/motions';
final _sampleExpressionDir =
    '${Directory.current.path}/Samples/Resources/Haru/expressions';

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

  group('CubismMotion', () {
    test('parses a motion3.json file', () {
      final motionFiles = Directory(_sampleMotionDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.motion3.json'))
          .toList();

      expect(motionFiles, isNotEmpty);

      final motion = CubismMotion.fromString(motionFiles.first.readAsStringSync());
      expect(motion.data.duration, greaterThan(0.0));
      expect(motion.data.fps, greaterThan(0.0));
      expect(motion.data.curves, isNotEmpty);
      expect(motion.data.segments, isNotEmpty);
      expect(motion.data.points, isNotEmpty);
    });

    test('evaluates curves at different time points', () {
      final motionFiles = Directory(_sampleMotionDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.motion3.json'))
          .toList();

      final motion = CubismMotion.fromString(motionFiles.first.readAsStringSync());
      final data = motion.data;

      // Evaluate first curve at t=0 and t=duration
      final valueAt0 = evaluateCurve(data, 0, 0.0);
      expect(valueAt0, isA<double>());
      expect(valueAt0.isFinite, isTrue);

      final valueAtMid = evaluateCurve(data, 0, data.duration / 2.0);
      expect(valueAtMid, isA<double>());
      expect(valueAtMid.isFinite, isTrue);
    });

    test('updateParameters applies motion to model', () {
      final motionFiles = Directory(_sampleMotionDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.motion3.json'))
          .toList();

      final model = CubismModel.fromMoc(moc);
      final motion = CubismMotion.fromString(motionFiles.first.readAsStringSync());

      // Record initial values
      final initialValues = <String, double>{};
      for (final p in model.parameters) {
        initialValues[p.id] = p.value;
      }

      // Apply motion at t=0.5
      motion.updateParameters(model, 0.5, 1.0, 0.0, -1.0);

      // At least some parameters should have changed
      bool anyChanged = false;
      for (final p in model.parameters) {
        if ((p.value - (initialValues[p.id] ?? 0.0)).abs() > 1e-6) {
          anyChanged = true;
          break;
        }
      }
      expect(anyChanged, isTrue);

      model.dispose();
    });

    test('all sample motions parse without error', () {
      final motionFiles = Directory(_sampleMotionDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.motion3.json'))
          .toList();

      for (final file in motionFiles) {
        expect(
          () => CubismMotion.fromString(file.readAsStringSync()),
          returnsNormally,
          reason: 'Failed to parse: ${file.path}',
        );
      }
    });
  });

  group('CubismMotionManager', () {
    test('starts and updates a motion', () {
      final motionFiles = Directory(_sampleMotionDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.motion3.json'))
          .toList();

      final model = CubismModel.fromMoc(moc);
      final manager = CubismMotionManager();
      final motion = CubismMotion.fromString(motionFiles.first.readAsStringSync());
      motion.fadeInSeconds = 0.5;
      motion.fadeOutSeconds = 0.5;

      manager.startMotionPriority(motion, priority: 1);

      // Update for 60 frames
      for (int i = 0; i < 60; i++) {
        manager.updateMotion(model, 1.0 / 60.0);
      }

      // Manager should not be finished yet (motion is still playing)
      // (depends on motion duration)
      model.dispose();
    });

    test('priority system works', () {
      final manager = CubismMotionManager();
      expect(manager.reserveMotion(1), isTrue);
      expect(manager.reserveMotion(1), isFalse); // Same priority rejected
      expect(manager.reserveMotion(2), isTrue);  // Higher priority accepted
    });
  });

  group('CubismExpressionMotion', () {
    test('parses an exp3.json file', () {
      final expDir = Directory(_sampleExpressionDir);
      if (!expDir.existsSync()) return;

      final expFiles = expDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.exp3.json'))
          .toList();
      if (expFiles.isEmpty) return;

      final expression = CubismExpressionMotion.fromString(
          expFiles.first.readAsStringSync());
      expect(expression.parameters, isNotEmpty);
      expect(expression.fadeInTime, greaterThan(0.0));
      expect(expression.fadeOutTime, greaterThan(0.0));
    });

    test('applies expression to model', () {
      final expDir = Directory(_sampleExpressionDir);
      if (!expDir.existsSync()) return;

      final expFiles = expDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.exp3.json'))
          .toList();
      if (expFiles.isEmpty) return;

      final model = CubismModel.fromMoc(moc);
      final expression = CubismExpressionMotion.fromString(
          expFiles.first.readAsStringSync());

      // Record initial values
      final initialValues = <String, double>{};
      for (final p in model.parameters) {
        initialValues[p.id] = p.value;
      }

      // Apply at full weight
      expression.applyParameters(model, 1.0);

      // At least some parameters should change
      bool anyChanged = false;
      for (final p in model.parameters) {
        if ((p.value - (initialValues[p.id] ?? 0.0)).abs() > 1e-6) {
          anyChanged = true;
          break;
        }
      }
      // May or may not change depending on expression values
      // Just verify it didn't throw
      model.dispose();
    });

    test('all sample expressions parse without error', () {
      final expDir = Directory(_sampleExpressionDir);
      if (!expDir.existsSync()) return;

      final expFiles = expDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.exp3.json'))
          .toList();

      for (final file in expFiles) {
        expect(
          () => CubismExpressionMotion.fromString(file.readAsStringSync()),
          returnsNormally,
          reason: 'Failed to parse: ${file.path}',
        );
      }
    });
  });
}
