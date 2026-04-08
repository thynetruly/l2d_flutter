import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/cubism_moc.dart';
import '../core/cubism_model.dart';
import '../framework/cubism_model_setting_json.dart';
import '../framework/effect/cubism_breath.dart';
import '../framework/effect/cubism_eye_blink.dart';
import '../framework/math/cubism_matrix44.dart';
import '../framework/math/cubism_model_matrix.dart';
import '../framework/motion/cubism_motion.dart';
import '../framework/motion/cubism_motion_manager.dart';
import '../framework/physics/cubism_physics.dart';
import '../framework/rendering/cubism_renderer.dart';

/// Controller for a Live2D model that manages the full update pipeline:
/// model loading, motion playback, physics, effects, and rendering.
class Live2DController {
  CubismMoc? _moc;
  CubismModel? _model;
  CubismModelSettingJson? _settings;
  CubismPhysics? _physics;
  CubismMotionManager? _motionManager;
  CubismEyeBlink? _eyeBlink;
  CubismBreath? _breath;
  CubismRenderer? _renderer;
  CubismModelMatrix? _modelMatrix;

  final List<ui.Image> _textures = [];
  bool _initialized = false;

  /// Whether the controller has been initialized with a model.
  bool get isInitialized => _initialized;

  /// The underlying model, or null if not initialized.
  CubismModel? get model => _model;

  /// The renderer, or null if not initialized.
  CubismRenderer? get renderer => _renderer;

  /// The model matrix for positioning/scaling.
  CubismModelMatrix? get modelMatrix => _modelMatrix;

  /// The motion manager for playing animations.
  CubismMotionManager? get motionManager => _motionManager;

  /// Loads a model from raw bytes.
  ///
  /// [mocBytes] is the .moc3 file contents.
  /// [settingsJson] is the model3.json file contents.
  void loadFromBytes({
    required Uint8List mocBytes,
    required String settingsJson,
  }) {
    dispose();

    _settings = CubismModelSettingJson.fromString(settingsJson);
    _moc = CubismMoc.fromBytes(mocBytes);
    _model = CubismModel.fromMoc(_moc!);

    // Initialize model matrix from canvas info
    final canvas = _model!.canvas;
    _modelMatrix = CubismModelMatrix(canvas.width, canvas.height);

    // Initialize physics if available
    _motionManager = CubismMotionManager();

    // Initialize eye blink
    final eyeBlinkIds = _settings!.eyeBlinkParameterIds;
    if (eyeBlinkIds.isNotEmpty) {
      _eyeBlink = CubismEyeBlink(parameterIds: eyeBlinkIds);
    }

    // Initialize breath
    _breath = CubismBreath(parameters: [
      BreathParameterData(
        parameterId: 'ParamAngleX',
        offset: 0.0,
        peak: 15.0,
        cycle: 6.5345,
        weight: 0.5,
      ),
      BreathParameterData(
        parameterId: 'ParamAngleY',
        offset: 0.0,
        peak: 8.0,
        cycle: 3.5345,
        weight: 0.5,
      ),
      BreathParameterData(
        parameterId: 'ParamAngleZ',
        offset: 0.0,
        peak: 10.0,
        cycle: 5.5345,
        weight: 0.5,
      ),
      BreathParameterData(
        parameterId: 'ParamBodyAngleX',
        offset: 0.0,
        peak: 4.0,
        cycle: 15.5345,
        weight: 0.5,
      ),
      BreathParameterData(
        parameterId: 'ParamBreath',
        offset: 0.5,
        peak: 0.5,
        cycle: 3.2345,
        weight: 0.5,
      ),
    ]);

    // Initialize renderer
    _renderer = CubismRenderer();
    _renderer!.initialize(_model!);

    _initialized = true;
  }

  /// Loads physics from physics3.json data.
  void loadPhysics(String physicsJson) {
    _physics = CubismPhysics.fromString(physicsJson);
    if (_model != null) {
      _physics!.stabilization(_model!);
    }
  }

  /// Sets a texture for the renderer.
  void setTexture(int index, ui.Image texture) {
    while (_textures.length <= index) {
      _textures.add(texture);
    }
    _textures[index] = texture;
    _renderer?.setTexture(index, texture);
  }

  /// Starts playing a motion.
  CubismMotion? startMotion(String motionJson, {int priority = 1}) {
    if (_motionManager == null) return null;
    final motion = CubismMotion.fromString(motionJson);
    _motionManager!.startMotionPriority(motion, priority: priority);
    return motion;
  }

  /// Updates the model for the current frame.
  ///
  /// [deltaTimeSeconds] is the time since the last update.
  void update(double deltaTimeSeconds) {
    if (!_initialized || _model == null) return;
    final model = _model!;

    // Update motion
    _motionManager?.updateMotion(model, deltaTimeSeconds);

    // Update eye blink
    _eyeBlink?.updateParameters(model, deltaTimeSeconds);

    // Update breath
    _breath?.updateParameters(model, deltaTimeSeconds);

    // Update physics
    _physics?.evaluate(model, deltaTimeSeconds);

    // Update model (propagate parameter changes to drawables)
    model.update();
  }

  /// Sets the MVP matrix on the renderer.
  void setMvpMatrix(CubismMatrix44 matrix) {
    _renderer?.mvpMatrix = matrix;
  }

  /// Releases all resources.
  void dispose() {
    _model?.dispose();
    _moc?.dispose();
    _model = null;
    _moc = null;
    _settings = null;
    _physics = null;
    _motionManager = null;
    _eyeBlink = null;
    _breath = null;
    _renderer = null;
    _modelMatrix = null;
    _textures.clear();
    _initialized = false;
  }
}
