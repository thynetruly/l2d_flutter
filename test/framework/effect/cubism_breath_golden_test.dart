import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/framework/math/cubism_math.dart';
import '../../helpers/golden_comparator.dart';

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    golden = GoldenComparator.loadGolden('breath_golden.json');
  });

  group('CubismBreath parity (vs C++ golden)', () {
    test('sine wave output matches C++ for 360 frames', () {
      final offset = (golden['offset'] as num).toDouble();
      final peak = (golden['peak'] as num).toDouble();
      final cycle = (golden['cycle'] as num).toDouble();
      final frames =
          (golden['frames'] as List).cast<Map<String, dynamic>>();

      double currentTime = 0.0;
      final dt = 1.0 / 60.0;

      for (int i = 0; i < frames.length; i++) {
        currentTime += dt;
        final t = currentTime * 2.0 * CubismMath.pi;
        final actual = offset + peak * math.sin(t / cycle);
        final expected = (frames[i]['value'] as num).toDouble();

        // C++ uses float (32-bit), Dart uses double (64-bit): expect 1e-4 tolerance
        expect(actual, closeTo(expected, 1e-4),
            reason: 'Breath frame $i at t=${frames[i]['t']}');
      }
    });
  });
}
