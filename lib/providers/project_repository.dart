import 'package:changing/data/database.dart';
import 'package:changing/data/file_store.dart';
import 'package:changing/models/models.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// 项目仓库（状态管理）
/// 持有项目列表，负责 CRUD 与记录点关联。
class ProjectRepository extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;
  final _uuid = const Uuid();

  List<Project> _projects = [];
  bool _loaded = false;

  /// 各项目最近一次记录时间（首页卡片「最近 x 天前」用）
  final Map<String, DateTime> _lastDates = {};

  List<Project> get projects => _projects;
  bool get loaded => _loaded;

  /// 某项目最近一次记录时间（无记录返回 null）
  DateTime? lastDateOf(String projectId) => _lastDates[projectId];

  /// 加载项目列表（排除已归档）
  Future<void> load() async {
    _projects = await _db.getProjects();
    _lastDates.clear();
    for (final p in _projects) {
      final latest = await _db.latestCheckIn(p.id);
      if (latest != null) _lastDates[p.id] = latest.date;
    }
    _loaded = true;
    notifyListeners();
  }

  Project? byId(String id) {
    for (final p in _projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 创建项目
  Future<Project> createProject({
    required String name,
    required ProjectType type,
    required RecordFrequency frequency,
    String? remind,
  }) async {
    final project = Project(
      id: _uuid.v4(),
      name: name,
      type: type,
      frequency: frequency,
      remind: remind,
    );
    await _db.insertProject(project);
    await load();
    return project;
  }

  /// 归档 / 恢复
  Future<void> setArchived(String id, bool archived) async {
    final p = byId(id);
    if (p == null) return;
    await _db.updateProject(p.copyWith(archived: archived));
    await load();
  }

  Future<void> deleteProject(String id) async {
    // 先取记录点，用于删除照片文件（数据库删除后记录点即丢失）
    final checkins = await _db.getCheckIns(id);
    await _db.deleteProject(id);
    // 级联删除照片文件（避免残留占空间）
    await FileStore.instance.deleteProjectPhotos(id);
    // 兜底：按记录点逐条删除（兼容历史文件命名）
    for (final c in checkins) {
      await FileStore.instance.deletePhoto(id, c.id);
    }
    await load();
  }

  /// 刷新单个项目（新增记录后更新 count / 封面）
  Future<void> refreshProject(String id) async {
    final p = await _db.getProject(id);
    if (p == null) return;
    final checkins = await _db.getCheckIns(id);
    final updated = p.copyWith(
      count: checkins.length,
      coverPath: checkins.isEmpty ? null : checkins.first.photoPath,
    );
    await _db.updateProject(updated);
    await load();
  }

  /// 新增记录点
  Future<CheckIn> addCheckIn({
    required String projectId,
    required DateTime date,
    required String photoPath,
    String? note,
    double? latitude,
    double? longitude,
  }) async {
    final checkIn = CheckIn(
      id: _uuid.v4(),
      projectId: projectId,
      date: date,
      photoPath: photoPath,
      note: note,
      latitude: latitude,
      longitude: longitude,
    );
    await _db.insertCheckIn(checkIn);
    await refreshProject(projectId);
    return checkIn;
  }

  /// 获取项目下所有记录点（时间降序）
  Future<List<CheckIn>> getCheckIns(String projectId) =>
      _db.getCheckIns(projectId);

  /// V3：删除单条记录点（数据库 + 照片文件），并刷新项目计数/封面
  Future<void> deleteCheckIn(CheckIn checkIn) async {
    await _db.deleteCheckIn(checkIn.id);
    await FileStore.instance.deletePhoto(checkIn.projectId, checkIn.id);
    await refreshProject(checkIn.projectId);
  }

  /// 最近一次记录（用于对齐拍照的参考图）
  Future<CheckIn?> latestCheckIn(String projectId) =>
      _db.latestCheckIn(projectId);
}
