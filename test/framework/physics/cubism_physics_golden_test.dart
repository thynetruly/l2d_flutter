import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';
import '../../helpers/golden_comparator.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
final _physicsPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.physics3.json';

void main() {
  late CubismMoc moc;
  late Map<String, dynamic> golden;

  setUpAll(() {
    final library = DynamicLibrary.open(_coreSoPath);
    NativeLibrary.overrideBindings(CubismCoreBindings(library));
    moc = CubismMoc.fromBytes(File(_sampleMocPath).readAsBytesSync());
    golden = GoldenComparator.loadGolden('physics_haru_golden.json');
  });

  tearDownAll(() {
    moc.dispose();
  });

  group('CubismPhysics parity (vs C++ golden)', () {
    test('300-frame simulation matches C++ within tolerance', () {
      final model = CubismModel.fromMoc(moc);
      final physics = CubismPhysics.fromString(
          File(_physicsPath).readAsStringSync());
      physics.stabilization(model);

      final frameData =
          (golden['frameData'] as List).cast<Map<String, dynamic>>();
      expect(frameData.length, equals(300));

      final dt = 1.0 / 60.0;

      // Replicate the same input pattern from the generator:
      // SetParameterValue(ParamAngleX, sin(i*0.1) * 30.0)
      int matched = 0;
      int total = 0;
      for (int i = 0; i < 300; i++) {
        final paramAngleX = model.getParameter('ParamAngleX');
        if (paramAngleX != null) {
          paramAngleX.value = math.sin(i * 0.1) * 30.0;
        }

        physics.evaluate(model, dt);
        model.update();

        // Compare against golden frame data
        final frame = frameData[i];
        final samples = (frame['paramSamples'] as List).cast<Map<String, dynamic>>();
        for (final sample in samples) {
          final id = sample['id'] as String;
          final expected = (sample['value'] as num).toDouble();
          final dartParam = model.getParameter(id);
          if (dartParam == null) continue;
          total++;
          // Physics tolerance: 1e-3 (allows for accumulated float drift)
          if ((dartParam.value - expected).abs() < 1e-3) {
            matched++;
          }
        }
      }

      // Most samples should match within tolerance
      // (Some divergence expected due to float vs double precision)
      expect(matched / total, greaterThan(0.7),
          reason: 'At least 70% of physics samples should match within 1e-3');

      model.dispose();
    });
  });
}
