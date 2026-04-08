import 'dart:convert';
import 'dart:math' as math;

import '../../core/cubism_model.dart';
import '../math/cubism_math.dart';
import '../math/cubism_vector2.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _airResistance = 5.0;
const double _maximumWeight = 100.0;
const double _movementThreshold = 0.001;
const double _maxDeltaTime = 5.0;

// ---------------------------------------------------------------------------
// Data structures
// ---------------------------------------------------------------------------

/// Normalization range for physics input/output.
class PhysicsNormalization {
  final double minimum;
  final double maximum;
  final double defaultValue;
  const PhysicsNormalization(this.minimum, this.maximum, this.defaultValue);
}

/// A single particle in a pendulum chain.
class PhysicsParticle {
  CubismVector2 initialPosition;
  double mobility;
  double delay;
  double acceleration;
  double radius;
  CubismVector2 position;
  CubismVector2 lastPosition;
  CubismVector2 lastGravity;
  CubismVector2 force;
  CubismVector2 velocity;

  PhysicsParticle({
    CubismVector2? initialPosition,
    this.mobility = 0.0,
    this.delay = 0.0,
    this.acceleration = 0.0,
    this.radius = 0.0,
  })  : initialPosition = initialPosition ?? CubismVector2(),
        position = CubismVector2(),
        lastPosition = CubismVector2(),
        lastGravity = CubismVector2(0.0, -1.0),
        force = CubismVector2(),
        velocity = CubismVector2();
}

/// Source type for physics input/output.
enum PhysicsSourceType { x, y, angle }

/// Input mapping from a model parameter to physics.
class PhysicsInput {
  final String sourceId;
  int sourceParameterIndex = -1;
  final double weight;
  final PhysicsSourceType type;
  final bool reflect;

  PhysicsInput({
    required this.sourceId,
    required this.weight,
    required this.type,
    this.reflect = false,
  });
}

/// Output mapping from physics to a model parameter.
class PhysicsOutput {
  final String destinationId;
  int destinationParameterIndex = -1;
  final int vertexIndex;
  final CubismVector2 translationScale;
  final double angleScale;
  final double weight;
  final PhysicsSourceType type;
  final bool reflect;
  double valueBelowMinimum = 0.0;
  double valueExceededMaximum = 0.0;

  PhysicsOutput({
    required this.destinationId,
    required this.vertexIndex,
    CubismVector2? translationScale,
    this.angleScale = 1.0,
    required this.weight,
    required this.type,
    this.reflect = false,
  }) : translationScale = translationScale ?? CubismVector2(1.0, 1.0);
}

/// A single pendulum group (sub-rig).
class PhysicsSubRig {
  final List<PhysicsInput> inputs;
  final List<PhysicsOutput> outputs;
  final List<PhysicsParticle> particles;
  final PhysicsNormalization normalizationPosition;
  final PhysicsNormalization normalizationAngle;

  PhysicsSubRig({
    required this.inputs,
    required this.outputs,
    required this.particles,
    required this.normalizationPosition,
    required this.normalizationAngle,
  });
}

/// Options for physics simulation.
class PhysicsOptions {
  CubismVector2 gravity;
  CubismVector2 wind;
  PhysicsOptions({CubismVector2? gravity, CubismVector2? wind})
      : gravity = gravity ?? CubismVector2(0.0, -1.0),
        wind = wind ?? CubismVector2();
}

// ---------------------------------------------------------------------------
// Main physics class
// ---------------------------------------------------------------------------

/// Pendulum-based physics simulation for hair/clothing dynamics.
///
/// Ported from Framework/src/Physics/CubismPhysics.cpp.
class CubismPhysics {
  final List<PhysicsSubRig> _subRigs;
  final double _fps;
  PhysicsOptions _options;

  // Per-output interpolation buffers
  late final List<double> _currentRigOutputs;
  late final List<double> _previousRigOutputs;

  // Per-parameter caches for sub-stepping
  List<double> _parameterCaches = [];
  List<double> _parameterInputCaches = [];

  double _currentRemainTime = 0.0;

  CubismPhysics._({
    required List<PhysicsSubRig> subRigs,
    double fps = 0.0,
    PhysicsOptions? options,
  })  : _subRigs = subRigs,
        _fps = fps,
        _options = options ?? PhysicsOptions() {
    int totalOutputs = 0;
    for (final rig in _subRigs) {
      totalOutputs += rig.outputs.length;
    }
    _currentRigOutputs = List<double>.filled(totalOutputs, 0.0);
    _previousRigOutputs = List<double>.filled(totalOutputs, 0.0);
  }

  /// Creates physics from a physics3.json file string.
  factory CubismPhysics.fromString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return _parsePhysicsJson(json);
  }

  /// Creates physics from physics3.json raw bytes.
  factory CubismPhysics.fromBytes(List<int> bytes) {
    return CubismPhysics.fromString(utf8.decode(bytes));
  }

  PhysicsOptions get options => _options;

  /// Resets all particles to their initial positions.
  void reset() {
    for (final rig in _subRigs) {
      _initializeParticles(rig.particles);
    }
    _currentRemainTime = 0.0;
  }

  /// Runs stabilization (steady-state convergence with no velocity).
  void stabilization(CubismModel model) {
    _ensureParameterCaches(model);

    for (int i = 0; i < model.parameterCount; i++) {
      _parameterCaches[i] = model.parameters[i].value;
      _parameterInputCaches[i] = _parameterCaches[i];
    }

    int outputIdx = 0;
    for (final rig in _subRigs) {
      final totalTranslation = CubismVector2();
      double totalAngle = 0.0;

      _processInputs(rig, model, _parameterCaches, totalTranslation, (a) => totalAngle = a, totalAngle);
      _applyRotation(totalTranslation, totalAngle);

      _updateParticlesForStabilization(
        rig.particles,
        totalTranslation,
        totalAngle,
        _options.wind,
        _movementThreshold * rig.normalizationPosition.maximum,
      );

      for (final output in rig.outputs) {
        _currentRigOutputs[outputIdx] = _calculateOutputValue(rig, output);
        _previousRigOutputs[outputIdx] = _currentRigOutputs[outputIdx];
        outputIdx++;
      }
    }
  }

  /// Main physics evaluation step.
  void evaluate(CubismModel model, double deltaTimeSeconds) {
    _ensureParameterCaches(model);
    _currentRemainTime += deltaTimeSeconds;

    if (_currentRemainTime > _maxDeltaTime) {
      _currentRemainTime = 0.0;
    }

    final physicsDeltaTime = (_fps > 0.0) ? (1.0 / _fps) : deltaTimeSeconds;
    if (physicsDeltaTime <= 0.0) return;

    // Sub-stepping loop
    while (_currentRemainTime >= physicsDeltaTime) {
      // Save previous outputs
      for (int i = 0; i < _currentRigOutputs.length; i++) {
        _previousRigOutputs[i] = _currentRigOutputs[i];
      }

      // Input interpolation
      final inputWeight = physicsDeltaTime / _currentRemainTime;
      for (int j = 0; j < model.parameterCount; j++) {
        _parameterCaches[j] = _parameterInputCaches[j] * (1.0 - inputWeight) +
            model.parameters[j].value * inputWeight;
        _parameterInputCaches[j] = _parameterCaches[j];
      }

      int outputIdx = 0;
      for (final rig in _subRigs) {
        final totalTranslation = CubismVector2();
        double totalAngle = 0.0;

        _processInputs(rig, model, _parameterCaches, totalTranslation, (a) => totalAngle = a, totalAngle);
        _applyRotation(totalTranslation, totalAngle);

        _updateParticles(
          rig.particles,
          totalTranslation,
          totalAngle,
          _options.wind,
          _movementThreshold * rig.normalizationPosition.maximum,
          physicsDeltaTime,
          _airResistance,
        );

        for (final output in rig.outputs) {
          _currentRigOutputs[outputIdx] = _calculateOutputValue(rig, output);
          _updateOutputParameterValue(model, output, _currentRigOutputs[outputIdx]);
          outputIdx++;
        }
      }

      _currentRemainTime -= physicsDeltaTime;
    }

    // Interpolate to render time
    final alpha = (_currentRemainTime / physicsDeltaTime).clamp(0.0, 1.0);
    _interpolate(model, alpha);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _ensureParameterCaches(CubismModel model) {
    if (_parameterCaches.length != model.parameterCount) {
      _parameterCaches = List<double>.filled(model.parameterCount, 0.0);
      _parameterInputCaches = List<double>.filled(model.parameterCount, 0.0);
      for (int i = 0; i < model.parameterCount; i++) {
        _parameterCaches[i] = model.parameters[i].value;
        _parameterInputCaches[i] = _parameterCaches[i];
      }
    }
  }

  void _processInputs(
    PhysicsSubRig rig,
    CubismModel model,
    List<double> parameterCaches,
    CubismVector2 totalTranslation,
    void Function(double) setAngle,
    double currentAngle,
  ) {
    double totalAngle = currentAngle;
    for (final input in rig.inputs) {
      if (input.sourceParameterIndex < 0) {
        input.sourceParameterIndex = _findParameterIndex(model, input.sourceId);
      }
      if (input.sourceParameterIndex < 0) continue;

      final param = model.parameters[input.sourceParameterIndex];
      final value = parameterCaches[input.sourceParameterIndex];
      final weight = input.weight / _maximumWeight;

      switch (input.type) {
        case PhysicsSourceType.x:
          totalTranslation.x += _normalizeParameterValue(
            value, param.minimumValue, param.maximumValue, param.defaultValue,
            rig.normalizationPosition.minimum, rig.normalizationPosition.maximum,
            rig.normalizationPosition.defaultValue, input.reflect,
          ) * weight;
        case PhysicsSourceType.y:
          totalTranslation.y += _normalizeParameterValue(
            value, param.minimumValue, param.maximumValue, param.defaultValue,
            rig.normalizationPosition.minimum, rig.normalizationPosition.maximum,
            rig.normalizationPosition.defaultValue, input.reflect,
          ) * weight;
        case PhysicsSourceType.angle:
          totalAngle += _normalizeParameterValue(
            value, param.minimumValue, param.maximumValue, param.defaultValue,
            rig.normalizationAngle.minimum, rig.normalizationAngle.maximum,
            rig.normalizationAngle.defaultValue, input.reflect,
          ) * weight;
      }
    }
    setAngle(totalAngle);
  }

  static void _applyRotation(CubismVector2 translation, double angle) {
    final rad = CubismMath.degreesToRadian(-angle);
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final x = translation.x * cosA - translation.y * sinA;
    final y = translation.x * sinA + translation.y * cosA;
    translation.x = x;
    translation.y = y;
  }

  double _calculateOutputValue(PhysicsSubRig rig, PhysicsOutput output) {
    final vi = output.vertexIndex;
    if (vi < 1 || vi >= rig.particles.length) return 0.0;

    final translation = rig.particles[vi].position - rig.particles[vi - 1].position;
    final inv = output.reflect ? -1.0 : 1.0;

    switch (output.type) {
      case PhysicsSourceType.x:
        return translation.x * inv;
      case PhysicsSourceType.y:
        return translation.y * inv;
      case PhysicsSourceType.angle:
        CubismVector2 parentGravity;
        if (vi >= 2) {
          parentGravity = rig.particles[vi - 1].position - rig.particles[vi - 2].position;
        } else {
          parentGravity = _options.gravity * -1.0;
        }
        return CubismMath.directionToRadian(parentGravity, translation) * inv;
    }
  }

  void _updateOutputParameterValue(CubismModel model, PhysicsOutput output, double translationValue) {
    if (output.destinationParameterIndex < 0) {
      output.destinationParameterIndex = _findParameterIndex(model, output.destinationId);
    }
    if (output.destinationParameterIndex < 0) return;

    final param = model.parameters[output.destinationParameterIndex];
    double outputScale;
    switch (output.type) {
      case PhysicsSourceType.x:
        outputScale = output.translationScale.x;
      case PhysicsSourceType.y:
        outputScale = output.translationScale.y;
      case PhysicsSourceType.angle:
        outputScale = output.angleScale;
    }

    var value = translationValue * outputScale;
    value = value.clamp(param.minimumValue, param.maximumValue);

    final weight = output.weight / _maximumWeight;
    if (weight >= 1.0) {
      _parameterCaches[output.destinationParameterIndex] = value;
    } else {
      _parameterCaches[output.destinationParameterIndex] =
          _parameterCaches[output.destinationParameterIndex] * (1.0 - weight) + value * weight;
    }
  }

  void _interpolate(CubismModel model, double weight) {
    int outputIdx = 0;
    for (final rig in _subRigs) {
      for (final output in rig.outputs) {
        if (output.destinationParameterIndex < 0) {
          output.destinationParameterIndex = _findParameterIndex(model, output.destinationId);
        }
        if (output.destinationParameterIndex < 0) {
          outputIdx++;
          continue;
        }

        final interpolated = _previousRigOutputs[outputIdx] * (1.0 - weight) +
            _currentRigOutputs[outputIdx] * weight;

        final param = model.parameters[output.destinationParameterIndex];
        double outputScale;
        switch (output.type) {
          case PhysicsSourceType.x:
            outputScale = output.translationScale.x;
          case PhysicsSourceType.y:
            outputScale = output.translationScale.y;
          case PhysicsSourceType.angle:
            outputScale = output.angleScale;
        }

        var value = interpolated * outputScale;
        value = value.clamp(param.minimumValue, param.maximumValue);

        final w = output.weight / _maximumWeight;
        if (w >= 1.0) {
          param.value = value;
        } else {
          param.value = param.value * (1.0 - w) + value * w;
        }

        outputIdx++;
      }
    }
  }

  int _findParameterIndex(CubismModel model, String id) {
    for (int i = 0; i < model.parameterCount; i++) {
      if (model.parameters[i].id == id) return i;
    }
    return -1;
  }

  // ---------------------------------------------------------------------------
  // Particle simulation
  // ---------------------------------------------------------------------------

  static void _updateParticles(
    List<PhysicsParticle> strand,
    CubismVector2 totalTranslation,
    double totalAngle,
    CubismVector2 windDirection,
    double thresholdValue,
    double deltaTimeSeconds,
    double airResistance,
  ) {
    strand[0].position = totalTranslation.copy();

    final totalRadian = CubismMath.degreesToRadian(totalAngle);
    final currentGravity = CubismMath.radianToDirection(totalRadian);
    currentGravity.normalize();

    for (int i = 1; i < strand.length; i++) {
      strand[i].force = currentGravity * strand[i].acceleration + windDirection;
      strand[i].lastPosition = strand[i].position.copy();

      final delay = strand[i].delay * deltaTimeSeconds * 30.0;

      var direction = strand[i].position - strand[i - 1].position;

      // Gravity rotation with air resistance damping
      final radian = CubismMath.directionToRadian(strand[i].lastGravity, currentGravity) / airResistance;
      final cosR = math.cos(radian);
      final sinR = math.sin(radian);
      final dx = cosR * direction.x - sinR * direction.y;
      final dy = sinR * direction.x + cosR * direction.y;
      direction = CubismVector2(dx, dy);

      strand[i].position = strand[i - 1].position + direction;

      // Apply velocity and force
      final velocity = strand[i].velocity * delay;
      final force = strand[i].force * (delay * delay);
      strand[i].position = strand[i].position + velocity + force;

      // Constraint: maintain radius from parent
      var newDirection = strand[i].position - strand[i - 1].position;
      newDirection.normalize();
      strand[i].position = strand[i - 1].position + newDirection * strand[i].radius;

      // Threshold clipping
      if (strand[i].position.x.abs() < thresholdValue) {
        strand[i].position.x = 0.0;
      }

      // Update velocity for next frame
      if (delay != 0.0) {
        strand[i].velocity = (strand[i].position - strand[i].lastPosition) / delay;
        strand[i].velocity = strand[i].velocity * strand[i].mobility;
      }

      strand[i].force = CubismVector2();
      strand[i].lastGravity = currentGravity.copy();
    }
  }

  static void _updateParticlesForStabilization(
    List<PhysicsParticle> strand,
    CubismVector2 totalTranslation,
    double totalAngle,
    CubismVector2 windDirection,
    double thresholdValue,
  ) {
    strand[0].position = totalTranslation.copy();

    final totalRadian = CubismMath.degreesToRadian(totalAngle);
    final currentGravity = CubismMath.radianToDirection(totalRadian);
    currentGravity.normalize();

    for (int i = 1; i < strand.length; i++) {
      strand[i].force = currentGravity * strand[i].acceleration + windDirection;
      strand[i].lastPosition = strand[i].position.copy();

      // Steady state: normalize force and apply at radius
      strand[i].velocity = CubismVector2();

      var forceDir = strand[i].force.copy();
      forceDir.normalize();
      forceDir = forceDir * strand[i].radius;
      strand[i].position = strand[i - 1].position + forceDir;

      if (strand[i].position.x.abs() < thresholdValue) {
        strand[i].position.x = 0.0;
      }

      strand[i].force = CubismVector2();
      strand[i].lastGravity = currentGravity.copy();
    }
  }

  static void _initializeParticles(List<PhysicsParticle> particles) {
    if (particles.isEmpty) return;

    particles[0].initialPosition = CubismVector2();
    particles[0].lastGravity = CubismVector2(0.0, -1.0);
    particles[0].velocity = CubismVector2();
    particles[0].force = CubismVector2();
    particles[0].position = particles[0].initialPosition.copy();

    for (int i = 1; i < particles.length; i++) {
      final radius = CubismVector2(0.0, particles[i].radius);
      particles[i].initialPosition = particles[i - 1].initialPosition + radius;
      particles[i].position = particles[i].initialPosition.copy();
      particles[i].lastPosition = particles[i].position.copy();
      particles[i].lastGravity = CubismVector2(0.0, -1.0);
      particles[i].velocity = CubismVector2();
      particles[i].force = CubismVector2();
    }
  }

  // ---------------------------------------------------------------------------
  // Input normalization
  // ---------------------------------------------------------------------------

  static double _normalizeParameterValue(
    double value,
    double paramMin,
    double paramMax,
    double paramDefault,
    double normMin,
    double normMax,
    double normDefault,
    bool isInverted,
  ) {
    var result = 0.0;
    final clampedValue = value.clamp(paramMin, paramMax);

    final paramMid = (paramMin + paramMax) / 2.0;
    final normMid = (normMin + normMax) / 2.0;
    final paramDelta = clampedValue - paramMid;

    if (paramDelta > 0.0) {
      final paramRange = paramMax - paramMid;
      if (paramRange != 0.0) {
        result = normMid + (normMax - normMid) * paramDelta / paramRange;
      }
    } else if (paramDelta < 0.0) {
      final paramRange = paramMid - paramMin;
      if (paramRange != 0.0) {
        result = normMid + (normMid - normMin) * paramDelta / paramRange;
      }
    } else {
      result = normMid;
    }

    return isInverted ? -result : result;
  }

  // ---------------------------------------------------------------------------
  // JSON parsing
  // ---------------------------------------------------------------------------

  static CubismPhysics _parsePhysicsJson(Map<String, dynamic> json) {
    final meta = json['Meta'] as Map<String, dynamic>? ?? {};
    final physicsSettings = json['PhysicsSettings'] as List? ?? [];

    final effectiveForces = meta['EffectiveForces'] as Map<String, dynamic>?;
    final gravityJson = effectiveForces?['Gravity'] as Map<String, dynamic>?;
    final windJson = effectiveForces?['Wind'] as Map<String, dynamic>?;
    final fps = (meta['Fps'] as num?)?.toDouble() ?? 0.0;

    final subRigs = <PhysicsSubRig>[];

    for (final setting in physicsSettings) {
      final s = setting as Map<String, dynamic>;
      final norm = s['Normalization'] as Map<String, dynamic>? ?? {};
      final posNorm = norm['Position'] as Map<String, dynamic>? ?? {};
      final angNorm = norm['Angle'] as Map<String, dynamic>? ?? {};

      final inputs = <PhysicsInput>[];
      for (final inp in (s['Input'] as List? ?? [])) {
        final m = inp as Map<String, dynamic>;
        inputs.add(PhysicsInput(
          sourceId: (m['Source'] as Map<String, dynamic>)['Id'] as String,
          weight: (m['Weight'] as num).toDouble(),
          type: _parseSourceType(m['Type'] as String),
          reflect: m['Reflect'] as bool? ?? false,
        ));
      }

      final outputs = <PhysicsOutput>[];
      for (final out_ in (s['Output'] as List? ?? [])) {
        final m = out_ as Map<String, dynamic>;
        final type = _parseSourceType(m['Type'] as String);
        final scale = (m['Scale'] as num?)?.toDouble() ?? 1.0;
        outputs.add(PhysicsOutput(
          destinationId: (m['Destination'] as Map<String, dynamic>)['Id'] as String,
          vertexIndex: (m['VertexIndex'] as num).toInt(),
          translationScale: CubismVector2(scale, scale),
          angleScale: scale,
          weight: (m['Weight'] as num).toDouble(),
          type: type,
          reflect: m['Reflect'] as bool? ?? false,
        ));
      }

      final particles = <PhysicsParticle>[];
      for (final vert in (s['Vertices'] as List? ?? [])) {
        final m = vert as Map<String, dynamic>;
        final pos = m['Position'] as Map<String, dynamic>;
        particles.add(PhysicsParticle(
          initialPosition: CubismVector2(
            (pos['X'] as num).toDouble(),
            (pos['Y'] as num).toDouble(),
          ),
          mobility: (m['Mobility'] as num).toDouble(),
          delay: (m['Delay'] as num).toDouble(),
          acceleration: (m['Acceleration'] as num).toDouble(),
          radius: (m['Radius'] as num).toDouble(),
        ));
      }

      subRigs.add(PhysicsSubRig(
        inputs: inputs,
        outputs: outputs,
        particles: particles,
        normalizationPosition: PhysicsNormalization(
          (posNorm['Minimum'] as num?)?.toDouble() ?? -10.0,
          (posNorm['Maximum'] as num?)?.toDouble() ?? 10.0,
          (posNorm['Default'] as num?)?.toDouble() ?? 0.0,
        ),
        normalizationAngle: PhysicsNormalization(
          (angNorm['Minimum'] as num?)?.toDouble() ?? -10.0,
          (angNorm['Maximum'] as num?)?.toDouble() ?? 10.0,
          (angNorm['Default'] as num?)?.toDouble() ?? 0.0,
        ),
      ));
    }

    final physics = CubismPhysics._(
      subRigs: subRigs,
      fps: fps,
      options: PhysicsOptions(
        gravity: gravityJson != null
            ? CubismVector2(
                (gravityJson['X'] as num).toDouble(),
                (gravityJson['Y'] as num).toDouble())
            : CubismVector2(0.0, -1.0),
        wind: windJson != null
            ? CubismVector2(
                (windJson['X'] as num).toDouble(),
                (windJson['Y'] as num).toDouble())
            : CubismVector2(),
      ),
    );

    // Initialize particle chains
    for (final rig in physics._subRigs) {
      _initializeParticles(rig.particles);
    }

    return physics;
  }

  static PhysicsSourceType _parseSourceType(String type) {
    switch (type) {
      case 'X':
        return PhysicsSourceType.x;
      case 'Y':
        return PhysicsSourceType.y;
      case 'Angle':
        return PhysicsSourceType.angle;
      default:
        return PhysicsSourceType.x;
    }
  }
}
