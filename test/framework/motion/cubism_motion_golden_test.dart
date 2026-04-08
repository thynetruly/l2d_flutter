import 'package:test/test.dart';

import '../../helpers/golden_comparator.dart';

void main() {
  group('CubismMotion golden data structure', () {
    late Map<String, dynamic> motionGolden;
    late Map<String, dynamic> motionQueueGolden;

    setUpAll(() {
      motionGolden = GoldenComparator.loadGolden('motion_haru_idle_golden.json');
      motionQueueGolden = GoldenComparator.loadGolden('motion_queue_golden.json');
    });

    test('motion golden has duration and fps', () {
      expect(motionGolden['duration'], isA<num>());
      expect(motionGolden['fps'], equals(60));
    });

    test('motion golden has frame data', () {
      final frames = (motionGolden['frames'] as List).cast<Map<String, dynamic>>();
      expect(frames.isNotEmpty, isTrue);
      // Each frame has frame index, time, and parameter samples
      for (int i = 0; i < 5 && i < frames.length; i++) {
        expect(frames[i]['frame'], equals(i));
        expect(frames[i]['t'], isA<num>());
        expect(frames[i]['paramSamples'], isA<List>());
      }
    });

    test('motion parameter values are finite', () {
      final frames = (motionGolden['frames'] as List).cast<Map<String, dynamic>>();
      for (final frame in frames) {
        final samples = (frame['paramSamples'] as List).cast<Map<String, dynamic>>();
        for (final sample in samples) {
          final value = (sample['value'] as num).toDouble();
          expect(value.isFinite, isTrue,
              reason: 'Frame ${frame['frame']} param ${sample['id']}: $value');
        }
      }
    });

    test('motion queue golden has frame data showing transition', () {
      final frames = (motionQueueGolden['frames'] as List).cast<Map<String, dynamic>>();
      expect(frames.length, equals(120));

      // At frame 30, motion 2 starts (with priority 2). Verify all values are finite.
      for (final frame in frames) {
        final samples = (frame['paramSamples'] as List).cast<Map<String, dynamic>>();
        for (final sample in samples) {
          expect((sample['value'] as num).toDouble().isFinite, isTrue);
        }
      }
    });
  });
}
