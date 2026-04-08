import 'dart:ffi';

/// A named parameter on a Cubism model.
///
/// Parameters control aspects of the model's appearance (e.g., eye openness,
/// head angle, mouth shape). Each parameter has an ID string, a value range
/// [minimumValue..maximumValue], a [defaultValue], and a mutable [value].
///
/// The [value] property writes directly to native memory via the model's
/// parameter values buffer.
class CubismParameter {
  /// The parameter's string ID (e.g., "ParamAngleX").
  final String id;

  /// Index of this parameter within the model.
  final int index;

  /// Minimum allowed value.
  final double minimumValue;

  /// Maximum allowed value.
  final double maximumValue;

  /// Default value.
  final double defaultValue;

  /// Parameter type (0 = Normal, 1 = BlendShape).
  final int type;

  /// Whether this parameter repeats (for animation looping).
  final int repeat;

  /// Pointer to the parameter values buffer in the native model.
  /// Index into this buffer using [index] to read/write this parameter.
  final Pointer<Float> _valuesPointer;

  CubismParameter({
    required this.id,
    required this.index,
    required this.minimumValue,
    required this.maximumValue,
    required this.defaultValue,
    required this.type,
    required this.repeat,
    required Pointer<Float> valuesPointer,
  }) : _valuesPointer = valuesPointer;

  /// Current value of this parameter.
  double get value => _valuesPointer[index];

  /// Sets the current value, clamped to [minimumValue..maximumValue].
  set value(double v) {
    _valuesPointer[index] = v.clamp(minimumValue, maximumValue);
  }

  /// Whether this is a normal parameter (not a blend shape).
  bool get isNormal => type == 0;

  /// Whether this is a blend shape parameter.
  bool get isBlendShape => type == 1;

  @override
  String toString() =>
      'CubismParameter($id: $value [$minimumValue..$maximumValue])';
}
