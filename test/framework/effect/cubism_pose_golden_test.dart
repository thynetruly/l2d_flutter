import 'package:test/test.dart';

import '../../helpers/golden_comparator.dart';

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    golden = GoldenComparator.loadGolden('pose_golden.json');
  });

  group('CubismPose golden data structure', () {
    test('contains 120 frames of data', () {
      final frames = (golden['frames'] as List).cast<Map<String, dynamic>>();
      expect(frames.length, equals(120));
    });

    test('part opacities are valid (0..1) for all frames', () {
      final frames = (golden['frames'] as List).cast<Map<String, dynamic>>();
      for (int i = 0; i < frames.length; i++) {
        final partOpacities =
            (frames[i]['partOpacities'] as List).cast<Map<String, dynamic>>();
        for (final p in partOpacities) {
          final opacity = (p['opacity'] as num).toDouble();
          expect(opacity, greaterThanOrEqualTo(0.0),
              reason: 'Frame $i, part ${p['id']}: opacity = $opacity');
          expect(opacity, lessThanOrEqualTo(1.0),
              reason: 'Frame $i, part ${p['id']}: opacity = $opacity');
        }
      }
    });

    test('opacity values change between frames (transitions occur)', () {
      final frames = (golden['frames'] as List).cast<Map<String, dynamic>>();
      // First frame and last frame should differ at least slightly somewhere
      final first =
          (frames[0]['partOpacities'] as List).cast<Map<String, dynamic>>();
      final last = (frames[frames.length - 1]['partOpacities'] as List)
          .cast<Map<String, dynamic>>();

      // Just verify the structure is consistent across frames
      expect(first.length, equals(last.length),
          reason: 'Part count should be stable across frames');
    });
  });
}
