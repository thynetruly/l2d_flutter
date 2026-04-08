import '../../core/cubism_model.dart';
import '../math/cubism_math.dart';
import '../math/float32.dart';
import '../math/libm.dart';

/// Configuration for a single breathing parameter.
class BreathParameterData {
  /// Parameter ID to modify.
  final String parameterId;

  /// Offset of the sine wave.
  final double offset;

  /// Peak amplitude of the sine wave.
  final double peak;

  /// Cycle period in seconds.
  final double cycle;

  /// Blending weight (0.0 to 1.0).
  final double weight;

  const BreathParameterData({
    required this.parameterId,
    this.offset = 0.0,
    this.peak = 0.0,
    this.cycle = 1.0,
    this.weight = 0.5,
  });
}

/// Cyclic breathing animation using sine waves.
///
/// Ported from Framework/src/Effect/CubismBreath.hpp.
///
/// Formula: `value = offset + peak * sin(2π * currentTime / cycle)`
/// Applied via additive blending with the given weight.
class CubismBreath {
  /// Breathing parameter configurations.
  List<BreathParameterData> parameters;

  double _currentTime = 0.0;

  CubismBreath({this.parameters = const []});

  /// Current accumulated time.
  double get currentTime => _currentTime;

  /// Updates breathing parameters on [model].
  ///
  /// For each configured parameter, calculates:
  /// `value = offset + peak * sinf(2π * currentTime / cycle)`
  /// and adds it to the parameter value with the configured weight.
  ///
  /// Uses [LibM.sinf] and float32 truncation throughout for bit-exact parity
  /// with the C++ Cubism Framework.
  void updateParameters(CubismModel model, double deltaTimeSeconds) {
    // Match C++ csmFloat32 _currentTime accumulator (truncated each frame).
    _currentTime = Float32.cast(_currentTime + deltaTimeSeconds);
    final t = Float32.cast(_currentTime * Float32.cast(2.0 * CubismMath.pi));

    for (final data in parameters) {
      final param = model.getParameter(data.parameterId);
      if (param == null) continue;

      final s = LibM.sinf(Float32.cast(t / data.cycle));
      final value = Float32.cast(data.offset + Float32.cast(data.peak * s));
      // Additive blend: model->AddParameterValue(id, value, weight)
      param.value = param.value + value * data.weight;
    }
  }
}
