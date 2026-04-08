import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/framework/math/cubism_matrix44.dart';

void main() {
  group('CubismMatrix44', () {
    test('initializes to identity', () {
      final m = CubismMatrix44();
      expect(m.array[0], equals(1.0));
      expect(m.array[5], equals(1.0));
      expect(m.array[10], equals(1.0));
      expect(m.array[15], equals(1.0));
      expect(m.array[1], equals(0.0));
      expect(m.array[12], equals(0.0));
    });

    test('translate sets correct elements', () {
      final m = CubismMatrix44();
      m.translate(3.0, 4.0);
      expect(m.translateX, equals(3.0));
      expect(m.translateY, equals(4.0));
    });

    test('scale sets correct elements', () {
      final m = CubismMatrix44();
      m.scale(2.0, 3.0);
      expect(m.scaleX, equals(2.0));
      expect(m.scaleY, equals(3.0));
    });

    test('transformX applies scale and translate', () {
      final m = CubismMatrix44();
      m.scale(2.0, 1.0);
      m.translate(10.0, 0.0);
      expect(m.transformX(5.0), equals(2.0 * 5.0 + 10.0));
    });

    test('transformY applies scale and translate', () {
      final m = CubismMatrix44();
      m.scale(1.0, 3.0);
      m.translate(0.0, 5.0);
      expect(m.transformY(2.0), equals(3.0 * 2.0 + 5.0));
    });

    test('invertTransformX reverses transformX', () {
      final m = CubismMatrix44();
      m.scale(2.0, 1.0);
      m.translate(10.0, 0.0);
      final transformed = m.transformX(5.0);
      expect(m.invertTransformX(transformed), closeTo(5.0, 1e-6));
    });

    test('multiply identity by identity gives identity', () {
      final a = Float32List(16);
      final b = Float32List(16);
      final dst = Float32List(16);
      _setIdentity(a);
      _setIdentity(b);
      CubismMatrix44.multiply(a, b, dst);
      expect(dst[0], equals(1.0));
      expect(dst[5], equals(1.0));
      expect(dst[10], equals(1.0));
      expect(dst[15], equals(1.0));
      expect(dst[1], equals(0.0));
    });

    test('multiply with translation', () {
      final a = Float32List(16);
      _setIdentity(a);
      a[12] = 5.0; // translate X by 5
      a[13] = 3.0; // translate Y by 3

      final b = Float32List(16);
      _setIdentity(b);
      b[12] = 2.0; // translate X by 2
      b[13] = 1.0; // translate Y by 1

      final dst = Float32List(16);
      CubismMatrix44.multiply(a, b, dst);
      // Translations should add
      expect(dst[12], closeTo(7.0, 1e-6));
      expect(dst[13], closeTo(4.0, 1e-6));
    });

    test('getInvert produces correct inverse', () {
      final m = CubismMatrix44();
      m.scale(2.0, 3.0);
      m.translate(5.0, 7.0);

      final inv = m.getInvert();

      // M * M^-1 should be identity
      final result = Float32List(16);
      CubismMatrix44.multiply(m.array, inv.array, result);
      expect(result[0], closeTo(1.0, 1e-4));
      expect(result[5], closeTo(1.0, 1e-4));
      expect(result[10], closeTo(1.0, 1e-4));
      expect(result[15], closeTo(1.0, 1e-4));
      expect(result[12], closeTo(0.0, 1e-4));
      expect(result[13], closeTo(0.0, 1e-4));
    });

    test('scaleRelative multiplies current scale', () {
      final m = CubismMatrix44();
      m.scale(2.0, 3.0);
      m.scaleRelative(1.5, 2.0);
      expect(m.scaleX, closeTo(3.0, 1e-6));
      expect(m.scaleY, closeTo(6.0, 1e-6));
    });

    test('translateRelative shifts current position', () {
      final m = CubismMatrix44();
      m.translate(10.0, 20.0);
      m.translateRelative(5.0, 3.0);
      expect(m.translateX, closeTo(15.0, 1e-6));
      expect(m.translateY, closeTo(23.0, 1e-6));
    });
  });
}

void _setIdentity(Float32List m) {
  for (int i = 0; i < 16; i++) {
    m[i] = 0.0;
  }
  m[0] = 1.0;
  m[5] = 1.0;
  m[10] = 1.0;
  m[15] = 1.0;
}
