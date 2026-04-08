import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/framework/math/cubism_vector2.dart';

final _coreSoPath =
    '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';

void main() {
  setUpAll(() {
    // Load the core library to ensure native bindings are available
    DynamicLibrary.open(_coreSoPath);
  });

  group('CubismVector2', () {
    test('default constructor produces (0, 0)', () {
      final v = CubismVector2();
      expect(v.x, equals(0.0));
      expect(v.y, equals(0.0));
    });

    test('constructor with arguments sets x and y', () {
      final v = CubismVector2(3.0, 4.0);
      expect(v.x, equals(3.0));
      expect(v.y, equals(4.0));
    });

    test('length of (3, 4) is 5', () {
      final v = CubismVector2(3.0, 4.0);
      expect(v.length, equals(5.0));
    });

    test('length of (0, 0) is 0', () {
      final v = CubismVector2();
      expect(v.length, equals(0.0));
    });

    test('length of (1, 0) is 1', () {
      final v = CubismVector2(1.0, 0.0);
      expect(v.length, equals(1.0));
    });

    group('operator +', () {
      test('adds two vectors', () {
        final a = CubismVector2(1.0, 2.0);
        final b = CubismVector2(3.0, 4.0);
        final result = a + b;
        expect(result.x, equals(4.0));
        expect(result.y, equals(6.0));
      });

      test('adding zero vector returns same values', () {
        final a = CubismVector2(5.0, -3.0);
        final zero = CubismVector2();
        final result = a + zero;
        expect(result.x, equals(5.0));
        expect(result.y, equals(-3.0));
      });
    });

    group('operator -', () {
      test('subtracts two vectors', () {
        final a = CubismVector2(5.0, 7.0);
        final b = CubismVector2(2.0, 3.0);
        final result = a - b;
        expect(result.x, equals(3.0));
        expect(result.y, equals(4.0));
      });

      test('subtracting from itself gives zero', () {
        final a = CubismVector2(3.0, 4.0);
        final result = a - a;
        expect(result.x, equals(0.0));
        expect(result.y, equals(0.0));
      });
    });

    group('operator *', () {
      test('multiplies by scalar', () {
        final v = CubismVector2(2.0, 3.0);
        final result = v * 4.0;
        expect(result.x, equals(8.0));
        expect(result.y, equals(12.0));
      });

      test('multiplying by zero gives zero vector', () {
        final v = CubismVector2(5.0, -3.0);
        final result = v * 0.0;
        expect(result.x, equals(0.0));
        expect(result.y, equals(0.0));
      });

      test('multiplying by 1 gives same vector', () {
        final v = CubismVector2(5.0, -3.0);
        final result = v * 1.0;
        expect(result.x, equals(5.0));
        expect(result.y, equals(-3.0));
      });
    });

    group('operator /', () {
      test('divides by scalar', () {
        final v = CubismVector2(8.0, 12.0);
        final result = v / 4.0;
        expect(result.x, equals(2.0));
        expect(result.y, equals(3.0));
      });

      test('dividing by 1 gives same vector', () {
        final v = CubismVector2(5.0, -3.0);
        final result = v / 1.0;
        expect(result.x, equals(5.0));
        expect(result.y, equals(-3.0));
      });
    });

    group('normalize', () {
      test('normalizing (3, 4) produces unit length', () {
        final v = CubismVector2(3.0, 4.0);
        v.normalize();
        expect(v.length, closeTo(1.0, 1e-10));
        expect(v.x, closeTo(3.0 / 5.0, 1e-10));
        expect(v.y, closeTo(4.0 / 5.0, 1e-10));
      });

      test('normalizing (1, 0) stays (1, 0)', () {
        final v = CubismVector2(1.0, 0.0);
        v.normalize();
        expect(v.x, closeTo(1.0, 1e-10));
        expect(v.y, closeTo(0.0, 1e-10));
      });

      test('normalized() returns unit-length copy without mutating original', () {
        final v = CubismVector2(3.0, 4.0);
        final n = v.normalized();
        expect(n.length, closeTo(1.0, 1e-10));
        // Original unchanged
        expect(v.x, equals(3.0));
        expect(v.y, equals(4.0));
      });
    });

    group('dot product', () {
      test('dot product of perpendicular vectors is 0', () {
        final a = CubismVector2(1.0, 0.0);
        final b = CubismVector2(0.0, 1.0);
        expect(a.dot(b), equals(0.0));
      });

      test('dot product of parallel vectors', () {
        final a = CubismVector2(2.0, 3.0);
        final b = CubismVector2(4.0, 5.0);
        // 2*4 + 3*5 = 8 + 15 = 23
        expect(a.dot(b), equals(23.0));
      });

      test('dot product with itself equals length squared', () {
        final v = CubismVector2(3.0, 4.0);
        expect(v.dot(v), closeTo(v.length * v.length, 1e-10));
      });
    });

    group('distanceTo', () {
      test('distance from (0,0) to (3,4) is 5', () {
        final a = CubismVector2(0.0, 0.0);
        final b = CubismVector2(3.0, 4.0);
        expect(a.distanceTo(b), equals(5.0));
      });

      test('distance to itself is 0', () {
        final v = CubismVector2(5.0, 3.0);
        expect(v.distanceTo(v), equals(0.0));
      });

      test('distance is symmetric', () {
        final a = CubismVector2(1.0, 2.0);
        final b = CubismVector2(4.0, 6.0);
        expect(a.distanceTo(b), equals(b.distanceTo(a)));
      });

      test('distance matches manual calculation', () {
        final a = CubismVector2(1.0, 2.0);
        final b = CubismVector2(4.0, 6.0);
        final expected = math.sqrt(9.0 + 16.0); // sqrt((4-1)^2 + (6-2)^2) = 5
        expect(a.distanceTo(b), closeTo(expected, 1e-10));
      });
    });

    group('equality', () {
      test('equal vectors are equal', () {
        final a = CubismVector2(1.0, 2.0);
        final b = CubismVector2(1.0, 2.0);
        expect(a, equals(b));
      });

      test('different vectors are not equal', () {
        final a = CubismVector2(1.0, 2.0);
        final b = CubismVector2(1.0, 3.0);
        expect(a, isNot(equals(b)));
      });

      test('default vectors are equal', () {
        final a = CubismVector2();
        final b = CubismVector2();
        expect(a, equals(b));
      });

      test('hashCode is consistent with equality', () {
        final a = CubismVector2(1.0, 2.0);
        final b = CubismVector2(1.0, 2.0);
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    test('copy creates an independent copy', () {
      final original = CubismVector2(3.0, 4.0);
      final copied = original.copy();
      expect(copied, equals(original));

      // Mutating copy does not affect original
      copied.x = 99.0;
      expect(original.x, equals(3.0));
    });

    test('toString returns readable format', () {
      final v = CubismVector2(1.5, 2.5);
      expect(v.toString(), equals('CubismVector2(1.5, 2.5)'));
    });
  });
}
