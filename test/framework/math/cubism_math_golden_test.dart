import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/framework/math/cubism_math.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_matrix44.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_vector2.dart';
import '../../helpers/golden_comparator.dart';

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    golden = GoldenComparator.loadGolden('math_golden.json');
  });

  group('CubismMath parity (vs C++ golden)', () {
    test('getEasingSine matches C++ for 101 sample points', () {
      final entries = (golden['easingSine'] as List).cast<Map<String, dynamic>>();
      final actual = <double>[];
      for (final e in entries) {
        actual.add(CubismMath.getEasingSine((e['t'] as num).toDouble()));
      }
      GoldenComparator.compareValues(
        goldenEntries: entries,
        actualValues: actual,
        valueKey: 'v',
        epsilon: 1e-6,
        label: 'getEasingSine',
      );
    });

    test('cardanoAlgorithmForBezier matches C++ for all test cases', () {
      final entries = (golden['bezier'] as List).cast<Map<String, dynamic>>();
      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];
        final a = (e['a'] as num).toDouble();
        final b = (e['b'] as num).toDouble();
        final c = (e['c'] as num).toDouble();
        final d = (e['d'] as num).toDouble();
        final expected = (e['result'] as num).toDouble();
        final actual = CubismMath.cardanoAlgorithmForBezier(a, b, c, d);
        expect(actual, closeTo(expected, 1e-5),
            reason: 'Bezier case $i: a=$a b=$b c=$c d=$d');
      }
    });

    test('matrix multiply matches C++', () {
      final cases = (golden['matrixMultiply'] as List).cast<Map<String, dynamic>>();
      for (final c in cases) {
        final a = Float32List.fromList(
            (c['a'] as List).map((e) => (e as num).toDouble()).toList());
        final b = Float32List.fromList(
            (c['b'] as List).map((e) => (e as num).toDouble()).toList());
        final expected = (c['result'] as List);
        final dst = Float32List(16);
        CubismMatrix44.multiply(a, b, dst);
        GoldenComparator.compareFloatList(
          golden: expected,
          actual: dst.toList(),
          epsilon: 1e-5,
          label: 'matrixMultiply',
        );
      }
    });

    test('matrix inverse matches C++', () {
      final cases = (golden['matrixInverse'] as List).cast<Map<String, dynamic>>();
      for (final c in cases) {
        final m = CubismMatrix44();
        final src = (c['matrix'] as List);
        for (int i = 0; i < 16; i++) {
          m.array[i] = (src[i] as num).toDouble();
        }
        final inv = m.getInvert();
        GoldenComparator.compareFloatList(
          golden: c['inverse'] as List,
          actual: inv.array.toList(),
          epsilon: 1e-5,
          label: 'matrixInverse',
        );
      }
    });

    test('directionToRadian matches C++', () {
      final entries = (golden['directionToRadian'] as List).cast<Map<String, dynamic>>();
      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];
        final from = CubismVector2(
            (e['fromX'] as num).toDouble(), (e['fromY'] as num).toDouble());
        final to = CubismVector2(
            (e['toX'] as num).toDouble(), (e['toY'] as num).toDouble());
        final expected = (e['result'] as num).toDouble();
        final actual = CubismMath.directionToRadian(from, to);
        expect(actual, closeTo(expected, 1e-6),
            reason: 'directionToRadian case $i');
      }
    });
  });
}
