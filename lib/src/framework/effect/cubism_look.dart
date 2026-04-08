import '../../core/cubism_model.dart';

/// Configuration for a single look/gaze parameter.
class LookParameterData {
  /// Parameter ID to control.
  final String parameterId;

  /// Coefficient for X-axis drag input.
  final double factorX;

  /// Coefficient for Y-axis drag input.
  final double factorY;

  /// Coefficient for combined XY drag input.
  final double factorXY;

  const LookParameterData({
    required this.parameterId,
    this.factorX = 0.0,
    this.factorY = 0.0,
    this.factorXY = 0.0,
  });
}

/// Gaze/drag parameter following effect.
///
/// Ported from Framework/src/Effect/CubismLook.hpp.
///
/// Maps drag input to model parameters using linear combination:
/// `delta = factorX * dragX + factorY * dragY + factorXY * (dragX * dragY)`
class CubismLook {
  /// Look parameter configurations.
  List<LookParameterData> parameters;

  CubismLook({this.parameters = const []});

  /// Updates look parameters on [model] based on drag input.
  ///
  /// [dragX] and [dragY] are typically in range [-1, 1] representing
  /// the user's gaze/touch position relative to the model center.
  void updateParameters(CubismModel model, double dragX, double dragY) {
    final dragXY = dragX * dragY;

    for (final data in parameters) {
      final param = model.getParameter(data.parameterId);
      if (param == null) continue;

      final delta =
          data.factorX * dragX + data.factorY * dragY + data.factorXY * dragXY;
      // Additive blend
      param.value = param.value + delta;
    }
  }
}
