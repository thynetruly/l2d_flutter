import 'dart:ffi';
import 'dart:typed_data';

import '../generated/cubism_core_bindings.dart';
import 'aligned_memory.dart';
import 'native_library.dart';

/// A parsed Cubism MOC (model data container).
///
/// MOC files (.moc3) contain the binary model data for a Live2D character.
/// This class loads and validates the MOC data, and can be used to create
/// [CubismModel] instances.
///
/// Memory is aligned to 64 bytes as required by the Core API.
/// Call [dispose] when no longer needed to free native memory.
class CubismMoc {
  final AlignedMemory _memory;
  final Pointer<csmMoc> _moc;
  bool _disposed = false;

  CubismMoc._(this._memory, this._moc);

  /// Loads a MOC from raw .moc3 file bytes.
  ///
  /// Throws [ArgumentError] if the data is empty.
  /// Throws [StateError] if the data fails consistency checks or cannot be parsed.
  factory CubismMoc.fromBytes(Uint8List mocData) {
    if (mocData.isEmpty) {
      throw ArgumentError.value(mocData, 'mocData', 'MOC data cannot be empty');
    }

    final bindings = NativeLibrary.bindings;

    // Allocate with 64-byte alignment as required by csmReviveMocInPlace.
    final memory = AlignedMemory.fromBytes(mocData, alignment: csmAlignofMoc);

    // Validate consistency before parsing.
    final isConsistent =
        bindings.csmHasMocConsistency(memory.voidPointer, mocData.length);
    if (isConsistent != 1) {
      memory.free();
      throw StateError('MOC data failed consistency check');
    }

    // Parse the moc in-place.
    final moc =
        bindings.csmReviveMocInPlace(memory.voidPointer, mocData.length);
    if (moc == nullptr) {
      memory.free();
      throw StateError('Failed to revive MOC from data');
    }

    return CubismMoc._(memory, moc);
  }

  /// The native moc pointer (for internal use by [CubismModel]).
  Pointer<csmMoc> get nativePointer {
    _checkNotDisposed();
    return _moc;
  }

  /// Returns the required buffer size (in bytes) to instantiate a model.
  int get modelSize {
    _checkNotDisposed();
    return NativeLibrary.bindings.csmGetSizeofModel(_moc);
  }

  /// Returns the MOC file format version.
  int get mocVersion {
    _checkNotDisposed();
    return NativeLibrary.bindings.csmGetMocVersion(
        _memory.voidPointer, _memory.size);
  }

  /// Whether this moc has been disposed.
  bool get isDisposed => _disposed;

  /// Frees the native memory associated with this MOC.
  ///
  /// After calling dispose, the MOC and any models created from it
  /// must no longer be used.
  void dispose() {
    if (!_disposed) {
      _memory.free();
      _disposed = true;
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('CubismMoc has been disposed');
    }
  }
}
