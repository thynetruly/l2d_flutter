import 'dart:convert';

import '../../core/cubism_model.dart';
import '../math/cubism_math.dart';

// ---------------------------------------------------------------------------
// Curve segment types and evaluation
// ---------------------------------------------------------------------------

/// A control point on a motion curve.
class MotionPoint {
  final double time;
  final double value;
  const MotionPoint(this.time, this.value);

  static MotionPoint lerp(MotionPoint a, MotionPoint b, double t) {
    return MotionPoint(
      a.time + (b.time - a.time) * t,
      a.value + (b.value - a.value) * t,
    );
  }
}

/// Segment types for motion curve interpolation.
enum MotionSegmentType { linear, bezier, stepped, inverseStepped }

/// A segment of a motion curve.
class MotionSegment {
  final MotionSegmentType type;
  final int basePointIndex;

  const MotionSegment(this.type, this.basePointIndex);

  /// Number of control points consumed by this segment type.
  int get pointCount {
    switch (type) {
      case MotionSegmentType.linear:
        return 2; // start + end
      case MotionSegmentType.bezier:
        return 4; // start + 2 control + end
      case MotionSegmentType.stepped:
      case MotionSegmentType.inverseStepped:
        return 2; // start + end
    }
  }
}

/// Target type for a motion curve.
enum MotionCurveTarget { model, parameter, partOpacity }

/// A single curve within a motion (controls one parameter/part/model property).
class MotionCurve {
  final MotionCurveTarget target;
  final String id;
  final int segmentCount;
  final int baseSegmentIndex;
  final double fadeInTime;
  final double fadeOutTime;

  const MotionCurve({
    required this.target,
    required this.id,
    required this.segmentCount,
    required this.baseSegmentIndex,
    this.fadeInTime = -1.0,
    this.fadeOutTime = -1.0,
  });
}

/// Parsed motion data from a motion3.json file.
class MotionData {
  final double duration;
  final double fps;
  final bool loop;
  final int curveCount;
  final List<MotionCurve> curves;
  final List<MotionSegment> segments;
  final List<MotionPoint> points;
  final List<MotionEvent> events;

  const MotionData({
    required this.duration,
    required this.fps,
    this.loop = false,
    required this.curveCount,
    required this.curves,
    required this.segments,
    required this.points,
    this.events = const [],
  });
}

/// A user-data event within a motion.
class MotionEvent {
  final double fireTime;
  final String value;
  const MotionEvent(this.fireTime, this.value);
}

// ---------------------------------------------------------------------------
// Segment evaluation functions
// ---------------------------------------------------------------------------

double _linearEvaluate(List<MotionPoint> points, int baseIndex, double time) {
  final p0 = points[baseIndex];
  final p1 = points[baseIndex + 1];
  var t = (time - p0.time) / (p1.time - p0.time);
  if (t < 0.0) t = 0.0;
  return p0.value + (p1.value - p0.value) * t;
}

double _bezierEvaluateCardano(
    List<MotionPoint> points, int baseIndex, double time) {
  final p0 = points[baseIndex];
  final p1 = points[baseIndex + 1];
  final p2 = points[baseIndex + 2];
  final p3 = points[baseIndex + 3];

  final x1 = p0.time;
  final x2 = p3.time;
  final cx1 = p1.time;
  final cx2 = p2.time;

  final a = x2 - 3.0 * cx2 + 3.0 * cx1 - x1;
  final b = 3.0 * cx2 - 6.0 * cx1 + 3.0 * x1;
  final c = 3.0 * cx1 - 3.0 * x1;
  final d = x1 - time;

  final t = CubismMath.cardanoAlgorithmForBezier(a, b, c, d);

  final q01 = MotionPoint.lerp(p0, p1, t);
  final q12 = MotionPoint.lerp(p1, p2, t);
  final q23 = MotionPoint.lerp(p2, p3, t);
  final q012 = MotionPoint.lerp(q01, q12, t);
  final q123 = MotionPoint.lerp(q12, q23, t);

  return MotionPoint.lerp(q012, q123, t).value;
}

double _steppedEvaluate(List<MotionPoint> points, int baseIndex, double time) {
  return points[baseIndex].value;
}

double _inverseSteppedEvaluate(
    List<MotionPoint> points, int baseIndex, double time) {
  return points[baseIndex + 1].value;
}

double _evaluateSegment(
    MotionSegment segment, List<MotionPoint> points, double time) {
  switch (segment.type) {
    case MotionSegmentType.linear:
      return _linearEvaluate(points, segment.basePointIndex, time);
    case MotionSegmentType.bezier:
      return _bezierEvaluateCardano(points, segment.basePointIndex, time);
    case MotionSegmentType.stepped:
      return _steppedEvaluate(points, segment.basePointIndex, time);
    case MotionSegmentType.inverseStepped:
      return _inverseSteppedEvaluate(points, segment.basePointIndex, time);
  }
}

/// Evaluates a curve at the given time.
double evaluateCurve(MotionData data, int curveIndex, double time) {
  final curve = data.curves[curveIndex];
  final totalSegmentCount = curve.baseSegmentIndex + curve.segmentCount;

  int target = -1;
  int pointPosition = 0;

  for (int i = curve.baseSegmentIndex; i < totalSegmentCount; i++) {
    final segment = data.segments[i];
    pointPosition = segment.basePointIndex +
        (segment.type == MotionSegmentType.bezier ? 3 : 1);

    if (data.points[pointPosition].time > time) {
      target = i;
      break;
    }
  }

  if (target == -1) {
    return data.points[pointPosition].value;
  }

  return _evaluateSegment(data.segments[target], data.points, time);
}

// ---------------------------------------------------------------------------
// CubismMotion
// ---------------------------------------------------------------------------

/// A motion animation parsed from a motion3.json file.
///
/// Ported from Framework/src/Motion/CubismMotion.hpp.
class CubismMotion {
  final MotionData _data;

  double fadeInSeconds = -1.0;
  double fadeOutSeconds = -1.0;
  double weight = 1.0;
  double offsetTime = 0.0;
  bool isLoop = false;

  List<String> eyeBlinkParameterIds = const [];
  List<String> lipSyncParameterIds = const [];

  double _modelOpacity = 1.0;

  CubismMotion._(this._data);

  /// Creates a motion from a motion3.json string.
  factory CubismMotion.fromString(String jsonString) {
    final data = _parseMotionJson(jsonString);
    return CubismMotion._(data);
  }

  /// Creates a motion from motion3.json raw bytes.
  factory CubismMotion.fromBytes(List<int> bytes) {
    return CubismMotion.fromString(utf8.decode(bytes));
  }

  /// The parsed motion data.
  MotionData get data => _data;

  /// Duration of the motion in seconds. Returns -1 if looping.
  double get duration => isLoop ? -1.0 : _data.duration;

  /// Duration of one loop cycle.
  double get loopDuration => _data.duration;

  /// Model opacity value from the motion's Opacity curve.
  double get modelOpacity => _modelOpacity;

  /// FPS from the source motion file.
  double get fps => _data.fps;

  /// Updates model parameters based on motion curves at the given time.
  ///
  /// [timeSeconds] is the elapsed time since motion start.
  /// [fadeWeight] is the current fade weight (0..1).
  void updateParameters(
    CubismModel model,
    double timeSeconds,
    double fadeWeight,
    double fadeInStartTime,
    double endTime,
  ) {
    if (_data.curveCount == 0) return;

    double time = timeSeconds;
    double motionDuration = _data.duration;

    if (isLoop) {
      motionDuration += 1.0 / _data.fps;
      while (time > motionDuration) {
        time -= motionDuration;
      }
    }

    // Compute global fade weights
    final tmpFadeIn = (fadeInSeconds <= 0.0)
        ? 1.0
        : CubismMath.getEasingSine(
            (timeSeconds - fadeInStartTime) / fadeInSeconds);
    final tmpFadeOut = (fadeOutSeconds <= 0.0 || endTime < 0.0)
        ? 1.0
        : CubismMath.getEasingSine((endTime - timeSeconds) / fadeOutSeconds);

    double eyeBlinkValue = double.maxFinite;
    double lipSyncValue = double.maxFinite;

    int c = 0;

    // Model curves (EyeBlink, LipSync, Opacity)
    for (; c < _data.curveCount && _data.curves[c].target == MotionCurveTarget.model; c++) {
      final value = evaluateCurve(_data, c, time);
      final curveId = _data.curves[c].id;

      if (curveId == 'EyeBlink') {
        eyeBlinkValue = value;
      } else if (curveId == 'LipSync') {
        lipSyncValue = value;
      } else if (curveId == 'Opacity') {
        _modelOpacity = value;
      }
    }

    // Parameter curves
    for (; c < _data.curveCount && _data.curves[c].target == MotionCurveTarget.parameter; c++) {
      final curve = _data.curves[c];
      final param = model.getParameter(curve.id);
      if (param == null) continue;

      final sourceValue = param.value;
      var value = evaluateCurve(_data, c, time);

      // Apply eye blink multiplier
      if (eyeBlinkValue != double.maxFinite) {
        for (final id in eyeBlinkParameterIds) {
          if (id == curve.id) {
            value *= eyeBlinkValue;
            break;
          }
        }
      }

      // Apply lip sync additive
      if (lipSyncValue != double.maxFinite) {
        for (final id in lipSyncParameterIds) {
          if (id == curve.id) {
            value += lipSyncValue;
            break;
          }
        }
      }

      // Per-parameter fade
      double fin, fout;
      if (curve.fadeInTime < 0.0) {
        fin = tmpFadeIn;
      } else {
        fin = (curve.fadeInTime == 0.0)
            ? 1.0
            : CubismMath.getEasingSine(
                (timeSeconds - fadeInStartTime) / curve.fadeInTime);
      }

      if (curve.fadeOutTime < 0.0) {
        fout = tmpFadeOut;
      } else {
        fout = (curve.fadeOutTime == 0.0 || endTime < 0.0)
            ? 1.0
            : CubismMath.getEasingSine(
                (endTime - timeSeconds) / curve.fadeOutTime);
      }

      final paramFadeWeight = (fin * fout).clamp(0.0, 1.0);
      param.value = sourceValue + (value - sourceValue) * paramFadeWeight;
    }

    // Part opacity curves
    for (; c < _data.curveCount && _data.curves[c].target == MotionCurveTarget.partOpacity; c++) {
      final curve = _data.curves[c];
      final value = evaluateCurve(_data, c, time);

      // Find part by ID and set opacity
      final part = model.getPart(curve.id);
      if (part != null) {
        part.opacity = value;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // motion3.json parsing
  // ---------------------------------------------------------------------------

  static MotionData _parseMotionJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final meta = json['Meta'] as Map<String, dynamic>;
    final duration = (meta['Duration'] as num).toDouble();
    final fps = (meta['Fps'] as num).toDouble();
    final loop = meta['Loop'] as bool? ?? false;
    final curveCount = (meta['CurveCount'] as num).toInt();

    final curves = <MotionCurve>[];
    final segments = <MotionSegment>[];
    final points = <MotionPoint>[];

    final curvesJson = json['Curves'] as List;
    for (final curveJson in curvesJson) {
      final cj = curveJson as Map<String, dynamic>;
      final targetStr = cj['Target'] as String;
      final target = switch (targetStr) {
        'Model' => MotionCurveTarget.model,
        'Parameter' => MotionCurveTarget.parameter,
        'PartOpacity' => MotionCurveTarget.partOpacity,
        _ => MotionCurveTarget.parameter,
      };

      final baseSegmentIndex = segments.length;
      final segmentData = cj['Segments'] as List;

      int segCount = 0;
      int i = 0;
      // First point
      if (segmentData.isNotEmpty) {
        points.add(MotionPoint(
          (segmentData[0] as num).toDouble(),
          (segmentData[1] as num).toDouble(),
        ));
        i = 2;
      }

      while (i < segmentData.length) {
        final typeId = (segmentData[i] as num).toInt();
        i++;

        final type = switch (typeId) {
          0 => MotionSegmentType.linear,
          1 => MotionSegmentType.bezier,
          2 => MotionSegmentType.stepped,
          3 => MotionSegmentType.inverseStepped,
          _ => MotionSegmentType.linear,
        };

        segments.add(MotionSegment(type, points.length - 1));
        segCount++;

        switch (type) {
          case MotionSegmentType.linear:
            points.add(MotionPoint(
              (segmentData[i] as num).toDouble(),
              (segmentData[i + 1] as num).toDouble(),
            ));
            i += 2;
          case MotionSegmentType.bezier:
            // 3 more points (control1, control2, end)
            for (int p = 0; p < 3; p++) {
              points.add(MotionPoint(
                (segmentData[i] as num).toDouble(),
                (segmentData[i + 1] as num).toDouble(),
              ));
              i += 2;
            }
          case MotionSegmentType.stepped:
            points.add(MotionPoint(
              (segmentData[i] as num).toDouble(),
              (segmentData[i + 1] as num).toDouble(),
            ));
            i += 2;
          case MotionSegmentType.inverseStepped:
            points.add(MotionPoint(
              (segmentData[i] as num).toDouble(),
              (segmentData[i + 1] as num).toDouble(),
            ));
            i += 2;
        }
      }

      curves.add(MotionCurve(
        target: target,
        id: cj['Id'] as String,
        segmentCount: segCount,
        baseSegmentIndex: baseSegmentIndex,
        fadeInTime: (cj['FadeInTime'] as num?)?.toDouble() ?? -1.0,
        fadeOutTime: (cj['FadeOutTime'] as num?)?.toDouble() ?? -1.0,
      ));
    }

    // Parse events
    final events = <MotionEvent>[];
    final userDataJson = json['UserData'] as List?;
    if (userDataJson != null) {
      for (final event in userDataJson) {
        final e = event as Map<String, dynamic>;
        events.add(MotionEvent(
          (e['Time'] as num).toDouble(),
          e['Value'] as String? ?? '',
        ));
      }
    }

    return MotionData(
      duration: duration,
      fps: fps,
      loop: loop,
      curveCount: curveCount,
      curves: curves,
      segments: segments,
      points: points,
      events: events,
    );
  }
}
