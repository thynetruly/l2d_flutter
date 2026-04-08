import 'dart:convert';

/// Parsed model3.json settings.
///
/// Ported from Framework/src/CubismModelSettingJson.hpp.
/// Parses the JSON manifest file that describes a Live2D model's resources:
/// moc3 file, textures, motions, expressions, physics, pose, hit areas, etc.
class CubismModelSettingJson {
  final Map<String, dynamic> _json;

  CubismModelSettingJson._(this._json);

  /// Parses a model3.json file from its raw JSON string.
  factory CubismModelSettingJson.fromString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return CubismModelSettingJson._(json);
  }

  /// Parses a model3.json file from raw bytes.
  factory CubismModelSettingJson.fromBytes(List<int> bytes) {
    return CubismModelSettingJson.fromString(utf8.decode(bytes));
  }

  // -- FileReferences --

  Map<String, dynamic>? get _fileReferences =>
      _json['FileReferences'] as Map<String, dynamic>?;

  /// The MOC3 file path.
  String get modelFileName =>
      (_fileReferences?['Moc'] as String?) ?? '';

  /// Number of textures.
  int get textureCount {
    final textures = _fileReferences?['Textures'] as List?;
    return textures?.length ?? 0;
  }

  /// The texture directory (empty string; textures use relative paths).
  String get textureDirectory => '';

  /// Gets the texture file path at [index].
  String getTextureFileName(int index) {
    final textures = _fileReferences?['Textures'] as List?;
    if (textures == null || index < 0 || index >= textures.length) return '';
    return textures[index] as String;
  }

  // -- Settings Files --

  /// Physics settings file path.
  String get physicsFileName =>
      (_fileReferences?['Physics'] as String?) ?? '';

  /// Pose settings file path.
  String get poseFileName =>
      (_fileReferences?['Pose'] as String?) ?? '';

  /// Display info file path.
  String get displayInfoFileName =>
      (_fileReferences?['DisplayInfo'] as String?) ?? '';

  /// User data file path.
  String get userDataFile =>
      (_fileReferences?['UserData'] as String?) ?? '';

  // -- Expressions --

  /// Number of expressions.
  int get expressionCount {
    final expressions = _fileReferences?['Expressions'] as List?;
    return expressions?.length ?? 0;
  }

  /// Gets the expression name at [index].
  String getExpressionName(int index) {
    final expressions = _fileReferences?['Expressions'] as List?;
    if (expressions == null || index < 0 || index >= expressions.length) return '';
    return (expressions[index] as Map<String, dynamic>)['Name'] as String? ?? '';
  }

  /// Gets the expression file path at [index].
  String getExpressionFileName(int index) {
    final expressions = _fileReferences?['Expressions'] as List?;
    if (expressions == null || index < 0 || index >= expressions.length) return '';
    return (expressions[index] as Map<String, dynamic>)['File'] as String? ?? '';
  }

  // -- Motions --

  Map<String, dynamic>? get _motions =>
      _fileReferences?['Motions'] as Map<String, dynamic>?;

  /// Number of motion groups.
  int get motionGroupCount => _motions?.keys.length ?? 0;

  /// Gets the motion group name at [index].
  String getMotionGroupName(int index) {
    final keys = _motions?.keys.toList();
    if (keys == null || index < 0 || index >= keys.length) return '';
    return keys[index];
  }

  /// Number of motions in a group.
  int getMotionCount(String groupName) {
    final group = _motions?[groupName] as List?;
    return group?.length ?? 0;
  }

  /// Gets the motion file path for [groupName] at [index].
  String getMotionFileName(String groupName, int index) {
    final group = _motions?[groupName] as List?;
    if (group == null || index < 0 || index >= group.length) return '';
    return (group[index] as Map<String, dynamic>)['File'] as String? ?? '';
  }

  /// Gets the motion sound file path for [groupName] at [index].
  String getMotionSoundFileName(String groupName, int index) {
    final group = _motions?[groupName] as List?;
    if (group == null || index < 0 || index >= group.length) return '';
    return (group[index] as Map<String, dynamic>)['Sound'] as String? ?? '';
  }

  /// Gets the motion fade-in time for [groupName] at [index].
  /// Returns -1.0 if not specified.
  double getMotionFadeInTimeValue(String groupName, int index) {
    final group = _motions?[groupName] as List?;
    if (group == null || index < 0 || index >= group.length) return -1.0;
    final value = (group[index] as Map<String, dynamic>)['FadeInTime'];
    if (value == null) return -1.0;
    return (value as num).toDouble();
  }

  /// Gets the motion fade-out time for [groupName] at [index].
  /// Returns -1.0 if not specified.
  double getMotionFadeOutTimeValue(String groupName, int index) {
    final group = _motions?[groupName] as List?;
    if (group == null || index < 0 || index >= group.length) return -1.0;
    final value = (group[index] as Map<String, dynamic>)['FadeOutTime'];
    if (value == null) return -1.0;
    return (value as num).toDouble();
  }

  // -- Hit Areas --

  List? get _hitAreas => _json['HitAreas'] as List?;

  /// Number of hit areas.
  int get hitAreasCount => _hitAreas?.length ?? 0;

  /// Gets the hit area ID at [index].
  String getHitAreaId(int index) {
    final areas = _hitAreas;
    if (areas == null || index < 0 || index >= areas.length) return '';
    return (areas[index] as Map<String, dynamic>)['Id'] as String? ?? '';
  }

  /// Gets the hit area name at [index].
  String getHitAreaName(int index) {
    final areas = _hitAreas;
    if (areas == null || index < 0 || index >= areas.length) return '';
    return (areas[index] as Map<String, dynamic>)['Name'] as String? ?? '';
  }

  // -- Layout --

  /// Gets the layout map (keys: "CenterX", "CenterY", "Width", etc.).
  Map<String, double>? getLayoutMap() {
    final layout = _json['Layout'] as Map<String, dynamic>?;
    if (layout == null) return null;
    return layout.map((key, value) => MapEntry(key, (value as num).toDouble()));
  }

  // -- Groups (EyeBlink, LipSync) --

  List? get _groups => _json['Groups'] as List?;

  List<String> _getGroupParameterIds(String groupName) {
    final groups = _groups;
    if (groups == null) return const [];
    for (final group in groups) {
      final g = group as Map<String, dynamic>;
      if (g['Name'] == groupName) {
        final ids = g['Ids'] as List?;
        if (ids == null) return const [];
        return ids.cast<String>();
      }
    }
    return const [];
  }

  /// Eye blink parameter IDs.
  List<String> get eyeBlinkParameterIds => _getGroupParameterIds('EyeBlink');

  /// Number of eye blink parameters.
  int get eyeBlinkParameterCount => eyeBlinkParameterIds.length;

  /// Gets the eye blink parameter ID at [index].
  String getEyeBlinkParameterId(int index) {
    final ids = eyeBlinkParameterIds;
    if (index < 0 || index >= ids.length) return '';
    return ids[index];
  }

  /// Lip sync parameter IDs.
  List<String> get lipSyncParameterIds => _getGroupParameterIds('LipSync');

  /// Number of lip sync parameters.
  int get lipSyncParameterCount => lipSyncParameterIds.length;

  /// Gets the lip sync parameter ID at [index].
  String getLipSyncParameterId(int index) {
    final ids = lipSyncParameterIds;
    if (index < 0 || index >= ids.length) return '';
    return ids[index];
  }
}
