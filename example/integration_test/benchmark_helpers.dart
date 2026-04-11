// Shared helpers for the Live2D Flutter benchmark integration tests.
//
// Provides:
//   - ensureCoreLoaded() — loads the Cubism Core native library.
//   - loadTexture(path) — decodes a PNG file into a dart:ui Image.
//   - createHaruController() — returns a fully configured Live2DController
//     with moc + settings + physics + textures + idle motion.
//   - projectRoot — resolves the project root regardless of CWD.

import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/widgets/live2d_controller.dart';

/// Resolves the project root. When running `flutter test` or
/// `flutter drive` from the `example/` directory, `Directory.current` is
/// `example/`. When running from the project root, it's the root itself.
String get projectRoot {
  final cwd = Directory.current.path;
  if (cwd.endsWith('example') || cwd.endsWith('example/')) {
    return Directory(cwd).parent.path;
  }
  return cwd;
}

String get _haruDir => '$projectRoot/Samples/Resources/Haru';

bool _coreLoaded = false;

/// Loads the Cubism Core native library. Safe to call multiple times.
void ensureCoreLoaded() {
  if (_coreLoaded) return;
  try {
    NativeLibrary.bindings;
    _coreLoaded = true;
  } catch (_) {
    // Try platform-specific paths.
    final paths = [
      '$projectRoot/Core/dll/linux/x86_64/libLive2DCubismCore.so',
      '$projectRoot/Core/dll/macos/libLive2DCubismCore.dylib',
    ];
    for (final path in paths) {
      if (File(path).existsSync()) {
        NativeLibrary.overrideBindings(
          CubismCoreBindings(DynamicLibrary.open(path)),
        );
        _coreLoaded = true;
        return;
      }
    }
    rethrow;
  }
}

/// Decodes a PNG file at [path] into a dart:ui [Image].
///
/// This uses `ui.instantiateImageCodec` which works in both test and
/// full-app contexts. The returned Image is suitable for
/// `controller.setTexture()`.
Future<ui.Image> loadTexture(String path) async {
  final bytes = File(path).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Creates a fully configured [Live2DController] with Haru model data:
/// moc3, model3.json, physics, textures, and an idle motion playing.
///
/// Caller must dispose the returned controller when done.
Future<Live2DController> createHaruController() async {
  ensureCoreLoaded();

  final controller = Live2DController();
  controller.loadFromBytes(
    mocBytes: File('$_haruDir/Haru.moc3').readAsBytesSync(),
    settingsJson: File('$_haruDir/Haru.model3.json').readAsStringSync(),
  );

  // Physics.
  final physicsPath = '$_haruDir/Haru.physics3.json';
  if (File(physicsPath).existsSync()) {
    controller.loadPhysics(File(physicsPath).readAsStringSync());
  }

  // Textures.
  final textureDir = '$_haruDir/Haru.2048';
  for (int i = 0; i < 2; i++) {
    final texPath = '$textureDir/texture_0$i.png';
    if (File(texPath).existsSync()) {
      final img = await loadTexture(texPath);
      controller.setTexture(i, img);
    }
  }

  // Start idle motion.
  final motionPath = '$_haruDir/motions/haru_g_idle.motion3.json';
  if (File(motionPath).existsSync()) {
    controller.startMotion(File(motionPath).readAsStringSync());
  }

  return controller;
}
