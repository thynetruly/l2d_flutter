import 'dart:convert';
import 'dart:math' as math;

import '../../core/cubism_model.dart';

/// Blend mode for expression parameters.
enum ExpressionBlendType {
  /// Additive: current + value * weight (default value: 0.0).
  additive,

  /// Multiplicative: current * (1 + (value - 1) * weight) (default value: 1.0).
  multiply,

  /// Overwrite: current * (1 - weight) + value * weight.
  overwrite,
}

/// A single parameter modification within an expression.
class ExpressionParameter {
  final String parameterId;
  final ExpressionBlendType blendType;
  final double value;

  const ExpressionParameter({
    required this.parameterId,
    required this.blendType,
    required this.value,
  });
}

/// Default additive value (identity for addition).
const double defaultAdditiveValue = 0.0;

/// Default multiplicative value (identity for multiplication).
const double defaultMultiplyValue = 1.0;

/// A facial expression from an exp3.json file.
///
/// Ported from Framework/src/Motion/CubismExpressionMotion.hpp.
///
/// Each expression modifies a set of parameters using blend modes:
/// - **Additive**: Adds to the current parameter value
/// - **Multiply**: Multiplies the current parameter value
/// - **Overwrite**: Replaces the current parameter value
class CubismExpressionMotion {
  final List<ExpressionParameter> parameters;
  final double fadeInTime;
  final double fadeOutTime;

  CubismExpressionMotion._({
    required this.parameters,
    this.fadeInTime = 1.0,
    this.fadeOutTime = 1.0,
  });

  /// Creates an expression from an exp3.json string.
  factory CubismExpressionMotion.fromString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return _parseExpression(json);
  }

  /// Creates an expression from exp3.json raw bytes.
  factory CubismExpressionMotion.fromBytes(List<int> bytes) {
    return CubismExpressionMotion.fromString(utf8.decode(bytes));
  }

  /// Applies this expression's parameters to the model with the given weight.
  void applyParameters(CubismModel model, double weight) {
    for (final param in parameters) {
      final p = model.getParameter(param.parameterId);
      if (p == null) continue;

      switch (param.blendType) {
        case ExpressionBlendType.additive:
          // current + value * weight
          p.value = p.value + param.value * weight;
        case ExpressionBlendType.multiply:
          // current * (1 + (value - 1) * weight)
          p.value = p.value * (1.0 + (param.value - 1.0) * weight);
        case ExpressionBlendType.overwrite:
          // current * (1 - weight) + value * weight
          p.value = p.value * (1.0 - weight) + param.value * weight;
      }
    }
  }

  static CubismExpressionMotion _parseExpression(Map<String, dynamic> json) {
    final fadeIn = (json['FadeInTime'] as num?)?.toDouble() ?? 1.0;
    final fadeOut = (json['FadeOutTime'] as num?)?.toDouble() ?? 1.0;

    final params = <ExpressionParameter>[];
    final paramsJson = json['Parameters'] as List? ?? [];

    for (final p in paramsJson) {
      final m = p as Map<String, dynamic>;
      final blendStr = m['Blend'] as String? ?? 'Add';
      final blendType = switch (blendStr) {
        'Add' => ExpressionBlendType.additive,
        'Multiply' => ExpressionBlendType.multiply,
        'Overwrite' => ExpressionBlendType.overwrite,
        _ => ExpressionBlendType.additive,
      };

      params.add(ExpressionParameter(
        parameterId: m['Id'] as String,
        blendType: blendType,
        value: (m['Value'] as num).toDouble(),
      ));
    }

    return CubismExpressionMotion._(
      parameters: params,
      fadeInTime: fadeIn,
      fadeOutTime: fadeOut,
    );
  }
}

/// Accumulator for expression parameter blending across multiple expressions.
class ExpressionParameterValue {
  final String parameterId;
  double additiveValue;
  double multiplyValue;
  double overwriteValue;

  ExpressionParameterValue({
    required this.parameterId,
    this.additiveValue = 0.0,
    this.multiplyValue = 1.0,
    this.overwriteValue = 0.0,
  });
}

/// Manages multiple concurrent expressions with crossfade blending.
///
/// Ported from Framework/src/Motion/CubismExpressionMotionManager.hpp.
///
/// Final parameter value = (overwriteValue + additiveValue) * multiplyValue
class CubismExpressionMotionManager {
  final List<_ExpressionEntry> _expressions = [];
  final List<ExpressionParameterValue> _parameterValues = [];
  final List<double> _fadeWeights = [];
  double _userTimeSeconds = 0.0;

  /// Starts playing an expression, fading out previous ones.
  void startExpression(CubismExpressionMotion expression) {
    // Trigger fade-out on current expressions
    for (final entry in _expressions) {
      entry.isTriggeredFadeOut = true;
      entry.fadeOutSeconds = expression.fadeOutTime;
    }

    _expressions.add(_ExpressionEntry(expression));
    _fadeWeights.add(0.0);
  }

  /// Updates all expressions and applies blended values to the model.
  bool updateMotion(CubismModel model, double deltaTimeSeconds) {
    _userTimeSeconds += deltaTimeSeconds;
    bool updated = false;

    // Ensure parameter value list covers all model parameters
    _ensureParameterValues(model);

    double expressionWeight = 0.0;
    int expressionIndex = 0;

    final toRemove = <int>[];
    for (int i = 0; i < _expressions.length; i++) {
      final entry = _expressions[i];
      final expression = entry.expression;

      // Setup on first update
      if (!entry.started) {
        entry.started = true;
        entry.startTimeSeconds = _userTimeSeconds;
        entry.fadeInStartTimeSeconds = _userTimeSeconds;
        if (expression.fadeOutTime > 0.0) {
          entry.endTimeSeconds = -1.0; // Indefinite until triggered
        }
      }

      // Calculate fade weight
      final fadein = (expression.fadeInTime <= 0.0)
          ? 1.0
          : _easingSine((_userTimeSeconds - entry.fadeInStartTimeSeconds) /
              expression.fadeInTime);

      double fadeout = 1.0;
      if (entry.endTimeSeconds > 0.0) {
        fadeout = (expression.fadeOutTime <= 0.0)
            ? 1.0
            : _easingSine(
                (entry.endTimeSeconds - _userTimeSeconds) / expression.fadeOutTime);
      }

      final fadeWeight = (fadein * fadeout).clamp(0.0, 1.0);
      if (i < _fadeWeights.length) {
        _fadeWeights[i] = fadeWeight;
      }

      // Calculate expression parameter values
      _calculateExpressionParameters(
        model, expression, expressionIndex, fadeWeight);

      expressionWeight += fadein.clamp(0.0, 1.0);

      // Handle triggered fade-out
      if (entry.isTriggeredFadeOut && entry.endTimeSeconds < 0.0) {
        entry.endTimeSeconds = _userTimeSeconds + entry.fadeOutSeconds;
      }

      // Check if finished
      if (entry.endTimeSeconds > 0.0 && entry.endTimeSeconds < _userTimeSeconds) {
        toRemove.add(i);
      }

      expressionIndex++;
      updated = true;
    }

    // Cleanup completed: keep only latest if fully faded in
    if (_expressions.length > 1) {
      final lastIdx = _expressions.length - 1;
      if (lastIdx < _fadeWeights.length && _fadeWeights[lastIdx] >= 1.0) {
        for (int i = lastIdx - 1; i >= 0; i--) {
          _expressions.removeAt(i);
          if (i < _fadeWeights.length) _fadeWeights.removeAt(i);
        }
        toRemove.clear();
      }
    }

    // Remove finished entries
    for (int i = toRemove.length - 1; i >= 0; i--) {
      final idx = toRemove[i];
      if (idx < _expressions.length) _expressions.removeAt(idx);
      if (idx < _fadeWeights.length) _fadeWeights.removeAt(idx);
    }

    // Apply blended values to model
    expressionWeight = expressionWeight.clamp(0.0, 1.0);
    for (final pv in _parameterValues) {
      final param = model.getParameter(pv.parameterId);
      if (param == null) continue;

      final value = (pv.overwriteValue + pv.additiveValue) * pv.multiplyValue;
      param.value = param.value * (1.0 - expressionWeight) + value * expressionWeight;

      // Reset accumulators for next frame
      pv.additiveValue = defaultAdditiveValue;
      pv.multiplyValue = defaultMultiplyValue;
    }

    return updated;
  }

  void _ensureParameterValues(CubismModel model) {
    final existingIds = _parameterValues.map((e) => e.parameterId).toSet();
    for (final param in model.parameters) {
      if (!existingIds.contains(param.id)) {
        _parameterValues.add(ExpressionParameterValue(
          parameterId: param.id,
          additiveValue: defaultAdditiveValue,
          multiplyValue: defaultMultiplyValue,
          overwriteValue: param.value,
        ));
      }
    }
  }

  void _calculateExpressionParameters(
    CubismModel model,
    CubismExpressionMotion expression,
    int expressionIndex,
    double fadeWeight,
  ) {
    for (final pv in _parameterValues) {
      final currentValue = model.getParameter(pv.parameterId)?.value ?? 0.0;

      // Find this parameter in the expression
      ExpressionParameter? exprParam;
      for (final ep in expression.parameters) {
        if (ep.parameterId == pv.parameterId) {
          exprParam = ep;
          break;
        }
      }

      double newAdditive, newMultiply, newOverwrite;

      if (exprParam == null) {
        // Not referenced by this expression: use defaults
        newAdditive = defaultAdditiveValue;
        newMultiply = defaultMultiplyValue;
        newOverwrite = currentValue;
      } else {
        switch (exprParam.blendType) {
          case ExpressionBlendType.additive:
            newAdditive = exprParam.value;
            newMultiply = defaultMultiplyValue;
            newOverwrite = currentValue;
          case ExpressionBlendType.multiply:
            newAdditive = defaultAdditiveValue;
            newMultiply = exprParam.value;
            newOverwrite = currentValue;
          case ExpressionBlendType.overwrite:
            newAdditive = defaultAdditiveValue;
            newMultiply = defaultMultiplyValue;
            newOverwrite = exprParam.value;
        }
      }

      if (expressionIndex == 0) {
        pv.additiveValue = newAdditive;
        pv.multiplyValue = newMultiply;
        pv.overwriteValue = newOverwrite;
      } else {
        pv.additiveValue =
            pv.additiveValue * (1.0 - fadeWeight) + newAdditive * fadeWeight;
        pv.multiplyValue =
            pv.multiplyValue * (1.0 - fadeWeight) + newMultiply * fadeWeight;
        pv.overwriteValue =
            pv.overwriteValue * (1.0 - fadeWeight) + newOverwrite * fadeWeight;
      }
    }
  }

  static double _easingSine(double value) {
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return 0.5 - 0.5 * math.cos(value * 3.1415926535897932384626433832795);
  }
}

class _ExpressionEntry {
  final CubismExpressionMotion expression;
  bool started = false;
  bool isTriggeredFadeOut = false;
  double startTimeSeconds = -1.0;
  double fadeInStartTimeSeconds = 0.0;
  double endTimeSeconds = -1.0;
  double fadeOutSeconds = 0.0;

  _ExpressionEntry(this.expression);
}
