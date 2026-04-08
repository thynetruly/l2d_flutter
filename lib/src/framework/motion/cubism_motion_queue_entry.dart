/// Per-motion playback state within the motion queue.
///
/// Ported from Framework/src/Motion/CubismMotionQueueEntry.hpp.
class CubismMotionQueueEntry {
  /// Whether to auto-delete the motion when finished.
  bool autoDelete;

  /// Whether this entry is active.
  bool available = true;

  /// Whether this motion has completed.
  bool finished = false;

  /// Whether initial setup has been performed.
  bool started = false;

  /// When the motion started (seconds).
  double startTimeSeconds = -1.0;

  /// When fade-in started (seconds).
  double fadeInStartTimeSeconds = 0.0;

  /// When the motion should end (-1 for looping/indefinite).
  double endTimeSeconds = -1.0;

  /// Current playback time.
  double stateTimeSeconds = 0.0;

  /// Current fade weight.
  double stateWeight = 0.0;

  /// Last time user-data events were checked.
  double lastEventCheckSeconds = 0.0;

  /// Fade-out duration (seconds).
  double fadeOutSeconds = 0.0;

  /// Whether fade-out has been triggered.
  bool isTriggeredFadeOut = false;

  CubismMotionQueueEntry({this.autoDelete = true});

  /// Triggers a fade-out with the given [seconds] duration.
  void setFadeout(double seconds) {
    fadeOutSeconds = seconds;
    isTriggeredFadeOut = true;
  }

  /// Starts fade-out, computing the end time from [userTimeSeconds].
  void startFadeout(double seconds, double userTimeSeconds) {
    final newEndTime = userTimeSeconds + seconds;
    if (endTimeSeconds < 0.0 || newEndTime < endTimeSeconds) {
      endTimeSeconds = newEndTime;
    }
    isTriggeredFadeOut = true;
  }

  /// Sets the state for query.
  void setState(double timeSeconds, double weight) {
    stateTimeSeconds = timeSeconds;
    stateWeight = weight;
  }
}
