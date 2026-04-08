import 'dart:math' as math;

import '../../core/cubism_model.dart';

/// Eye state for the blink state machine.
enum EyeState {
  first,
  interval,
  closing,
  closed,
  opening,
}

/// Automatic eye blinking effect using a state machine.
///
/// Ported from Framework/src/Effect/CubismEyeBlink.hpp.
///
/// States: First → Interval → Closing → Closed → Opening → Interval → ...
/// Parameter value: 1.0 = fully open, 0.0 = fully closed.
class CubismEyeBlink {
  /// Parameter IDs to control (typically "ParamEyeLOpen", "ParamEyeROpen").
  List<String> parameterIds;

  EyeState _blinkingState = EyeState.first;
  double _nextBlinkingTime = 0.0;
  double _stateStartTimeSeconds = 0.0;

  /// Average interval between blinks (seconds). Default: 4.0.
  double blinkingIntervalSeconds;

  /// Duration of the closing phase (seconds). Default: 0.1.
  double closingSeconds;

  /// Duration of the closed phase (seconds). Default: 0.05.
  double closedSeconds;

  /// Duration of the opening phase (seconds). Default: 0.15.
  double openingSeconds;

  double _userTimeSeconds = 0.0;
  final math.Random _random;

  CubismEyeBlink({
    this.parameterIds = const [],
    this.blinkingIntervalSeconds = 4.0,
    this.closingSeconds = 0.1,
    this.closedSeconds = 0.05,
    this.openingSeconds = 0.15,
    math.Random? random,
  }) : _random = random ?? math.Random();

  /// Creates an instance from model settings, auto-populating parameter IDs.
  factory CubismEyeBlink.fromParameterIds(List<String> parameterIds,
      {math.Random? random}) {
    return CubismEyeBlink(parameterIds: parameterIds, random: random);
  }

  /// Current eye state.
  EyeState get state => _blinkingState;

  /// Sets blink timing parameters.
  void setBlinkingSettings(double closing, double closed, double opening) {
    closingSeconds = closing;
    closedSeconds = closed;
    openingSeconds = opening;
  }

  /// Updates the blink state machine and applies parameter values to [model].
  void updateParameters(CubismModel model, double deltaTimeSeconds) {
    _userTimeSeconds += deltaTimeSeconds;
    double parameterValue;

    switch (_blinkingState) {
      case EyeState.closing:
        var t = (_userTimeSeconds - _stateStartTimeSeconds) / closingSeconds;
        if (t >= 1.0) {
          t = 1.0;
          _blinkingState = EyeState.closed;
          _stateStartTimeSeconds = _userTimeSeconds;
        }
        parameterValue = 1.0 - t;

      case EyeState.closed:
        var t = (_userTimeSeconds - _stateStartTimeSeconds) / closedSeconds;
        if (t >= 1.0) {
          _blinkingState = EyeState.opening;
          _stateStartTimeSeconds = _userTimeSeconds;
        }
        parameterValue = 0.0;

      case EyeState.opening:
        var t = (_userTimeSeconds - _stateStartTimeSeconds) / openingSeconds;
        if (t >= 1.0) {
          t = 1.0;
          _blinkingState = EyeState.interval;
          _nextBlinkingTime = _determineNextBlinkingTiming();
        }
        parameterValue = t;

      case EyeState.interval:
        if (_nextBlinkingTime < _userTimeSeconds) {
          _blinkingState = EyeState.closing;
          _stateStartTimeSeconds = _userTimeSeconds;
        }
        parameterValue = 1.0;

      case EyeState.first:
        _blinkingState = EyeState.interval;
        _nextBlinkingTime = _determineNextBlinkingTiming();
        parameterValue = 1.0;
    }

    // Apply to all eye parameters
    for (final id in parameterIds) {
      final param = model.getParameter(id);
      if (param != null) {
        param.value = parameterValue;
      }
    }
  }

  double _determineNextBlinkingTiming() {
    final r = _random.nextDouble();
    return _userTimeSeconds + (r * (2.0 * blinkingIntervalSeconds - 1.0));
  }
}
