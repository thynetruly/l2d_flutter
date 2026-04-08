import 'dart:ffi';
import 'dart:io';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';

/// Shared test setup for core FFI tests.
final coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
final sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
final sampleDir = '${Directory.current.path}/Samples/Resources/Haru';

/// Ensures the Cubism Core library is loaded. Safe to call multiple times.
void ensureCoreLoaded() {
  try {
    NativeLibrary.bindings;
  } catch (_) {
    NativeLibrary.overrideBindings(
        CubismCoreBindings(DynamicLibrary.open(coreSoPath)));
  }
}

/// Creates a CubismMoc from the Haru sample model.
CubismMoc loadSampleMoc() {
  return CubismMoc.fromBytes(File(sampleMocPath).readAsBytesSync());
}
