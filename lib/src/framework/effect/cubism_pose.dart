import 'dart:convert';
import 'dart:math' as math;

import '../../core/cubism_model.dart';

/// Data for a single part in a pose group.
class _PartData {
  final String partId;
  int parameterIndex = -1;
  int partIndex = -1;
  final List<_PartData> link;

  _PartData({
    required this.partId,
    List<_PartData>? link,
  }) : link = link ?? [];

  /// Resolves parameter and part indices from the model.
  void initialize(CubismModel model) {
    parameterIndex = -1;
    partIndex = -1;

    for (int i = 0; i < model.parameterCount; i++) {
      if (model.parameters[i].id == partId) {
        parameterIndex = i;
        break;
      }
    }
    for (int i = 0; i < model.partCount; i++) {
      if (model.parts[i].id == partId) {
        partIndex = i;
        break;
      }
    }
  }
}

/// Part visibility toggling with crossfade transitions.
///
/// Ported from Framework/src/Effect/CubismPose.hpp.
///
/// Manages mutually exclusive part groups (e.g., different outfit pieces)
/// with smooth opacity transitions. Only one part per group is visible at
/// a time; background parts fade based on a piecewise-linear curve.
class CubismPose {
  static const double _epsilon = 0.001;
  static const double _defaultFadeInSeconds = 0.5;
  static const double _phi = 0.5;
  static const double _backOpacityThreshold = 0.15;

  final List<_PartData> _partGroups = [];
  final List<int> _partGroupCounts = [];
  double _fadeTimeSeconds;
  CubismModel? _lastModel;

  CubismPose._({double fadeTimeSeconds = _defaultFadeInSeconds})
      : _fadeTimeSeconds = fadeTimeSeconds;

  /// Creates a [CubismPose] from a pose3.json file's raw bytes.
  factory CubismPose.fromBytes(List<int> bytes) {
    return CubismPose.fromString(utf8.decode(bytes));
  }

  /// Creates a [CubismPose] from a pose3.json string.
  factory CubismPose.fromString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    final fadeTime = (json['FadeInTime'] as num?)?.toDouble() ?? _defaultFadeInSeconds;
    final pose = CubismPose._(fadeTimeSeconds: fadeTime);

    final groups = json['Groups'] as List?;
    if (groups != null) {
      for (final group in groups) {
        final groupList = group as List;
        final count = groupList.length;
        pose._partGroupCounts.add(count);

        for (final partJson in groupList) {
          final partMap = partJson as Map<String, dynamic>;
          final partId = partMap['Id'] as String;

          final linkList = partMap['Link'] as List?;
          final links = <_PartData>[];
          if (linkList != null) {
            for (final linkId in linkList) {
              links.add(_PartData(partId: linkId as String));
            }
          }

          pose._partGroups.add(_PartData(partId: partId, link: links));
        }
      }
    }

    return pose;
  }

  /// Fade duration in seconds.
  double get fadeTimeSeconds => _fadeTimeSeconds;

  /// Resets all parts to their initial visibility.
  ///
  /// First part in each group is visible (1.0), rest are hidden (0.0).
  void reset(CubismModel model) {
    int beginIndex = 0;
    for (final groupCount in _partGroupCounts) {
      for (int j = beginIndex; j < beginIndex + groupCount; j++) {
        final part = _partGroups[j];
        part.initialize(model);

        final isFirst = (j == beginIndex);
        if (part.partIndex >= 0) {
          model.parts[part.partIndex].opacity = isFirst ? 1.0 : 0.0;
        }
        if (part.parameterIndex >= 0) {
          model.parameters[part.parameterIndex].value = isFirst ? 1.0 : 0.0;
        }

        for (final linked in part.link) {
          linked.initialize(model);
        }
      }
      beginIndex += groupCount;
    }
  }

  /// Updates part visibilities with crossfade transitions.
  void updateParameters(CubismModel model, double deltaTimeSeconds) {
    if (!identical(model, _lastModel)) {
      reset(model);
    }
    _lastModel = model;

    if (deltaTimeSeconds < 0.0) deltaTimeSeconds = 0.0;

    int beginIndex = 0;
    for (final groupCount in _partGroupCounts) {
      _doFade(model, deltaTimeSeconds, beginIndex, groupCount);
      beginIndex += groupCount;
    }

    _copyPartOpacities(model);
  }

  void _doFade(
      CubismModel model, double deltaTimeSeconds, int beginIndex, int count) {
    int visiblePartIndex = -1;
    double newOpacity = 1.0;

    // Find the currently visible part (parameter value > epsilon)
    for (int i = beginIndex; i < beginIndex + count; i++) {
      final part = _partGroups[i];
      if (part.parameterIndex < 0) continue;

      if (model.parameters[part.parameterIndex].value > _epsilon) {
        visiblePartIndex = i;
        if (_fadeTimeSeconds == 0.0) {
          newOpacity = 1.0;
        } else {
          newOpacity = (part.partIndex >= 0)
              ? model.parts[part.partIndex].opacity
              : 1.0;
          newOpacity += deltaTimeSeconds / _fadeTimeSeconds;
          if (newOpacity > 1.0) newOpacity = 1.0;
        }
        break;
      }
    }

    if (visiblePartIndex < 0) {
      visiblePartIndex = beginIndex;
      newOpacity = 1.0;
    }

    // Apply opacities
    for (int i = beginIndex; i < beginIndex + count; i++) {
      final part = _partGroups[i];

      if (i == visiblePartIndex) {
        // Visible part
        if (part.partIndex >= 0) {
          model.parts[part.partIndex].opacity = newOpacity;
        }
      } else {
        // Hidden part: use piecewise-linear curve for background opacity
        double a1;
        if (newOpacity < _phi) {
          a1 = newOpacity * (_phi - 1.0) / _phi + 1.0;
        } else {
          a1 = (1.0 - newOpacity) * _phi / (1.0 - _phi);
        }

        final backOpacity = (1.0 - a1) * (1.0 - newOpacity);
        if (backOpacity > _backOpacityThreshold) {
          a1 = 1.0 - _backOpacityThreshold / (1.0 - newOpacity);
        }

        if (part.partIndex >= 0) {
          final currentOpacity = model.parts[part.partIndex].opacity;
          model.parts[part.partIndex].opacity = math.min(currentOpacity, a1);
        }
      }
    }
  }

  void _copyPartOpacities(CubismModel model) {
    for (final part in _partGroups) {
      if (part.link.isEmpty || part.partIndex < 0) continue;

      final opacity = model.parts[part.partIndex].opacity;
      for (final linked in part.link) {
        if (linked.partIndex >= 0) {
          model.parts[linked.partIndex].opacity = opacity;
        }
      }
    }
  }
}
