import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';

/// Path to the prebuilt Cubism Core shared library for Linux.
final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';

/// Path to a sample .moc3 file for testing.
final _sampleMocPath =
    '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';

void main() {
  late Uint8List mocData;

  setUpAll(() {
    final library = DynamicLibrary.open(_coreSoPath);
    NativeLibrary.overrideBindings(CubismCoreBindings(library));

    final file = File(_sampleMocPath);
    if (!file.existsSync()) {
      fail('Sample MOC file not found at $_sampleMocPath');
    }
    mocData = file.readAsBytesSync();
  });

  group('CubismMoc', () {
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
}
