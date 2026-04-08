/// Immutable string ID for identifying parameters, parts, and drawables.
///
/// Ported from Framework/src/Id/CubismId.hpp.
///
/// In the C++ Framework, IDs are interned via CubismIdManager. In Dart,
/// we use a simple string-interning [Map] in [CubismIdManager] and
/// represent IDs as lightweight wrappers around [String].
class CubismId {
  final String _id;

  const CubismId(this._id);

  /// The string value of this ID.
  String get string => _id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CubismId && _id == other._id);

  @override
  int get hashCode => _id.hashCode;

  @override
  String toString() => _id;
}

/// Manages a pool of interned [CubismId] instances.
///
/// Ported from Framework/src/Id/CubismIdManager.hpp.
class CubismIdManager {
  final Map<String, CubismId> _ids = {};

  /// Returns the [CubismId] for [id], creating it if it doesn't exist.
  CubismId getId(String id) {
    return _ids.putIfAbsent(id, () => CubismId(id));
  }

  /// Registers multiple IDs at once.
  void registerIds(List<String> ids) {
    for (final id in ids) {
      getId(id);
    }
  }

  /// Whether an ID with the given string exists in the pool.
  bool isExist(String id) => _ids.containsKey(id);
}
