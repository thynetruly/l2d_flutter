import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Utility for allocating memory with a specific byte alignment.
///
/// The Cubism Core API requires:
/// - Moc buffers aligned to 64 bytes ([csmAlignofMoc])
/// - Model buffers aligned to 16 bytes ([csmAlignofModel])
///
/// Dart's default [malloc] does not guarantee these alignments, so we
/// over-allocate and manually align the returned pointer.
class AlignedMemory {
  /// The raw (unaligned) allocation from malloc.
  final Pointer<Uint8> _rawPointer;

  /// The aligned pointer within the raw allocation.
  final Pointer<Uint8> alignedPointer;

  /// The usable size at the aligned pointer.
  final int size;

  AlignedMemory._(this._rawPointer, this.alignedPointer, this.size);

  /// Allocates [size] bytes with the given [alignment].
  ///
  /// The [alignment] must be a positive power of two.
  factory AlignedMemory.allocate(int size, {required int alignment}) {
    assert(alignment > 0 && (alignment & (alignment - 1)) == 0,
        'Alignment must be a positive power of two');

    // Over-allocate by (alignment - 1) bytes to guarantee we can align.
    final rawSize = size + alignment - 1;
    final rawPointer = malloc<Uint8>(rawSize);
    if (rawPointer == nullptr) {
      throw StateError('Failed to allocate $rawSize bytes');
    }

    // Align the pointer: round up to the next multiple of alignment.
    final rawAddress = rawPointer.address;
    final alignedAddress = (rawAddress + alignment - 1) & ~(alignment - 1);
    final alignedPointer = Pointer<Uint8>.fromAddress(alignedAddress);

    return AlignedMemory._(rawPointer, alignedPointer, size);
  }

  /// Allocates aligned memory and copies [data] into it.
  factory AlignedMemory.fromBytes(Uint8List data, {required int alignment}) {
    final mem = AlignedMemory.allocate(data.length, alignment: alignment);
    mem.alignedPointer.asTypedList(data.length).setAll(0, data);
    return mem;
  }

  /// Returns the aligned pointer as a [Pointer<Void>].
  Pointer<Void> get voidPointer => alignedPointer.cast<Void>();

  /// Frees the underlying allocation.
  void free() {
    malloc.free(_rawPointer);
  }
}
