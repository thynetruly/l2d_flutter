import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/framework/math/cubism_math.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_vector2.dart';

void main() {
  group('CubismMath', () {
    group('rangeF / clampF', () {
      test('clamps below min', () {
        expect(CubismMath.rangeF(-5.0, 0.0, 1.0), equals(0.0));
      });
      test('clamps above max', () {
        expect(CubismMath.rangeF(5.0, 0.0, 1.0), equals(1.0));
      });
      test('returns value within range', () {
        expect(CubismMath.rangeF(0.5, 0.0, 1.0), equals(0.5));
      });
    });

    group('getEasingSine', () {
      test('returns 0 at input 0', () {
        expect(CubismMath.getEasingSine(0.0), closeTo(0.0, 1e-6));
      });
      test('returns 1 at input 1', () {
        expect(CubismMath.getEasingSine(1.0), closeTo(1.0, 1e-6));
      });
      test('returns 0.5 at input 0.5', () {
        expect(CubismMath.getEasingSine(0.5), closeTo(0.5, 1e-6));
      });
      test('clamps negative input to 0', () {
        expect(CubismMath.getEasingSine(-1.0), equals(0.0));
      });
      test('clamps input > 1 to 1', () {
        expect(CubismMath.getEasingSine(2.0), equals(1.0));
      });
      test('is monotonically increasing', () {
        double prev = 0.0;
        for (double t = 0.01; t <= 1.0; t += 0.01) {
          final v = CubismMath.getEasingSine(t);
          expect(v, greaterThanOrEqualTo(prev));
          prev = v;
        }
      });
      test('matches formula: 0.5 - 0.5*cos(value*pi)', () {
        // Note: getEasingSine intentionally truncates to float32 precision
        // to match C++ Framework. Tolerance is float32 epsilon (~1e-7).
        for (double t = 0.0; t <= 1.0; t += 0.1) {
          final expected = 0.5 - 0.5 * math.cos(t * CubismMath.pi);
          expect(CubismMath.getEasingSine(t), closeTo(expected, 1e-7));
        }
      });
    });

    group('angle conversions', () {
      test('degreesToRadian 180 = pi', () {
        expect(CubismMath.degreesToRadian(180.0), closeTo(CubismMath.pi, 1e-10));
      });
      test('radianToDegrees pi = 180', () {
        expect(CubismMath.radianToDegrees(CubismMath.pi), closeTo(180.0, 1e-10));
      });
      test('round-trip conversion', () {
        for (double deg = -360; deg <= 360; deg += 45) {
          final rad = CubismMath.degreesToRadian(deg);
          expect(CubismMath.radianToDegrees(rad), closeTo(deg, 1e-10));
        }
      });
    });

    group('directionToRadian', () {
      test('same direction returns 0', () {
        final v = CubismVector2(1, 0);
        expect(CubismMath.directionToRadian(v, v), closeTo(0.0, 1e-10));
      });
      test('90 degree rotation', () {
        final from = CubismVector2(1, 0);
        final to = CubismVector2(0, 1);
        expect(CubismMath.directionToRadian(from, to),
            closeTo(CubismMath.pi / 2, 1e-6));
      });
    });

    group('radianToDirection', () {
      test('0 radian gives (0, 1)', () {
        final v = CubismMath.radianToDirection(0.0);
        expect(v.x, closeTo(0.0, 1e-6));
        expect(v.y, closeTo(1.0, 1e-6));
      });
    });

    group('quadraticEquation', () {
      test('linear case (a=0)', () {
        // 2x + 4 = 0 → x = -2
        expect(CubismMath.quadraticEquation(0.0, 2.0, 4.0), closeTo(-2.0, 1e-6));
      });
      test('quadratic case', () {
        // x^2 - 5x + 6 = 0 → roots at 2, 3
        final root = CubismMath.quadraticEquation(1.0, -5.0, 6.0);
        // Should return -(b + sqrt(b²-4ac)) / 2a = -((-5) + sqrt(25-24))/2 = -((-5)+1)/2 = 2
        expect(root, closeTo(2.0, 1e-6));
      });
    });

    group('cardanoAlgorithmForBezier', () {
      test('returns value in [0, 1] range', () {
        final result =
            CubismMath.cardanoAlgorithmForBezier(1.0, -3.0, 3.0, -0.5);
        expect(result, greaterThanOrEqualTo(0.0));
        expect(result, lessThanOrEqualTo(1.0));
      });
      test('identity bezier (linear)', () {
        // For a linear bezier f(t) = t, the cubic is: t^3 coefficients resolve to t
        // Testing with known control points that produce near-identity
        final result =
            CubismMath.cardanoAlgorithmForBezier(0.0, 0.0, 1.0, -0.5);
        expect(result, closeTo(0.5, 1e-4));
      });
    });

    group('modF', () {
      test('positive dividend and divisor', () {
        expect(CubismMath.modF(5.5, 2.0), closeTo(1.5, 1e-6));
      });
      test('negative dividend', () {
        expect(CubismMath.modF(-5.5, 2.0), closeTo(-1.5, 1e-6));
      });
      test('divisor is 0 returns NaN', () {
        expect(CubismMath.modF(5.0, 0.0), isNaN);
      });
    });

    group('trig functions', () {
      // sinF/cosF now use LibM.sinf/cosf via FFI for bit-exact parity with C++.
      // These are single-precision; comparing against double-precision math.sin
      // requires float32-epsilon tolerance.
      test('sinF approximates dart:math sin', () {
        for (double x = -2 * CubismMath.pi; x <= 2 * CubismMath.pi; x += 0.5) {
          expect(CubismMath.sinF(x), closeTo(math.sin(x), 1e-6));
        }
      });
      test('cosF approximates dart:math cos', () {
        for (double x = -2 * CubismMath.pi; x <= 2 * CubismMath.pi; x += 0.5) {
          expect(CubismMath.cosF(x), closeTo(math.cos(x), 1e-6));
        }
      });
    });
  });
}
