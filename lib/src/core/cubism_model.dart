import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../generated/cubism_core_bindings.dart';
import 'aligned_memory.dart';
import 'cubism_canvas.dart';
import 'cubism_drawable.dart';
import 'cubism_moc.dart';
import 'cubism_parameter.dart';
import 'cubism_part.dart';
import 'native_library.dart';

/// A live instance of a Cubism model.
///
/// Created from a [CubismMoc], this class provides access to all model data:
/// parameters, parts, drawables, and canvas info. Parameter values and part
/// opacities can be modified directly, then [update] must be called to
/// propagate changes to drawables.
///
/// Call [dispose] when no longer needed to free native memory.
/// The source [CubismMoc] must outlive all models created from it.
class CubismModel {
  final CubismMoc _moc;
  final AlignedMemory _memory;
  final Pointer<csmModel> _model;
  final CubismCoreBindings _bindings;
  bool _disposed = false;

  // Cached parameter/part/drawable lists (built once on construction)
  late final List<CubismParameter> _parameters;
  late final List<CubismPart> _parts;
  late final List<CubismDrawable> _drawables;
  late final CubismCanvas _canvas;

  CubismModel._(this._moc, this._memory, this._model, this._bindings) {
    _buildParameters();
    _buildParts();
    _buildDrawables();
    _buildCanvas();
  }

  /// Creates a model instance from a [CubismMoc].
  ///
  /// The [moc] must not be disposed while this model is alive.
  /// Throws [StateError] if model initialization fails.
  factory CubismModel.fromMoc(CubismMoc moc) {
    final bindings = NativeLibrary.bindings;

    // Query required buffer size.
    final size = bindings.csmGetSizeofModel(moc.nativePointer);
    if (size == 0) {
      throw StateError('Failed to query model size from MOC');
    }

    // Allocate with 16-byte alignment as required by csmInitializeModelInPlace.
    final memory = AlignedMemory.allocate(size, alignment: csmAlignofModel);

    final model = bindings.csmInitializeModelInPlace(
        moc.nativePointer, memory.voidPointer, size);
    if (model == nullptr) {
      memory.free();
      throw StateError('Failed to initialize model from MOC');
    }

    return CubismModel._(moc, memory, model, bindings);
  }

  /// The native model pointer (for advanced/internal use).
  Pointer<csmModel> get nativePointer {
    _checkNotDisposed();
    return _model;
  }

  /// The source MOC this model was created from.
  CubismMoc get moc => _moc;

  // ---------------------------------------------------------------------------
  // UPDATE
  // ---------------------------------------------------------------------------

  /// Updates the model after parameter/opacity changes.
  ///
  /// Must be called after modifying parameter values or part opacities
  /// to propagate changes to drawable vertices, flags, etc.
  void update() {
    _checkNotDisposed();
    _bindings.csmUpdateModel(_model);
  }

  /// Resets all dynamic drawable flags (visibility/change tracking).
  void resetDynamicFlags() {
    _checkNotDisposed();
    _bindings.csmResetDrawableDynamicFlags(_model);
  }

  // ---------------------------------------------------------------------------
  // CANVAS
  // ---------------------------------------------------------------------------

  /// Canvas information (size, origin, pixels-per-unit).
  CubismCanvas get canvas {
    _checkNotDisposed();
    return _canvas;
  }

  // ---------------------------------------------------------------------------
  // PARAMETERS
  // ---------------------------------------------------------------------------

  /// All parameters on this model.
  List<CubismParameter> get parameters {
    _checkNotDisposed();
    return _parameters;
  }

  /// Number of parameters.
  int get parameterCount => _parameters.length;

  /// Gets a parameter by its string ID, or `null` if not found.
  CubismParameter? getParameter(String id) {
    for (final p in _parameters) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // PARTS
  // ---------------------------------------------------------------------------

  /// All parts on this model.
  List<CubismPart> get parts {
    _checkNotDisposed();
    return _parts;
  }

  /// Number of parts.
  int get partCount => _parts.length;

  /// Gets a part by its string ID, or `null` if not found.
  CubismPart? getPart(String id) {
    for (final p in _parts) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // DRAWABLES
  // ---------------------------------------------------------------------------

  /// All drawables on this model.
  List<CubismDrawable> get drawables {
    _checkNotDisposed();
    return _drawables;
  }

  /// Number of drawables.
  int get drawableCount => _drawables.length;

  /// Gets a drawable by its string ID, or `null` if not found.
  CubismDrawable? getDrawable(String id) {
    for (final d in _drawables) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Returns the render orders for all drawables.
  List<int> get renderOrders {
    _checkNotDisposed();
    final ptr = _bindings.csmGetRenderOrders(_model);
    return List<int>.generate(drawableCount, (i) => ptr[i]);
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  /// Whether this model has been disposed.
  bool get isDisposed => _disposed;

  /// Frees the native memory associated with this model.
  void dispose() {
    if (!_disposed) {
      _memory.free();
      _disposed = true;
    }
  }

  // ---------------------------------------------------------------------------
  // PRIVATE BUILDERS
  // ---------------------------------------------------------------------------

  void _buildParameters() {
    final count = _bindings.csmGetParameterCount(_model);
    if (count < 0) {
      _parameters = const [];
      return;
    }

    final ids = _bindings.csmGetParameterIds(_model);
    final types = _bindings.csmGetParameterTypes(_model);
    final mins = _bindings.csmGetParameterMinimumValues(_model);
    final maxs = _bindings.csmGetParameterMaximumValues(_model);
    final defaults = _bindings.csmGetParameterDefaultValues(_model);
    final values = _bindings.csmGetParameterValues(_model);
    final repeats = _bindings.csmGetParameterRepeats(_model);

    _parameters = List<CubismParameter>.generate(count, (i) {
      return CubismParameter(
        id: ids[i].cast<Utf8>().toDartString(),
        index: i,
        minimumValue: mins[i],
        maximumValue: maxs[i],
        defaultValue: defaults[i],
        type: types[i],
        repeat: repeats[i],
        valuesPointer: values,
      );
    });
  }

  void _buildParts() {
    final count = _bindings.csmGetPartCount(_model);
    if (count < 0) {
      _parts = const [];
      return;
    }

    final ids = _bindings.csmGetPartIds(_model);
    final opacities = _bindings.csmGetPartOpacities(_model);
    final parentIndices = _bindings.csmGetPartParentPartIndices(_model);

    _parts = List<CubismPart>.generate(count, (i) {
      return CubismPart(
        id: ids[i].cast<Utf8>().toDartString(),
        index: i,
        parentPartIndex: parentIndices[i],
        opacitiesPointer: opacities,
      );
    });
  }

  void _buildDrawables() {
    final count = _bindings.csmGetDrawableCount(_model);
    if (count < 0) {
      _drawables = const [];
      return;
    }

    final ids = _bindings.csmGetDrawableIds(_model);
    final constFlags = _bindings.csmGetDrawableConstantFlags(_model);
    final texIndices = _bindings.csmGetDrawableTextureIndices(_model);
    final parentPartIndices =
        _bindings.csmGetDrawableParentPartIndices(_model);

    _drawables = List<CubismDrawable>.generate(count, (i) {
      return CubismDrawable(
        id: ids[i].cast<Utf8>().toDartString(),
        index: i,
        constantFlags: constFlags[i],
        textureIndex: texIndices[i],
        parentPartIndex: parentPartIndices[i],
        model: _model,
        bindings: _bindings,
      );
    });
  }

  void _buildCanvas() {
    final sizePtr = calloc<csmVector2>();
    final originPtr = calloc<csmVector2>();
    final ppuPtr = calloc<Float>();

    _bindings.csmReadCanvasInfo(_model, sizePtr, originPtr, ppuPtr);

    _canvas = CubismCanvas(
      width: sizePtr.ref.X,
      height: sizePtr.ref.Y,
      originX: originPtr.ref.X,
      originY: originPtr.ref.Y,
      pixelsPerUnit: ppuPtr.value,
    );

    calloc.free(sizePtr);
    calloc.free(originPtr);
    calloc.free(ppuPtr);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('CubismModel has been disposed');
    }
  }
}
