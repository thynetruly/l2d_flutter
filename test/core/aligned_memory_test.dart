import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/core/aligned_memory.dart';

void main() {
  group('AlignedMemory', () {
    test('allocates with 64-byte alignment', () {
      final mem = AlignedMemory.allocate(1024, alignment: 64);
      expect(mem.alignedPointer.address % 64, equals(0));
      expect(mem.size, equals(1024));
      mem.free();
    });

    test('allocates with 16-byte alignment', () {
      final mem = AlignedMemory.allocate(512, alignment: 16);
      expect(mem.alignedPointer.address % 16, equals(0));
      expect(mem.size, equals(512));
      mem.free();
    });

    test('fromBytes copies data correctly', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final mem = AlignedMemory.fromBytes(data, alignment: 64);
      expect(mem.alignedPointer.address % 64, equals(0));

      final view = mem.alignedPointer.asTypedList(8);
      for (int i = 0; i < 8; i++) {
        expect(view[i], equals(data[i]));
      }
      mem.free();
    });

    test('multiple allocations produce different aligned addresses', () {
      final mem1 = AlignedMemory.allocate(100, alignment: 64);
      final mem2 = AlignedMemory.allocate(100, alignment: 64);
      expect(mem1.alignedPointer.address,
          isNot(equals(mem2.alignedPointer.address)));
      mem1.free();
      mem2.free();
    });

    test('alignment must be power of two', () {
      expect(
        () => AlignedMemory.allocate(100, alignment: 3),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
