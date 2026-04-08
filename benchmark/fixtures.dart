// Shared fixture loader for benchmarks that need real model data.
//
// Mirrors `test/helpers/test_setup.dart` but exposes all eight sample models
// (Haru, Hiyori, Mao, Mark, Natori, Ren, Rice, Wanko) via a lazy-loaded enum.
// Each entry caches its parsed settings / physics / pose / motion so that
// benchmarks instantiating multiple models don't re-read and re-parse JSON
// on every variant.
//
// Loading the Cubism Core native library is done once at first call — the
// benchmark suite is pure Dart, but [CubismModel] still requires the C core
// to construct model instances.

import 'dart:ffi';
import 'dart:io';

import 'package:l2d_flutter_plugin/src/core/cubism_moc.dart';
import 'package:l2d_flutter_plugin/src/core/cubism_model.dart';
import 'package:l2d_flutter_plugin/src/core/native_library.dart';
import 'package:l2d_flutter_plugin/src/framework/cubism_model_setting_json.dart';
import 'package:l2d_flutter_plugin/src/framework/effect/cubism_pose.dart';
import 'package:l2d_flutter_plugin/src/framework/motion/cubism_motion.dart';
import 'package:l2d_flutter_plugin/src/framework/physics/cubism_physics.dart';
import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';

/// Identity of one of the sample models bundled under
/// `Samples/Resources/<name>/`.
enum SampleModel {
  haru,
  hiyori,
  mao,
  mark,
  natori,
  ren,
  rice,
  wanko,
}

extension SampleModelName on SampleModel {
  /// Directory / file-prefix name, e.g. `Haru` for [SampleModel.haru].
  String get displayName => switch (this) {
        SampleModel.haru => 'Haru',
        SampleModel.hiyori => 'Hiyori',
        SampleModel.mao => 'Mao',
        SampleModel.mark => 'Mark',
        SampleModel.natori => 'Natori',
        SampleModel.ren => 'Ren',
        SampleModel.rice => 'Rice',
        SampleModel.wanko => 'Wanko',
      };

  /// Short lowercase identifier used in metadata keys.
  String get metaKey => switch (this) {
        SampleModel.haru => 'haru',
        SampleModel.hiyori => 'hiyori',
        SampleModel.mao => 'mao',
        SampleModel.mark => 'mark',
        SampleModel.natori => 'natori',
        SampleModel.ren => 'ren',
        SampleModel.rice => 'rice',
        SampleModel.wanko => 'wanko',
      };

  /// True if this model ships with a `pose3.json` file. Only half of the
  /// sample models do — benchmarks skip the pose phase otherwise.
  bool get hasPose => switch (this) {
        SampleModel.haru ||
        SampleModel.hiyori ||
        SampleModel.mao ||
        SampleModel.natori =>
          true,
        SampleModel.mark ||
        SampleModel.ren ||
        SampleModel.rice ||
        SampleModel.wanko =>
          false,
      };
}

/// Lazy-loaded, parsed fixture for a single sample model.
///
/// All [CubismModel] instances constructed from [fixture.model()] share the
/// same backing [CubismMoc] — which is intentional: the moc is immutable and
/// shareable, so multi-instance / multi-model benchmarks exercise per-instance
/// state without paying the (one-time) moc-parse cost for each copy.
class ModelFixture {
  final SampleModel sample;
  final String sampleDir;
  final CubismMoc moc;
  final CubismModelSettingJson settings;
  final String? physicsJson;
  final String? poseJson;
  final String? idleMotionJson;

  ModelFixture._({
    required this.sample,
    required this.sampleDir,
    required this.moc,
    required this.settings,
    required this.physicsJson,
    required this.poseJson,
    required this.idleMotionJson,
  });

  /// Constructs a fresh model instance sharing this fixture's moc.
  ///
  /// Caller owns the returned instance and must call `dispose()` when done.
  CubismModel newModel() => CubismModel.fromMoc(moc);

  /// Parses a fresh [CubismPhysics]. Physics state is per-instance, so each
  /// call returns a new object.
  CubismPhysics? newPhysics() =>
      physicsJson == null ? null : CubismPhysics.fromString(physicsJson!);

  /// Parses a fresh [CubismPose]. Pose state is per-instance.
  CubismPose? newPose() =>
      poseJson == null ? null : CubismPose.fromString(poseJson!);

  /// Parses a fresh [CubismMotion] from the idle motion file. Motion data
  /// is immutable once parsed but the per-frame curve evaluation state is
  /// on the motion manager, not the [CubismMotion] itself, so sharing is
  /// safe — but we return a fresh instance anyway to match the typical
  /// real-world pattern (one motion per logical animation).
  CubismMotion? newIdleMotion() => idleMotionJson == null
      ? null
      : CubismMotion.fromString(idleMotionJson!);
}

/// Central registry of parsed fixtures. Loaded on demand.
class Fixtures {
  Fixtures._();

  static bool _coreLoaded = false;
  static final Map<SampleModel, ModelFixture> _cache = {};

  /// Ensures the native Cubism Core library is loaded. Safe to call
  /// multiple times. Only attempts the load on first call.
  static void ensureCoreLoaded() {
    if (_coreLoaded) return;
    try {
      // If already loaded by another path, this succeeds with the bindings
      // that were installed previously.
      NativeLibrary.bindings;
    } catch (_) {
      NativeLibrary.overrideBindings(
        CubismCoreBindings(DynamicLibrary.open(_corePath())),
      );
    }
    _coreLoaded = true;
  }

  /// Loads and caches the fixture for [model]. Subsequent calls return the
  /// cached value.
  static ModelFixture load(SampleModel model) {
    ensureCoreLoaded();
    final cached = _cache[model];
    if (cached != null) return cached;

    final dir = '${Directory.current.path}/Samples/Resources/${model.displayName}';
    final mocPath = '$dir/${model.displayName}.moc3';
    final settingsPath = '$dir/${model.displayName}.model3.json';

    final moc = CubismMoc.fromBytes(File(mocPath).readAsBytesSync());
    final settings = CubismModelSettingJson.fromString(
        File(settingsPath).readAsStringSync());

    final physicsFileName = settings.physicsFileName;
    final physicsJson = physicsFileName.isEmpty
        ? null
        : _readIfExists('$dir/$physicsFileName');

    final poseFileName = settings.poseFileName;
    final poseJson = poseFileName.isEmpty
        ? null
        : _readIfExists('$dir/$poseFileName');

    final idleMotionJson = _findIdleMotion(dir, settings);

    final fixture = ModelFixture._(
      sample: model,
      sampleDir: dir,
      moc: moc,
      settings: settings,
      physicsJson: physicsJson,
      poseJson: poseJson,
      idleMotionJson: idleMotionJson,
    );
    _cache[model] = fixture;
    return fixture;
  }

  /// Convenience: the Haru fixture, used by most single-model benchmarks.
  static ModelFixture haru() => load(SampleModel.haru);

  static String? _readIfExists(String path) {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  /// Picks the first motion from the "Idle" group when present; falls back
  /// to the first motion from any group. Returns null if no motion exists.
  static String? _findIdleMotion(
      String dir, CubismModelSettingJson settings) {
    // Try "Idle" first.
    if (settings.getMotionCount('Idle') > 0) {
      final file = settings.getMotionFileName('Idle', 0);
      final found = _readIfExists('$dir/$file');
      if (found != null) return found;
    }
    // Fall back to the first motion in the first group that has any.
    for (int g = 0; g < settings.motionGroupCount; g++) {
      final groupName = settings.getMotionGroupName(g);
      if (settings.getMotionCount(groupName) > 0) {
        final file = settings.getMotionFileName(groupName, 0);
        final found = _readIfExists('$dir/$file');
        if (found != null) return found;
      }
    }
    return null;
  }

  static String _corePath() {
    final cwd = Directory.current.path;
    if (Platform.isLinux) {
      return '$cwd/Core/dll/linux/x86_64/libLive2DCubismCore.so';
    }
    if (Platform.isMacOS) {
      // Honour whichever arch ships in Core/dll/macos. Benchmarks are
      // developer-run, so we don't auto-detect arm64 vs x86_64 here — the
      // user can override via DYLD_LIBRARY_PATH if needed.
      return '$cwd/Core/dll/macos/libLive2DCubismCore.dylib';
    }
    if (Platform.isWindows) {
      return '$cwd\\Core\\dll\\windows\\x86_64\\Live2DCubismCore.dll';
    }
    throw UnsupportedError(
      'Cubism Core shared library path not configured for '
      '${Platform.operatingSystem}. Add the path for your platform in '
      'benchmark/fixtures.dart:_corePath.',
    );
  }
}
