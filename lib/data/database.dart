import 'package:changing/models/models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 本地优先存储层（SQLite）
/// 对应 PRD：照片默认存设备本地，云端同步为可选且需授权。
/// 本层只负责项目与记录点的结构化元数据；照片文件由 FileStore 管理。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = await getDatabasesPath();
    _db = await openDatabase(
      p.join(path, 'changing.db'),
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        frequency TEXT NOT NULL,
        streak INTEGER DEFAULT 0,
        remind TEXT,
        count INTEGER DEFAULT 0,
        monthMissed INTEGER DEFAULT 0,
        coverPath TEXT,
        archived INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE checkins (
        id TEXT PRIMARY KEY,
        projectId TEXT NOT NULL,
        date TEXT NOT NULL,
        photoPath TEXT NOT NULL,
        note TEXT,
        latitude REAL,
        longitude REAL,
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_checkins_project ON checkins (projectId, date DESC)');
  }

  /// 数据库升级：v1 -> v2 增加地理位置列
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE checkins ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE checkins ADD COLUMN longitude REAL');
    }
  }

  // ---------- 项目 CRUD ----------
  Future<List<Project>> getProjects({bool includeArchived = false}) async {
    final d = await db;
    final rows = await d.query(
      'projects',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'name',
    );
    return rows.map(Project.fromMap).toList();
  }

  Future<Project?> getProject(String id) async {
    final d = await db;
    final rows = await d.query('projects', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Project.fromMap(rows.first);
  }

  Future<void> insertProject(Project project) async {
    final d = await db;
    await d.insert('projects', project.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProject(Project project) async {
    final d = await db;
    await d.update('projects', project.toMap(),
        where: 'id = ?', whereArgs: [project.id]);
  }

  Future<void> deleteProject(String id) async {
    final d = await db;
    await d.delete('checkins', where: 'projectId = ?', whereArgs: [id]);
    await d.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 记录点 CRUD ----------
  Future<List<CheckIn>> getCheckIns(String projectId) async {
    final d = await db;
    final rows = await d.query(
      'checkins',
      where: 'projectId = ?',
      whereArgs: [projectId],
      orderBy: 'date DESC',
    );
    return rows.map(CheckIn.fromMap).toList();
  }

  Future<CheckIn?> latestCheckIn(String projectId) async {
    final list = await getCheckIns(projectId);
    return list.isEmpty ? null : list.first;
  }

  Future<void> insertCheckIn(CheckIn checkIn) async {
    final d = await db;
    await d.insert('checkins', checkIn.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCheckIn(String id) async {
    final d = await db;
    await d.delete('checkins', where: 'id = ?', whereArgs: [id]);
  }
}
