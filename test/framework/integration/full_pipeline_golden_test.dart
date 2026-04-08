import 'package:test/test.dart';

import '../../helpers/golden_comparator.dart';

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    golden = GoldenComparator.loadGolden('full_pipeline_haru_golden.json');
  });

  group('Full pipeline golden data', () {
    test('contains 300 frames', () {
      expect(golden['frames'], equals(300));
      final frameData = (golden['frameData'] as List).cast<Map<String, dynamic>>();
      expect(frameData.length, equals(300));
    });

    test('all parameter values are finite across 300 frames', () {
      final frameData = (golden['frameData'] as List).cast<Map<String, dynamic>>();
      for (final frame in frameData) {
        final samples =
            (frame['paramSamples'] as List).cast<Map<String, dynamic>>();
        for (final sample in samples) {
          final value = (sample['value'] as num).toDouble();
          expect(value.isFinite, isTrue,
              reason: 'Frame ${frame['frame']} param ${sample['id']}: $value');
        }
      }
    });

    test('parameter values change throughout simulation', () {
      // Verify the pipeline (motion + physics + eye blink + breath) actually
      // produces non-trivial parameter changes over time
      final frameData = (golden['frameData'] as List).cast<Map<String, dynamic>>();
      final firstSamples =
          (frameData[0]['paramSamples'] as List).cast<Map<String, dynamic>>();
      final lastSamples =
          (frameData[frameData.length - 1]['paramSamples'] as List)
              .cast<Map<String, dynamic>>();

      // At least one parameter should differ between first and last frame
      bool anyChanged = false;
      for (int i = 0; i < firstSamples.length && i < lastSamples.length; i++) {
        final v1 = (firstSamples[i]['value'] as num).toDouble();
        final v2 = (lastSamples[i]['value'] as num).toDouble();
        if ((v1 - v2).abs() > 1e-6) {
          anyChanged = true;
          break;
        }
      }
      expect(anyChanged, isTrue,
          reason: 'At least one parameter should change over 300 frames');
    });
  });
}
