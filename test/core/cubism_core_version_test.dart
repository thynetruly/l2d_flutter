import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_core.dart';

/// Path to the prebuilt Cubism Core shared library for Linux.
final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';

void main() {
  setUpAll(() {
    final library = DynamicLibrary.open(_coreSoPath);
    NativeLibrary.overrideBindings(CubismCoreBindings(library));
  });

  group('CubismCore', () {
    test('version returns a non-zero packed version number', () {
      final version = CubismCore.version;
      expect(version, isNonZero);

      // Version should decode to reasonable values
      final major = (version >> 24) & 0xFF;
      final minor = (version >> 16) & 0xFF;
      expect(major, greaterThanOrEqualTo(4),
          reason: 'Expected SDK major version >= 4');
      expect(minor, greaterThanOrEqualTo(0));
    });

    test('versionString returns a formatted version string', () {
      final versionStr = CubismCore.versionString;
      expect(versionStr, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });

    test('latestMocVersion returns a valid moc version constant', () {
      final mocVer = CubismCore.latestMocVersion;
      // Should be one of the defined csmMocVersion_* constants (1-6)
      expect(mocVer, greaterThanOrEqualTo(csmMocVersion_30));
      expect(mocVer, lessThanOrEqualTo(csmMocVersion_53));
    });
  });
}
