import '../auth/auth_session.dart';
import 'robot_models.dart';
import 'robot_service.dart';

/// 机器人目录内存缓存：用 robotKey 查 canChat，避免硬编码业务键。
class RobotCatalogCache {
  RobotCatalogCache._();
  static final RobotCatalogCache instance = RobotCatalogCache._();

  final Map<String, RobotRole> _byKey = <String, RobotRole>{};
  DateTime? _loadedAt;

  RobotRole? byKey(String robotKey) {
    final key = robotKey.trim();
    if (key.isEmpty) return null;
    return _byKey[key];
  }

  /// 优先 API 缓存，未命中再回退静态目录（未知 key 仍落到灯塔）。
  RobotRole resolve(String robotKey) {
    final key = robotKey.trim().isEmpty ? 'r_lighthouse' : robotKey.trim();
    return byKey(key) ?? RobotCatalog.roleById(key);
  }

  /// 缺省 true（兼容未拉取 / 旧字段）。
  bool canChat(String robotKey) => byKey(robotKey)?.canChat ?? true;

  void rememberAll(Iterable<RobotRole> roles) {
    for (final r in roles) {
      final key = r.id.trim();
      if (key.isEmpty) continue;
      _byKey[key] = r;
    }
    _loadedAt = DateTime.now();
  }

  Future<List<RobotRole>> refresh(AuthSession session, {bool force = false}) async {
    if (!force &&
        _byKey.isNotEmpty &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(seconds: 30)) {
      return _byKey.values.toList(growable: false);
    }
    final list = await RobotService(session: session).listRobots();
    rememberAll(list);
    return list;
  }
}
