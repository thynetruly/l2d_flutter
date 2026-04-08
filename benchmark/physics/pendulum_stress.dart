// Pendulum stress benchmark — synthetic scaling curve beyond Haru's 8 particles.
//
// Generates a synthetic physics3.json in memory (no committed fixture file —
// see note below) with N sub-rigs × M particles. Runs the same 300-frame
// simulation as `pendulum.dart` but over a model large enough that any
// per-particle cost dominates FFI overhead.
//
// Why in-memory generation? The plan initially called for a committed
// fixture at `benchmark/physics/fixtures/stress_rig.physics3.json`, but
// generating the file in code keeps the benchmark self-contained and lets
// us scale N and M by variant without juggling multiple files. The
// generator is deterministic so runs are reproducible.
//
// The model used is still Haru — we only need a valid CubismModel for the
// physics evaluator to write output parameters into; Haru's parameter set
// includes the hair/body angle parameters that the synthetic inputs target.

import 'dart:convert';

import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';

import '../fixtures.dart';
import '../harness.dart';

/// Generates a physics3.json with [subRigCount] independent pendulum chains
/// of [particlesPerRig] particles each. Each chain outputs to a distinct
/// Haru hair parameter — if we run out of Haru parameters we round-robin,
/// which is fine because the physics evaluator only cares that the target
/// exists, not that every write is unique.
String generateStressRig({
  required int subRigCount,
  required int particlesPerRig,
}) {
  // Haru parameters known to exist — we round-robin for output targets.
  const outputParams = [
    'ParamHairFront',
    'ParamHairSide',
    'ParamHairBack',
    'ParamAngleX',
    'ParamAngleY',
    'ParamAngleZ',
  ];

  final settings = <Map<String, Object?>>[];
  for (int r = 0; r < subRigCount; r++) {
    final vertices = <Map<String, Object?>>[];
    for (int p = 0; p < particlesPerRig; p++) {
      vertices.add({
        'Position': {'X': 0, 'Y': p * 8},
        'Mobility': p == 0 ? 1.0 : 0.95,
        'Delay': p == 0 ? 1.0 : 0.8,
        'Acceleration': 1.0,
        'Radius': p == 0 ? 0.0 : 8.0,
      });
    }

    settings.add({
      'Id': 'StressSetting$r',
      'Input': const [
        {
          'Source': {'Target': 'Parameter', 'Id': 'ParamAngleX'},
          'Weight': 60.0,
          'Type': 'X',
          'Reflect': false,
        },
        {
          'Source': {'Target': 'Parameter', 'Id': 'ParamAngleZ'},
          'Weight': 60.0,
          'Type': 'Angle',
          'Reflect': false,
        },
        {
          'Source': {'Target': 'Parameter', 'Id': 'ParamBodyAngleX'},
          'Weight': 40.0,
          'Type': 'X',
          'Reflect': false,
        },
      ],
      'Output': [
        {
          'Destination': {
            'Target': 'Parameter',
            'Id': outputParams[r % outputParams.length],
          },
          'VertexIndex': 1,
          'Scale': 1.5,
          'Weight': 100.0,
          'Type': 'Angle',
          'Reflect': false,
        },
      ],
      'Vertices': vertices,
      'Normalization': {
        'Position': {'Minimum': -10.0, 'Default': 0.0, 'Maximum': 10.0},
        'Angle': {'Minimum': -10.0, 'Default': 0.0, 'Maximum': 10.0},
      },
    });
  }

  final doc = {
    'Version': 3,
    'Meta': {
      'PhysicsSettingCount': subRigCount,
      'TotalInputCount': subRigCount * 3,
      'TotalOutputCount': subRigCount,
      'VertexCount': subRigCount * particlesPerRig,
      'EffectiveForces': {
        'Gravity': {'X': 0, 'Y': -1},
        'Wind': {'X': 0, 'Y': 0},
      },
      'PhysicsDictionary': [
        for (int i = 0; i < subRigCount; i++)
          {'Id': 'StressSetting$i', 'Name': 'stress_rig_$i'},
      ],
    },
    'PhysicsSettings': settings,
  };

  return jsonEncode(doc);
}

class _PendulumStressBench extends CubismBenchmark {
  _PendulumStressBench({
    required int subRigs,
    required int particles,
  })  : _subRigs = subRigs,
        _particles = particles,
        super(
          module: 'physics',
          benchName: 'pendulumStress',
          variant: '${subRigs}rigs_${particles}particles',
          innerIterations: 1,
          sampleCount: 20,
          warmupMs: 100,
        );

  final int _subRigs;
  final int _particles;

  static const int _frames = 300;
  static const double _dt = 1.0 / 60.0;

  late CubismModel _model;
  late CubismPhysics _physics;

  @override
  void setup() {
    _model = Fixtures.haru().newModel();
    final json = generateStressRig(
      subRigCount: _subRigs,
      particlesPerRig: _particles,
    );
    _physics = CubismPhysics.fromString(json);
    _physics.stabilization(_model);
  }

  @override
  void run() {
    for (int f = 0; f < _frames; f++) {
      _physics.evaluate(_model, _dt);
    }
  }

  @override
  void teardown() {
    _model.dispose();
  }

  @override
  Map<String, Object?> get metadata => {
        'frames': _frames,
        'dt_seconds': _dt,
        'sub_rigs': _subRigs,
        'particles_per_rig': _particles,
        'total_particles': _subRigs * _particles,
      };
}

List<CubismBenchmark> all() => [
      _PendulumStressBench(subRigs: 4, particles: 5),
      _PendulumStressBench(subRigs: 10, particles: 5),
      _PendulumStressBench(subRigs: 10, particles: 10),
    ];
