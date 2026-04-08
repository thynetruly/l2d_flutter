// Parity regression test.
//
// Runs the Dart implementations of every Cubism Framework module against the
// C++ Framework's golden reference data and verifies maximum differences are
// within established tolerances. This catches regressions when changes to the
// Dart code cause divergence from the C++ source.
//
// To regenerate golden data after intentional Framework SDK upgrades:
//   cd test/golden_generator/build && ./golden_generator ../../golden ../../../Samples/Resources/Haru
//
// To diagnose a specific module's divergence:
//   dart run tool/verify_parity.dart
//
// To update tolerances after intentional improvements:
//   Edit test/parity_baseline.json

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_math.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_matrix44.dart';
import 'package:l2d_flutter_plugin/src/framework/math/cubism_vector2.dart';
import 'package:l2d_flutter_plugin/src/framework/math/float32.dart';
import 'package:l2d_flutter_plugin/src/framework/cubism_model_setting_json.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion_manager.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_expression_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';

class ParityResult {
  double maxAbs = 0.0;
  int samples = 0;

  void record(double expected, double actual) {
    samples++;
    final diff = (expected - actual).abs();
    if (diff > maxAbs) maxAbs = diff;
  }
}

late Map<String, dynamic> _baseline;
late CubismMoc _moc;

Map<String, dynamic> _loadGolden(String name) {
  final path = '${Directory.current.path}/test/golden/$name';
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

double _tolerance(String moduleKey) {
  final modules = _baseline['modules'] as Map<String, dynamic>;
  final m = modules[moduleKey] as Map<String, dynamic>;
  return (m['max_abs_tolerance'] as num).toDouble();
}

int _expectedSamples(String moduleKey) {
  final modules = _baseline['modules'] as Map<String, dynamic>;
  final m = modules[moduleKey] as Map<String, dynamic>;
  return (m['samples'] as num).toInt();
}

void _expectParity(String moduleKey, ParityResult result) {
  final tol = _tolerance(moduleKey);
  final expSamples = _expectedSamples(moduleKey);

  expect(result.samples, equals(expSamples),
      reason: '$moduleKey: sample count changed (golden data updated?)');
  expect(result.maxAbs, lessThanOrEqualTo(tol),
      reason: '$moduleKey: max diff ${result.maxAbs.toStringAsExponential(3)} '
          'exceeds baseline tolerance ${tol.toStringAsExponential(3)}. '
          'See test/parity_baseline.json and tool/verify_parity.dart.');
}

void main() {
  setUpAll(() {
    final coreSoPath =
        '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
    NativeLibrary.overrideBindings(
        CubismCoreBindings(DynamicLibrary.open(coreSoPath)));

    _baseline = jsonDecode(
            File('${Directory.current.path}/test/parity_baseline.json')
                .readAsStringSync()) as Map<String, dynamic>;

    _moc = CubismMoc.fromBytes(
        File('${Directory.current.path}/Samples/Resources/Haru/Haru.moc3')
            .readAsBytesSync());
  });

  tearDownAll(() {
    _moc.dispose();
  });

  group('Parity regression vs C++ Framework golden data', () {
    test('math.easingSine', () {
      final g = _loadGolden('math_golden.json');
      final r = ParityResult();
      for (final e in (g['easingSine'] as List).cast<Map<String, dynamic>>()) {
        r.record(
            (e['v'] as num).toDouble(),
            CubismMath.getEasingSine((e['t'] as num).toDouble()));
      }
      _expectParity('math.easingSine', r);
    });

    test('math.cardanoAlgorithmForBezier', () {
      final g = _loadGolden('math_golden.json');
      final r = ParityResult();
      for (final c in (g['bezier'] as List).cast<Map<String, dynamic>>()) {
        r.record(
            (c['result'] as num).toDouble(),
            CubismMath.cardanoAlgorithmForBezier(
                (c['a'] as num).toDouble(),
                (c['b'] as num).toDouble(),
                (c['c'] as num).toDouble(),
                (c['d'] as num).toDouble()));
      }
      _expectParity('math.cardanoAlgorithmForBezier', r);
    });

    test('math.matrixMultiply', () {
      final g = _loadGolden('math_golden.json');
      final r = ParityResult();
      for (final c in (g['matrixMultiply'] as List).cast<Map<String, dynamic>>()) {
        final a = Float32List.fromList(
            (c['a'] as List).map((e) => (e as num).toDouble()).toList());
        final b = Float32List.fromList(
            (c['b'] as List).map((e) => (e as num).toDouble()).toList());
        final expected =
            (c['result'] as List).map((e) => (e as num).toDouble()).toList();
        final dst = Float32List(16);
        CubismMatrix44.multiply(a, b, dst);
        for (int i = 0; i < 16; i++) {
          r.record(expected[i], dst[i]);
        }
      }
      _expectParity('math.matrixMultiply', r);
    });

    test('math.matrixInverse', () {
      final g = _loadGolden('math_golden.json');
      final r = ParityResult();
      for (final c in (g['matrixInverse'] as List).cast<Map<String, dynamic>>()) {
        final m = CubismMatrix44();
        final src = (c['matrix'] as List);
        for (int i = 0; i < 16; i++) {
          m.array[i] = (src[i] as num).toDouble();
        }
        final inv = m.getInvert();
        final expected = (c['inverse'] as List);
        for (int i = 0; i < 16; i++) {
          r.record((expected[i] as num).toDouble(), inv.array[i]);
        }
      }
      _expectParity('math.matrixInverse', r);
    });

    test('math.directionToRadian', () {
      final g = _loadGolden('math_golden.json');
      final r = ParityResult();
      for (final c in (g['directionToRadian'] as List).cast<Map<String, dynamic>>()) {
        final from = CubismVector2(
            (c['fromX'] as num).toDouble(), (c['fromY'] as num).toDouble());
        final to = CubismVector2(
            (c['toX'] as num).toDouble(), (c['toY'] as num).toDouble());
        r.record((c['result'] as num).toDouble(),
            CubismMath.directionToRadian(from, to));
      }
      _expectParity('math.directionToRadian', r);
    });

    test('breath.sineWave', () {
      final g = _loadGolden('breath_golden.json');
      final offset = Float32.cast((g['offset'] as num).toDouble());
      final peak = Float32.cast((g['peak'] as num).toDouble());
      final cycle = Float32.cast((g['cycle'] as num).toDouble());
      final r = ParityResult();
      // Match C++ exactly:
      //   _currentTime += deltaTimeSeconds; (float32 accumulator)
      //   t = _currentTime * 2.0f * Pi
      //   value = offset + peak * sinf(t / cycle)
      double currentTime = 0.0;
      final dt = Float32.cast(1.0 / 60.0);
      final twoPi = Float32.cast(2.0 * CubismMath.pi);
      for (final f in (g['frames'] as List).cast<Map<String, dynamic>>()) {
        currentTime = Float32.cast(currentTime + dt);
        final t = Float32.cast(currentTime * twoPi);
        // sinf is single-precision; Dart math.sin is double — there is an
        // inherent ~1e-7 ULP gap here that no amount of casting can close.
        final s = Float32.cast(math.sin(Float32.cast(t / cycle)));
        final actual = Float32.cast(offset + Float32.cast(peak * s));
        r.record((f['value'] as num).toDouble(), actual);
      }
      _expectParity('breath.sineWave', r);
    });

    test('look.formula', () {
      final g = _loadGolden('look_golden.json');
      // Inputs from JSON come as doubles parsed from "%.10g" floats.
      // Cast each to float32 to match C++ generator's computation chain.
      final fX = Float32.cast((g['factorX'] as num).toDouble());
      final fY = Float32.cast((g['factorY'] as num).toDouble());
      final fXY = Float32.cast((g['factorXY'] as num).toDouble());
      final r = ParityResult();
      for (final c in (g['inputs'] as List).cast<Map<String, dynamic>>()) {
        final dx = Float32.cast((c['dragX'] as num).toDouble());
        final dy = Float32.cast((c['dragY'] as num).toDouble());
        // C++ computation chain (with float32 truncation at each step):
        //   csmFloat32 dragXY = dx * dy;
        //   csmFloat32 result = fX*dx + fY*dy + fXY*dragXY;
        // Each operation truncates to float32.
        final dragXY = Float32.cast(dx * dy);
        final t1 = Float32.cast(fX * dx);
        final t2 = Float32.cast(fY * dy);
        final t3 = Float32.cast(fXY * dragXY);
        final actual = Float32.cast(Float32.cast(t1 + t2) + t3);
        r.record((c['delta'] as num).toDouble(), actual);
      }
      _expectParity('look.formula', r);
    });

    test('modelSetting.parsing', () {
      final g = _loadGolden('model_setting_haru_golden.json');
      final settings = CubismModelSettingJson.fromString(File(
              '${Directory.current.path}/Samples/Resources/Haru/Haru.model3.json')
          .readAsStringSync());

      final r = ParityResult();
      void checkStr(String expected, String actual) {
        r.samples++;
        if (expected != actual) r.maxAbs = double.infinity;
      }

      void checkInt(int expected, int actual) {
        r.samples++;
        if (expected != actual) r.maxAbs = double.infinity;
      }

      checkStr(g['modelFileName'] as String, settings.modelFileName);
      checkInt(g['textureCount'] as int, settings.textureCount);
      checkStr(g['physicsFileName'] as String, settings.physicsFileName);
      checkStr(g['poseFileName'] as String, settings.poseFileName);
      checkInt(g['expressionCount'] as int, settings.expressionCount);
      checkInt(g['motionGroupCount'] as int, settings.motionGroupCount);
      checkInt(g['hitAreasCount'] as int, settings.hitAreasCount);
      checkInt(g['eyeBlinkParameterCount'] as int, settings.eyeBlinkParameterCount);
      checkInt(g['lipSyncParameterCount'] as int, settings.lipSyncParameterCount);
      for (final t in (g['textures'] as List).asMap().entries) {
        checkStr((t.value as Map)['file'] as String,
            settings.getTextureFileName(t.key));
      }
      for (final e in (g['expressions'] as List).asMap().entries) {
        final exp = e.value as Map;
        checkStr(exp['name'] as String, settings.getExpressionName(e.key));
        checkStr(exp['file'] as String, settings.getExpressionFileName(e.key));
      }
      for (final mg in (g['motionGroups'] as List).asMap().entries) {
        final group = mg.value as Map;
        checkStr(group['name'] as String, settings.getMotionGroupName(mg.key));
        checkInt(group['count'] as int,
            settings.getMotionCount(group['name'] as String));
      }
      _expectParity('modelSetting.parsing', r);
    });

    test('expression.weightSamples', () {
      final g = _loadGolden('expression_haru_F01_golden.json');
      final expression = CubismExpressionMotion.fromString(File(
              '${Directory.current.path}/Samples/Resources/Haru/expressions/F01.exp3.json')
          .readAsStringSync());

      final r = ParityResult();
      for (final sample
          in (g['weightSamples'] as List).cast<Map<String, dynamic>>()) {
        final weight = (sample['weight'] as num).toDouble();
        final goldenParams =
            (sample['params'] as List).cast<Map<String, dynamic>>();

        final model = CubismModel.fromMoc(_moc);
        for (final p in model.parameters) {
          p.value = p.defaultValue;
        }
        expression.applyParameters(model, weight);

        for (final gp in goldenParams) {
          final dartParam = model.getParameter(gp['id'] as String);
          if (dartParam == null) continue;
          r.record((gp['value'] as num).toDouble(), dartParam.value);
        }
        model.dispose();
      }
      _expectParity('expression.weightSamples', r);
    });

    test('motion.curves', () {
      final g = _loadGolden('motion_haru_idle_golden.json');
      final motion = CubismMotion.fromString(File(
              '${Directory.current.path}/Samples/Resources/Haru/motions/haru_g_idle.motion3.json')
          .readAsStringSync());
      motion.fadeInSeconds = 0.0;
      motion.fadeOutSeconds = 0.0;
      motion.isLoop = false;

      final model = CubismModel.fromMoc(_moc);
      final manager = CubismMotionManager();
      manager.startMotionPriority(motion, priority: 1);

      final r = ParityResult();
      const dt = 1.0 / 60.0;
      for (final f in (g['frames'] as List).cast<Map<String, dynamic>>()) {
        manager.updateMotion(model, dt);
        model.update();
        for (final s in (f['paramSamples'] as List).cast<Map<String, dynamic>>()) {
          final dp = model.getParameter(s['id'] as String);
          if (dp == null) continue;
          r.record((s['value'] as num).toDouble(), dp.value);
        }
      }
      _expectParity('motion.curves', r);
      model.dispose();
    });

    test('motionQueue.priorityTransition', () {
      final g = _loadGolden('motion_queue_golden.json');
      final m1 = CubismMotion.fromString(File(
              '${Directory.current.path}/Samples/Resources/Haru/motions/haru_g_idle.motion3.json')
          .readAsStringSync());
      final m2 = CubismMotion.fromString(File(
              '${Directory.current.path}/Samples/Resources/Haru/motions/haru_g_m01.motion3.json')
          .readAsStringSync());
      m1.fadeInSeconds = 0.5;
      m1.fadeOutSeconds = 0.5;
      m2.fadeInSeconds = 0.5;
      m2.fadeOutSeconds = 0.5;

      final model = CubismModel.fromMoc(_moc);
      final manager = CubismMotionManager();
      manager.startMotionPriority(m1, priority: 1);

      final r = ParityResult();
      const dt = 1.0 / 60.0;
      final frames = (g['frames'] as List).cast<Map<String, dynamic>>();
      for (int i = 0; i < frames.length; i++) {
        if (i == 30) manager.startMotionPriority(m2, priority: 2);
        manager.updateMotion(model, dt);
        model.update();
        for (final s in (frames[i]['paramSamples'] as List).cast<Map<String, dynamic>>()) {
          final dp = model.getParameter(s['id'] as String);
          if (dp == null) continue;
          r.record((s['value'] as num).toDouble(), dp.value);
        }
      }
      _expectParity('motionQueue.priorityTransition', r);
      model.dispose();
    });

    test('physics.300frame', () {
      final g = _loadGolden('physics_haru_golden.json');
      final physics = CubismPhysics.fromString(File(
              '${Directory.current.path}/Samples/Resources/Haru/Haru.physics3.json')
          .readAsStringSync());
      final model = CubismModel.fromMoc(_moc);
      physics.stabilization(model);

      final r = ParityResult();
      const dt = 1.0 / 60.0;
      final frameData = (g['frameData'] as List).cast<Map<String, dynamic>>();
      for (int i = 0; i < frameData.length; i++) {
        final px = model.getParameter('ParamAngleX');
        if (px != null) px.value = math.sin(i * 0.1) * 30.0;
        physics.evaluate(model, dt);
        model.update();
        for (final s in (frameData[i]['paramSamples'] as List).cast<Map<String, dynamic>>()) {
          final dp = model.getParameter(s['id'] as String);
          if (dp == null) continue;
          r.record((s['value'] as num).toDouble(), dp.value);
        }
      }
      _expectParity('physics.300frame', r);
      model.dispose();
    });

    test('pose.120frame', () {
      final g = _loadGolden('pose_golden.json');
      final pose = CubismPose.fromString(File(
              '${Directory.current.path}/Samples/Resources/Haru/Haru.pose3.json')
          .readAsStringSync());
      final model = CubismModel.fromMoc(_moc);

      final r = ParityResult();
      const dt = 1.0 / 60.0;
      for (final f in (g['frames'] as List).cast<Map<String, dynamic>>()) {
        pose.updateParameters(model, dt);
        model.update();
        for (final po in (f['partOpacities'] as List).cast<Map<String, dynamic>>()) {
          final dp = model.getPart(po['id'] as String);
          if (dp == null) continue;
          r.record((po['opacity'] as num).toDouble(), dp.opacity);
        }
      }
      _expectParity('pose.120frame', r);
      model.dispose();
    });
  });
}
