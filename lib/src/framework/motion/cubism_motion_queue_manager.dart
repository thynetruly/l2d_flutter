import '../../core/cubism_model.dart';
import 'cubism_motion.dart';
import 'cubism_motion_queue_entry.dart';
import '../math/cubism_math.dart';

/// Callback when a motion event fires.
typedef MotionEventCallback = void Function(String eventValue);

/// Manages a queue of playing motions with fade-in/out transitions.
///
/// Ported from Framework/src/Motion/CubismMotionQueueManager.hpp.
class CubismMotionQueueManager {
  final List<_MotionEntry> _motions = [];
  // ignore: prefer_final_fields
  double _userTimeSeconds = 0.0;
  MotionEventCallback? _eventCallback;

  /// Current user time in seconds.
  double get userTimeSeconds => _userTimeSeconds;

  /// Starts playing a motion, fading out all currently playing motions.
  ///
  /// Returns the queue entry for the new motion.
  CubismMotionQueueEntry startMotion(CubismMotion motion,
      {bool autoDelete = true}) {
    // Trigger fade-out on all current motions
    for (final entry in _motions) {
      entry.queueEntry.setFadeout(entry.motion.fadeOutSeconds > 0
          ? entry.motion.fadeOutSeconds
          : 0.0);
    }

    final queueEntry = CubismMotionQueueEntry(autoDelete: autoDelete);
    final entry = _MotionEntry(motion, queueEntry);
    _motions.add(entry);
    return queueEntry;
  }

  /// Sets the event callback.
  void setEventCallback(MotionEventCallback callback) {
    _eventCallback = callback;
  }

  /// Returns true if all motions have finished.
  bool isFinished() {
    _motions.removeWhere((e) => e.queueEntry.finished);
    return _motions.isEmpty;
  }

  /// Returns true if a specific queue entry is finished.
  bool isEntryFinished(CubismMotionQueueEntry entry) {
    for (final e in _motions) {
      if (identical(e.queueEntry, entry)) {
        return e.queueEntry.finished;
      }
    }
    return true; // Not found = finished
  }

  /// Stops all currently playing motions.
  void stopAllMotions() {
    _motions.clear();
  }

  /// Returns all current queue entries.
  List<CubismMotionQueueEntry> get entries =>
      _motions.map((e) => e.queueEntry).toList();

  /// Updates all playing motions. Called by subclass.
  bool doUpdateMotion(CubismModel model, double userTimeSeconds) {
    bool updated = false;

    final toRemove = <int>[];
    for (int i = 0; i < _motions.length; i++) {
      final entry = _motions[i];
      final motion = entry.motion;
      final qe = entry.queueEntry;

      if (!qe.available) {
        toRemove.add(i);
        continue;
      }

      // Setup on first update
      if (!qe.started) {
        qe.started = true;
        qe.startTimeSeconds = userTimeSeconds - motion.offsetTime;
        qe.fadeInStartTimeSeconds = userTimeSeconds;
        if (motion.duration > 0 && !motion.isLoop) {
          qe.endTimeSeconds = qe.startTimeSeconds + motion.duration;
        } else {
          qe.endTimeSeconds = -1.0;
        }
      }

      // Calculate fade weight
      final fadeWeight = _calculateFadeWeight(motion, qe, userTimeSeconds);

      // Calculate elapsed time
      final timeOffset = userTimeSeconds - qe.startTimeSeconds;

      // Update parameters — pass GLOBAL userTimeSeconds for fade calculations
      // (fadeInStartTime and endTime are in global time scale).
      motion.updateParameters(
        model,
        timeOffset < 0.0 ? 0.0 : timeOffset,
        fadeWeight,
        qe.fadeInStartTimeSeconds,
        qe.endTimeSeconds,
        userTimeSeconds: userTimeSeconds,
      );
      updated = true;

      // Fire events
      if (_eventCallback != null) {
        final lastCheck = qe.lastEventCheckSeconds - qe.startTimeSeconds;
        final currentCheck = userTimeSeconds - qe.startTimeSeconds;
        for (final event in motion.data.events) {
          if (event.fireTime > lastCheck && event.fireTime <= currentCheck) {
            _eventCallback!(event.value);
          }
        }
      }
      qe.lastEventCheckSeconds = userTimeSeconds;

      // Check if finished
      if (qe.endTimeSeconds > 0.0 && qe.endTimeSeconds < userTimeSeconds) {
        qe.finished = true;
        toRemove.add(i);
        continue;
      }

      // Handle triggered fade-out
      if (qe.isTriggeredFadeOut) {
        qe.startFadeout(qe.fadeOutSeconds, userTimeSeconds);
      }
    }

    // Remove finished entries in reverse order
    for (int i = toRemove.length - 1; i >= 0; i--) {
      _motions.removeAt(toRemove[i]);
    }

    return updated;
  }

  double _calculateFadeWeight(
      CubismMotion motion, CubismMotionQueueEntry qe, double userTimeSeconds) {
    double fadeWeight = motion.weight;

    final fadeIn = (motion.fadeInSeconds <= 0.0)
        ? 1.0
        : CubismMath.getEasingSine(
            (userTimeSeconds - qe.fadeInStartTimeSeconds) /
                motion.fadeInSeconds);

    final fadeOut = (motion.fadeOutSeconds <= 0.0 || qe.endTimeSeconds < 0.0)
        ? 1.0
        : CubismMath.getEasingSine(
            (qe.endTimeSeconds - userTimeSeconds) / motion.fadeOutSeconds);

    fadeWeight = fadeWeight * fadeIn * fadeOut;
    qe.setState(userTimeSeconds, fadeWeight);

    return fadeWeight.clamp(0.0, 1.0);
  }
}

class _MotionEntry {
  final CubismMotion motion;
  final CubismMotionQueueEntry queueEntry;
  _MotionEntry(this.motion, this.queueEntry);
}
