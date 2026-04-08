import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_expression_motion.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
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
      // Expression with non-zero values applied at weight 1.0 should change
      // at least one parameter
      expect(anyChanged, isTrue,
          reason: 'Applying expression at weight 1.0 should change parameters');
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
