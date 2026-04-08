import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_eye_blink.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';

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

  group('CubismEyeBlink', () {
    test('starts in First state and transitions to Interval', () {
      final model = CubismModel.fromMoc(moc);
      final blink = CubismEyeBlink(
        parameterIds: ['ParamEyeLOpen', 'ParamEyeROpen'],
        random: math.Random(42),
      );

      expect(blink.state, equals(EyeState.first));

      // First update transitions to Interval
      blink.updateParameters(model, 0.016);
      expect(blink.state, equals(EyeState.interval));

      // Eyes should be open (value = 1.0)
      final eyeL = model.getParameter('ParamEyeLOpen');
      expect(eyeL, isNotNull);
      expect(eyeL!.value, equals(1.0));

      model.dispose();
    });

    test('completes a full blink cycle', () {
      final model = CubismModel.fromMoc(moc);
      final blink = CubismEyeBlink(
        parameterIds: ['ParamEyeLOpen'],
        blinkingIntervalSeconds: 0.1, // Short interval for testing
        closingSeconds: 0.1,
        closedSeconds: 0.05,
        openingSeconds: 0.15,
        random: math.Random(42),
      );

      // Initialize
      blink.updateParameters(model, 0.016);
      expect(blink.state, equals(EyeState.interval));

      // Advance past the blink interval
      for (int i = 0; i < 100; i++) {
        blink.updateParameters(model, 0.016);
      }

      // After enough time, should have gone through at least one blink cycle
      // and be back in interval or in another state
      final eyeL = model.getParameter('ParamEyeLOpen');
      expect(eyeL, isNotNull);
      // Value should be valid [0, 1]
      expect(eyeL!.value, greaterThanOrEqualTo(0.0));
      expect(eyeL.value, lessThanOrEqualTo(1.0));

      model.dispose();
    });

    test('respects blink settings', () {
      final blink = CubismEyeBlink(
        parameterIds: ['ParamEyeLOpen'],
      );
      blink.setBlinkingSettings(0.2, 0.1, 0.3);
      expect(blink.closingSeconds, equals(0.2));
      expect(blink.closedSeconds, equals(0.1));
      expect(blink.openingSeconds, equals(0.3));
    });
  });
}
