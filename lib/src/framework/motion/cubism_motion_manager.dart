import '../../core/cubism_model.dart';
import 'cubism_motion.dart';
import 'cubism_motion_queue_entry.dart';
import 'cubism_motion_queue_manager.dart';

/// Priority-based motion manager.
///
/// Ported from Framework/src/Motion/CubismMotionManager.hpp.
///
/// Manages motion playback with a priority system. Higher priority motions
/// replace lower priority ones. Uses [CubismMotionQueueManager] for the
/// underlying queue and fade logic.
class CubismMotionManager extends CubismMotionQueueManager {
  int _currentPriority = 0;
  int _reservePriority = 0;

  /// Priority of the currently playing motion.
  int get currentPriority => _currentPriority;

  /// Priority of the reserved (queued) motion.
  int get reservePriority => _reservePriority;

  /// Starts a motion with priority.
  ///
  /// If [priority] matches the reserved priority, the reservation is consumed.
  /// Returns the queue entry for the new motion.
  CubismMotionQueueEntry startMotionPriority(
    CubismMotion motion, {
    bool autoDelete = true,
    int priority = 0,
  }) {
    if (priority == _reservePriority) {
      _reservePriority = 0;
    }
    _currentPriority = priority;
    return startMotion(motion, autoDelete: autoDelete);
  }

  /// Updates all motions and returns true if any motion was updated.
  bool updateMotion(CubismModel model, double deltaTimeSeconds) {
    _userTimeSeconds += deltaTimeSeconds;
    final updated = doUpdateMotion(model, _userTimeSeconds);
    if (isFinished()) {
      _currentPriority = 0;
    }
    return updated;
  }

  /// Reserves a motion at the given [priority].
  ///
  /// Returns true if the reservation was accepted (priority is higher than
  /// both current and reserve priorities).
  bool reserveMotion(int priority) {
    if (priority <= _reservePriority || priority <= _currentPriority) {
      return false;
    }
    _reservePriority = priority;
    return true;
  }

  // Override userTimeSeconds as public for manager
  @override
  double get userTimeSeconds => _userTimeSeconds;
  double _userTimeSeconds = 0.0;
}
