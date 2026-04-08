import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'live2d_controller.dart';

/// A Flutter widget that renders a Live2D Cubism model.
///
/// This widget uses a [CustomPainter] to render the model's drawable meshes
/// at each frame, driven by a [Live2DController] that manages the animation
/// pipeline (motion, physics, effects).
///
/// Usage:
/// ```dart
/// final controller = Live2DController();
/// controller.loadFromBytes(mocBytes: ..., settingsJson: ...);
///
/// Live2DWidget(controller: controller)
/// ```
class Live2DWidget extends StatefulWidget {
  /// The controller managing the Live2D model.
  final Live2DController controller;

  /// Whether to automatically update the model each frame.
  /// Defaults to true.
  final bool autoUpdate;

  /// Background color behind the model. Defaults to transparent.
  final Color? backgroundColor;

  const Live2DWidget({
    super.key,
    required this.controller,
    this.autoUpdate = true,
    this.backgroundColor,
  });

  @override
  State<Live2DWidget> createState() => _Live2DWidgetState();
}

class _Live2DWidgetState extends State<Live2DWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.autoUpdate) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(Live2DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoUpdate && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.autoUpdate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final deltaTime = _lastTime == Duration.zero
        ? 1.0 / 60.0
        : (elapsed - _lastTime).inMicroseconds / 1000000.0;
    _lastTime = elapsed;

    widget.controller.update(deltaTime.clamp(0.0, 1.0 / 30.0));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _Live2DPainter(
        controller: widget.controller,
        backgroundColor: widget.backgroundColor,
      ),
      size: Size.infinite,
    );
  }
}

class _Live2DPainter extends CustomPainter {
  final Live2DController controller;
  final Color? backgroundColor;

  _Live2DPainter({required this.controller, this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    if (backgroundColor != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = backgroundColor!,
      );
    }

    // Draw the model
    final renderer = controller.renderer;
    if (renderer != null && controller.isInitialized) {
      renderer.drawModel(canvas, size);
    }
  }

  @override
  bool shouldRepaint(_Live2DPainter oldDelegate) => true;
}
