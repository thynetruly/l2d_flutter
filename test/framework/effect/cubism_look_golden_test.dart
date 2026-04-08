import 'package:test/test.dart';

import '../../helpers/golden_comparator.dart';

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    golden = GoldenComparator.loadGolden('look_golden.json');
  });

  group('CubismLook parity (vs C++ golden)', () {
    test('drag-to-parameter formula matches C++ for all inputs', () {
      final factorX = (golden['factorX'] as num).toDouble();
      final factorY = (golden['factorY'] as num).toDouble();
      final factorXY = (golden['factorXY'] as num).toDouble();
      final inputs =
          (golden['inputs'] as List).cast<Map<String, dynamic>>();

      for (int i = 0; i < inputs.length; i++) {
        final dragX = (inputs[i]['dragX'] as num).toDouble();
        final dragY = (inputs[i]['dragY'] as num).toDouble();
        final expected = (inputs[i]['delta'] as num).toDouble();

        final actual =
            factorX * dragX + factorY * dragY + factorXY * dragX * dragY;

        expect(actual, closeTo(expected, 1e-6),
            reason: 'Look input $i: dragX=$dragX dragY=$dragY');
      }
    });
  });
}
