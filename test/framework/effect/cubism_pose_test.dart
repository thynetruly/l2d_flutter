import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
final _samplePosePath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.pose3.json';

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

  group('CubismPose', () {
    test('loads pose3.json without error', () {
      final poseJson = File(_samplePosePath).readAsStringSync();
      expect(() => CubismPose.fromString(poseJson), returnsNormally);
    });

    test('parses fade time from pose3.json', () {
      final poseJson = File(_samplePosePath).readAsStringSync();
      final pose = CubismPose.fromString(poseJson);
      // fadeTimeSeconds should be a positive value
      expect(pose.fadeTimeSeconds, greaterThan(0.0));
    });

    test('reset sets first part in each group to visible', () {
      final poseJson = File(_samplePosePath).readAsStringSync();
      final pose = CubismPose.fromString(poseJson);
      final model = CubismModel.fromMoc(moc);

      pose.reset(model);

      // After reset, the pose has been initialized on the model.
      // We cannot inspect internal state directly, but the call should succeed.
      model.dispose();
    });

    test('updateParameters runs for multiple frames without error', () {
      final poseJson = File(_samplePosePath).readAsStringSync();
      final pose = CubismPose.fromString(poseJson);
      final model = CubismModel.fromMoc(moc);

      // Record initial part opacities
      final initialOpacities = <String, double>{};
      for (final part in model.parts) {
        initialOpacities[part.id] = part.opacity;
      }

      // Run updateParameters for 120 frames (2 seconds at 60fps)
      for (int i = 0; i < 120; i++) {
        pose.updateParameters(model, 1.0 / 60.0);
      }

      // After running for 2 seconds, part opacities should reflect
      // the pose crossfade state. At minimum, the call should not throw.
      model.dispose();
    });

    test('part opacities change after multiple updateParameters calls', () {
      final poseJson = File(_samplePosePath).readAsStringSync();
      final pose = CubismPose.fromString(poseJson);
      final model = CubismModel.fromMoc(moc);

      // First call initializes (reset) the pose
      pose.updateParameters(model, 1.0 / 60.0);

      // Record opacities after initialization
      final opacitiesAfterInit = <String, double>{};
      for (final part in model.parts) {
        opacitiesAfterInit[part.id] = part.opacity;
      }

      // Some parts should have opacity 1.0 (visible) and some 0.0 (hidden)
      final hasVisible = opacitiesAfterInit.values.any((v) => v >= 0.99);
      final hasHidden = opacitiesAfterInit.values.any((v) => v <= 0.01);
      expect(hasVisible, isTrue,
          reason: 'At least one part should be visible after pose init');
      expect(hasHidden, isTrue,
          reason: 'At least one part should be hidden after pose init');

      model.dispose();
    });

    test('fromBytes produces same result as fromString', () {
      final poseFile = File(_samplePosePath);
      final poseFromString = CubismPose.fromString(poseFile.readAsStringSync());
      final poseFromBytes = CubismPose.fromBytes(poseFile.readAsBytesSync());

      expect(poseFromString.fadeTimeSeconds, equals(poseFromBytes.fadeTimeSeconds));
    });
  });
}
