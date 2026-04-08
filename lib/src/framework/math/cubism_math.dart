import 'dart:math' as math;

import 'cubism_vector2.dart';

/// Static math utility functions for the Cubism Framework.
///
/// Ported from Framework/src/Math/CubismMath.hpp.
class CubismMath {
  CubismMath._();

  static const double pi = 3.1415926535897932384626433832795;
  static const double epsilon = 0.00001;

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

  /// Sine function.
  static double sinF(double x) => math.sin(x);

  /// Cosine function.
  static double cosF(double x) => math.cos(x);

  /// Absolute value.
  static double absF(double x) => x.abs();

  /// Square root.
  static double sqrtF(double x) => math.sqrt(x);

  /// Returns the larger of [l] and [r].
  static double max(double l, double r) => (l > r) ? l : r;

  /// Returns the smaller of [l] and [r].
  static double min(double l, double r) => (l > r) ? r : l;

  /// Sine-wave easing for fade-in/fade-out.
  ///
  /// Maps [value] in [0..1] to a smooth ease curve using cosine.
  /// Formula: `0.5 - 0.5 * cos(value * pi)`
  static double getEasingSine(double value) {
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return 0.5 - 0.5 * cosF(value * pi);
  }

  /// Converts degrees to radians.
  static double degreesToRadian(double degrees) => (degrees / 180.0) * pi;

  /// Converts radians to degrees.
  static double radianToDegrees(double radian) => (radian * 180.0) / pi;

  /// Calculates the angle between two vectors in radians.
  ///
  /// Result is normalized to [-pi, pi] range.
  static double directionToRadian(CubismVector2 from, CubismVector2 to) {
    final q1 = math.atan2(to.y, to.x);
    final q2 = math.atan2(from.y, from.x);
    var ret = q1 - q2;

    while (ret < -pi) {
      ret += pi * 2.0;
    }
    while (ret > pi) {
      ret -= pi * 2.0;
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
    return -(b + math.sqrt(b * b - 4.0 * a * c)) / (2.0 * a);
  }

  /// Solves a cubic equation using Cardano's algorithm for Bezier curves.
  ///
  /// Solves: `a*x^3 + b*x^2 + c*x + d = 0`
  /// Returns a solution in [0.0, 1.0] for valid Bezier t-values.
  static double cardanoAlgorithmForBezier(
      double a, double b, double c, double d) {
    if (absF(a) < epsilon) {
      return rangeF(quadraticEquation(b, c, d), 0.0, 1.0);
    }

    final ba = b / a;
    final ca = c / a;
    final da = d / a;

    final p = (3.0 * ca - ba * ba) / 3.0;
    final p3 = p / 3.0;
    final q = (2.0 * ba * ba * ba - 9.0 * ba * ca + 27.0 * da) / 27.0;
    final q2 = q / 2.0;
    final discriminant = q2 * q2 + p3 * p3 * p3;

    const center = 0.5;
    const threshold = center + 0.01;

    if (discriminant < 0.0) {
      // Three distinct real roots
      final mp3 = -p / 3.0;
      final mp33 = mp3 * mp3 * mp3;
      final r = math.sqrt(mp33);
      final t = -q / (2.0 * r);
      final cosphi = rangeF(t, -1.0, 1.0);
      final phi = math.acos(cosphi);
      final crtr = _cbrt(r);
      final t1 = 2.0 * crtr;

      final root1 = t1 * math.cos(phi / 3.0) - ba / 3.0;
      final root2 = t1 * math.cos((phi + 2.0 * pi) / 3.0) - ba / 3.0;
      final root3 = t1 * math.cos((phi + 4.0 * pi) / 3.0) - ba / 3.0;

      if ((root1 - center).abs() < threshold) {
        return rangeF(root1, 0.0, 1.0);
      }
      if ((root2 - center).abs() < threshold) {
        return rangeF(root2, 0.0, 1.0);
      }
      return rangeF(root3, 0.0, 1.0);
    } else if (discriminant == 0.0) {
      // Repeated roots
      double u1;
      if (q2 < 0.0) {
        u1 = _cbrt(-q2);
      } else {
        u1 = -_cbrt(q2);
      }

      final root1 = 2.0 * u1 - ba / 3.0;
      final root2 = -u1 - ba / 3.0;

      if ((root1 - center).abs() < threshold) {
        return rangeF(root1, 0.0, 1.0);
      }
      return rangeF(root2, 0.0, 1.0);
    } else {
      // One real root
      final sd = math.sqrt(discriminant);
      final u1 = _cbrt(sd - q2);
      final v1 = _cbrt(sd + q2);
      final root1 = u1 - v1 - ba / 3.0;

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

  /// Cube root function (handles negative values).
  static double _cbrt(double x) {
    if (x >= 0.0) {
      return math.pow(x, 1.0 / 3.0).toDouble();
    }
    return -math.pow(-x, 1.0 / 3.0).toDouble();
  }
}
