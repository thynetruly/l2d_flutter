import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion_manager.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
final _sampleMotionDir =
    '${Directory.current.path}/Samples/Resources/Haru/motions';

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
}
