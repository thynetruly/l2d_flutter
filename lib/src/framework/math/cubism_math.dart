import 'cubism_vector2.dart';
import 'float32.dart';
import 'libm.dart';

/// Static math utility functions for the Cubism Framework.
///
/// Ported from Framework/src/Math/CubismMath.hpp.
class CubismMath {
  CubismMath._();

  static const double pi = 3.1415926535897932384626433832795;
  static const double epsilon = 0.00001;

  /// Pi truncated to float32 precision (matches C++ `Pi` constant exactly).
  static final double piF32 = Float32.cast(pi);

  /// Clamps [value] within [min]..[max] range (float).
  static double rangeF(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Clamps [val] within [min]..[max] range (int).
  static int clamp(int val, int min, int max) {
    if (val < min) return min;
    if (max < val) return max;
    return val;
  }

  /// Clamps [val] within [min]..[max] range (float).
  static double clampF(double val, double min, double max) {
    if (val < min) return min;
    if (max < val) return max;
    return val;
  }

  /// Sine function (single-precision via libm `sinf`).
  static double sinF(double x) => LibM.sinf(x);

  /// Cosine function (single-precision via libm `cosf`).
  static double cosF(double x) => LibM.cosf(x);

  /// Absolute value.
  static double absF(double x) => x.abs();

  /// Square root (single-precision via libm `sqrtf`).
  static double sqrtF(double x) => LibM.sqrtf(x);

  /// Returns the larger of [l] and [r].
  static double max(double l, double r) => (l > r) ? l : r;

  /// Returns the smaller of [l] and [r].
  static double min(double l, double r) => (l > r) ? r : l;

  /// Sine-wave easing for fade-in/fade-out.
  ///
  /// Maps [value] in [0..1] to a smooth ease curve using cosine.
  /// Formula: `0.5 - 0.5 * cosf(value * Pi)` (matches C++ exactly).
  ///
  /// Uses [LibM.cosf] for bit-exact parity with the C++ Cubism Framework.
  static double getEasingSine(double value) {
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    final x = Float32.cast(value * piF32);
    final c = LibM.cosf(x);
    return Float32.cast(0.5 - Float32.cast(0.5 * c));
  }

  /// Converts degrees to radians.
  static double degreesToRadian(double degrees) => (degrees / 180.0) * pi;

  /// Converts radians to degrees.
  static double radianToDegrees(double radian) => (radian * 180.0) / pi;

  /// Calculates the angle between two vectors in radians.
  ///
  /// Result is normalized to [-pi, pi] range.
  ///
  /// Uses [LibM.atan2f] for bit-exact parity with the C++ Cubism Framework.
  static double directionToRadian(CubismVector2 from, CubismVector2 to) {
    final q1 = LibM.atan2f(to.y, to.x);
    final q2 = LibM.atan2f(from.y, from.x);
    var ret = Float32.cast(q1 - q2);

    final twoPi = Float32.cast(piF32 * 2.0);
    while (ret < -piF32) {
      ret = Float32.cast(ret + twoPi);
    }
    while (ret > piF32) {
      ret = Float32.cast(ret - twoPi);
    }

    return ret;
  }

  /// Calculates the angle between two vectors in degrees.
  static double directionToDegrees(CubismVector2 from, CubismVector2 to) {
    final radian = directionToRadian(from, to);
    var degree = radianToDegrees(radian);

    if ((to.x - from.x) > 0.0) {
      degree = -degree;
    }

    return degree;
  }

  /// Converts a radian angle to a direction vector.
  static CubismVector2 radianToDirection(double totalAngle) {
    return CubismVector2(sinF(totalAngle), cosF(totalAngle));
  }

  /// Solves the quadratic equation: `a*x^2 + b*x + c = 0`.
  static double quadraticEquation(double a, double b, double c) {
    if (absF(a) < epsilon) {
      if (absF(b) < epsilon) {
        return -c;
      }
      return -c / b;
    }
    return Float32.cast(
        -(b + LibM.sqrtf(Float32.cast(b * b - 4.0 * a * c))) / (2.0 * a));
  }

  /// Solves a cubic equation using Cardano's algorithm for Bezier curves.
  ///
  /// Solves: `a*x^3 + b*x^2 + c*x + d = 0`
  /// Returns a solution in [0.0, 1.0] for valid Bezier t-values.
  ///
  /// Uses [LibM.sqrtf]/[LibM.cosf] for the float-precision parts and
  /// [LibM.acos]/[LibM.cbrt] (DOUBLE precision) for the parts where C++
  /// intentionally uses double-precision (`acos`/`cbrt`) for stability.
  /// Achieves bit-exact parity with the C++ Cubism Framework.
  static double cardanoAlgorithmForBezier(
      double a, double b, double c, double d) {
    if (absF(a) < epsilon) {
      return rangeF(quadraticEquation(b, c, d), 0.0, 1.0);
    }

    double f(double v) => Float32.cast(v);

    final ba = f(b / a);
    final ca = f(c / a);
    final da = f(d / a);

    final p = f(f(f(3.0 * ca) - f(ba * ba)) / 3.0);
    final p3 = f(p / 3.0);
    final q = f(f(f(f(2.0 * f(f(ba * ba) * ba)) - f(f(9.0 * ba) * ca)) +
            f(27.0 * da)) /
        27.0);
    final q2 = f(q / 2.0);
    final discriminant = f(f(q2 * q2) + f(f(p3 * p3) * p3));

    const center = 0.5;
    const threshold = center + 0.01;

    if (discriminant < 0.0) {
      // Three distinct real roots
      final mp3 = f(-p / 3.0);
      final mp33 = f(f(mp3 * mp3) * mp3);
      final r = f(LibM.sqrtf(mp33));
      final t = f(-q / f(2.0 * r));
      final cosphi = rangeF(t, -1.0, 1.0);
      // C++ uses double-precision `acos()` here intentionally for stability,
      // then truncates the result to csmFloat32 on assignment.
      final phi = f(LibM.acos(cosphi));
      // C++ uses double-precision `cbrt()` here intentionally, then truncates.
      final crtr = f(LibM.cbrt(r));
      final t1 = f(2.0 * crtr);

      final root1 = f(f(t1 * LibM.cosf(f(phi / 3.0))) - f(ba / 3.0));
      final root2 = f(f(t1 * LibM.cosf(f(f(phi + f(2.0 * piF32)) / 3.0))) -
          f(ba / 3.0));
      final root3 = f(f(t1 * LibM.cosf(f(f(phi + f(4.0 * piF32)) / 3.0))) -
          f(ba / 3.0));

      if ((root1 - center).abs() < threshold) {
        return rangeF(root1, 0.0, 1.0);
      }
      if ((root2 - center).abs() < threshold) {
        return rangeF(root2, 0.0, 1.0);
      }
      return rangeF(root3, 0.0, 1.0);
    } else if (discriminant == 0.0) {
      // Repeated roots — C++ uses double-precision `cbrt()`.
      double u1;
      if (q2 < 0.0) {
        u1 = f(LibM.cbrt(-q2));
      } else {
        u1 = f(-LibM.cbrt(q2));
      }

      final root1 = f(f(2.0 * u1) - f(ba / 3.0));
      final root2 = f(-u1 - f(ba / 3.0));

      if ((root1 - center).abs() < threshold) {
        return rangeF(root1, 0.0, 1.0);
      }
      return rangeF(root2, 0.0, 1.0);
    } else {
      // One real root — C++ uses sqrtf, cbrt (double).
      final sd = f(LibM.sqrtf(discriminant));
      final u1 = f(LibM.cbrt(f(sd - q2)));
      final v1 = f(LibM.cbrt(f(sd + q2)));
      final root1 = f(f(u1 - v1) - f(ba / 3.0));

      return rangeF(root1, 0.0, 1.0);
    }
  }

  /// Floating-point modulo with sign of dividend preserved.
  static double modF(double dividend, double divisor) {
    if (!dividend.isFinite || divisor == 0.0 || dividend.isNaN || divisor.isNaN) {
      return double.nan;
    }

    final absDividend = dividend.abs();
    final absDivisor = divisor.abs();
    final result = absDividend - (absDividend / absDivisor).floorToDouble() * absDivisor;
    return dividend.isNegative ? -result : result;
  }
}
