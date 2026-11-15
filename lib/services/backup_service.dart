import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:changing/data/database.dart';
import 'package:changing/data/file_store.dart';
import 'package:changing/models/models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 数据批量导入 / 导出（换机迁移）。
///
/// 备份包 `.changing` 本质是 ZIP：
/// ```
/// manifest.json   格式版本 / 导出时间 / 项目数 / 记录数
/// data.json       projects[] + checkins[]（照片只存相对文件名）
/// photos/         {projectId}_{checkInId}.jpg 原图
/// ```
///
/// 关键设计：DB 里 `photoPath` / `coverPath` 是**绝对路径**，换机后必然失效。
/// 因此备份只存相对文件名，导入时在新设备用 [FileStore.photoPath] 重新生成
/// 绝对路径（路径重映射），保证照片可被找到。
///
/// 纯字节打包 / 解包（[encodePackage] / [decodePackage]）不依赖文件系统与数据库，
/// 便于单元测试；文件系统与 DB 交互放在 [exportBackup] / [importBackup]。
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// 当前备份格式版本（未来格式演进时递增，导入端做兼容判断）
  static const int formatVersion = 1;

  static const String _manifestName = 'manifest.json';
  static const String _dataName = 'data.json';
  static const String _photoDir = 'photos';

  final AppDatabase _db = AppDatabase.instance;
  final FileStore _files = FileStore.instance;

  // ============================ 导出 ============================

  /// 导出备份包。
  ///
  /// [projectIds] 为空表示导出全部项目（含已归档）；否则仅导出指定项目。
  /// [onProgress] 回传 `已完成照片数 / 总照片数`，用于进度展示。
  /// 返回生成的 `.changing` 文件（位于缓存目录，供系统分享）。
  Future<File> exportBackup({
    Set<String>? projectIds,
    void Function(int done, int total)? onProgress,
  }) async {
    final all = await _db.getProjects(includeArchived: true);
    final projects = projectIds == null
        ? all
        : all.where((e) => projectIds.contains(e.id)).toList();

    final checkins = <CheckIn>[];
    final photos = <String, Uint8List>{};
    for (final proj in projects) {
      for (final c in await _db.getCheckIns(proj.id)) {
        checkins.add(c);
        final f = File(c.photoPath);
        if (await f.exists()) {
          photos[_relativeName(c.projectId, c.id)] = await f.readAsBytes();
        }
      }
    }

    final total = checkins.length;
    var done = 0;
    onProgress?.call(0, total);

    final data = <String, dynamic>{
      'projects': projects.map((e) => e.toMap()).toList(),
      'checkins': checkins.map((c) {
        final m = c.toMap();
        // 绝对路径 → 相对文件名（换机重映射的关键）
        m['photoPath'] = _relativeName(c.projectId, c.id);
        onProgress?.call(++done, total);
        return m;
      }).toList(),
    };
    final manifest = <String, dynamic>{
      'formatVersion': formatVersion,
      'app': 'changing',
      'exportedAt': DateTime.now().toIso8601String(),
      'projectCount': projects.length,
      'checkInCount': checkins.length,
    };

    final bytes = encodePackage(manifest: manifest, data: data, photos: photos);
    final dir = await getTemporaryDirectory();
    final stamp = _stamp(DateTime.now());
    final out = File(p.join(dir.path, 'changing_backup_$stamp.changing'));
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  // ============================ 导入 ============================

  /// 解析备份包做导入预览（不落库）。损坏 / 不兼容时抛 [BackupException]。
  Future<BackupPreview> previewBackup(String path) async {
    final bytes = await File(path).readAsBytes();
    final pkg = decodePackage(bytes);
    final existing = await _db.getProjects(includeArchived: true);
    final existingIds = existing.map((e) => e.id).toSet();
    final dup = pkg.data.projects.where((e) => existingIds.contains(e.id)).length;
    return BackupPreview(
      manifest: pkg.manifest,
      data: pkg.data,
      photos: pkg.photos,
      duplicateProjectCount: dup,
    );
  }

  /// 执行导入。
  ///
  /// [overwrite] = false（默认）：本机已存在的项目 id 跳过，只导入新项目；
  /// [overwrite] = true：同 id 项目用备份数据覆盖（先删旧记录与照片再写入）。
  /// 照片解压到本机目录后重映射绝对路径，元数据走事务批量写入。
  Future<ImportResult> importBackup(
    BackupPreview preview, {
    bool overwrite = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final existing = await _db.getProjects(includeArchived: true);
    final selection = selectForImport(
      backupProjects: preview.data.projects,
      backupCheckIns: preview.data.checkins,
      existingIds: existing.map((e) => e.id).toSet(),
      overwrite: overwrite,
    );

    // 覆盖模式：先清掉旧照片文件，避免残留
    for (final id in selection.replaceIds) {
      await _files.deleteProjectPhotos(id);
    }

    // 解压照片 + 路径重映射
    final total = selection.checkins.length;
    var done = 0;
    var restoredPhotos = 0;
    onProgress?.call(0, total);
    final remapped = <CheckIn>[];
    for (final c in selection.checkins) {
      final rel = _relativeName(c.projectId, c.id);
      final newPath = await _files.photoPath(c.projectId, c.id);
      final photoBytes = preview.photos[rel];
      if (photoBytes != null) {
        final f = File(newPath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(photoBytes, flush: true);
        restoredPhotos++;
      }
      remapped.add(CheckIn(
        id: c.id,
        projectId: c.projectId,
        date: c.date,
        photoPath: newPath,
        note: c.note,
        latitude: c.latitude,
        longitude: c.longitude,
      ));
      onProgress?.call(++done, total);
    }

    // 重映射封面路径（coverPath 指向最新记录照片）
    final fixedProjects = selection.projects.map((proj) {
      final cs = remapped.where((c) => c.projectId == proj.id).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return proj.copyWith(
        count: cs.length,
        coverPath: cs.isEmpty ? null : cs.first.photoPath,
      );
    }).toList();

    await _db.importBackupData(
      projects: fixedProjects,
      checkins: remapped,
      replaceProjectIds: selection.replaceIds,
    );

    return ImportResult(
      importedProjects: fixedProjects.length,
      importedCheckIns: remapped.length,
      skippedProjects: selection.skipped,
      restoredPhotos: restoredPhotos,
    );
  }

  /// 按合并策略筛选待导入的项目 / 记录（纯逻辑，便于单测）。
  ///
  /// 跳过模式：已存在的项目整条跳过（含其记录）；覆盖模式：已存在项目纳入
  /// 导入并记入 [ImportSelection.replaceIds]，由 DB 层先删后插，避免主键冲突。
  /// 返回的记录只保留待导入项目下的记录。
  ImportSelection selectForImport({
    required List<Project> backupProjects,
    required List<CheckIn> backupCheckIns,
    required Set<String> existingIds,
    required bool overwrite,
  }) {
    final projects = <Project>[];
    final replaceIds = <String>{};
    var skipped = 0;
    for (final proj in backupProjects) {
      final exists = existingIds.contains(proj.id);
      if (exists && !overwrite) {
        skipped++;
        continue;
      }
      projects.add(proj);
      if (exists) replaceIds.add(proj.id);
    }
    final importIds = projects.map((e) => e.id).toSet();
    final checkins =
        backupCheckIns.where((c) => importIds.contains(c.projectId)).toList();
    return ImportSelection(
      projects: projects,
      checkins: checkins,
      replaceIds: replaceIds,
      skipped: skipped,
    );
  }

  // ====================== 纯字节打包 / 解包（可单测） ======================

  /// 把 manifest + data + 照片打包成 ZIP 字节。JPEG 已压缩，用 STORE 不再压缩。
  Uint8List encodePackage({
    required Map<String, dynamic> manifest,
    required Map<String, dynamic> data,
    required Map<String, Uint8List> photos,
  }) {
    final archive = Archive();
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile(_manifestName, manifestBytes.length, manifestBytes));
    final dataBytes = utf8.encode(jsonEncode(data));
    archive.addFile(ArchiveFile(_dataName, dataBytes.length, dataBytes));
    photos.forEach((name, bytes) {
      archive.addFile(ArchiveFile('$_photoDir/$name', bytes.length, bytes));
    });
    final encoded = ZipEncoder().encode(archive, level: Deflate.NO_COMPRESSION);
    return Uint8List.fromList(encoded!);
  }

  /// 解析 ZIP 字节为备份内容。结构非法 / 版本过新时抛 [BackupException]。
  BackupContent decodePackage(Uint8List bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const BackupException('备份文件已损坏，无法解析');
    }

    ArchiveFile? manifestFile;
    ArchiveFile? dataFile;
    final photos = <String, Uint8List>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      if (f.name == _manifestName) {
        manifestFile = f;
      } else if (f.name == _dataName) {
        dataFile = f;
      } else if (f.name.startsWith('$_photoDir/')) {
        photos[p.basename(f.name)] = Uint8List.fromList(f.content as List<int>);
      }
    }
    if (manifestFile == null || dataFile == null) {
      throw const BackupException('不是有效的观变备份包（缺少 manifest / data）');
    }

    Map<String, dynamic> manifest;
    Map<String, dynamic> data;
    try {
      manifest =
          jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
      data = jsonDecode(utf8.decode(dataFile.content as List<int>)) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('备份包内容格式错误');
    }

    final version = (manifest['formatVersion'] as int?) ?? 0;
    if (version > formatVersion) {
      throw BackupException('备份格式版本 $version 过新，请升级 App 后再导入');
    }

    final projects = (data['projects'] as List<dynamic>? ?? [])
        .map((e) => Project.fromMap(e as Map<String, dynamic>))
        .toList();
    final checkins = (data['checkins'] as List<dynamic>? ?? [])
        .map((e) => CheckIn.fromMap(e as Map<String, dynamic>))
        .toList();

    return BackupContent(
      manifest: BackupManifest.fromJson(manifest),
      data: BackupData(projects: projects, checkins: checkins),
      photos: photos,
    );
  }

  // ============================ 工具 ============================

  String _relativeName(String projectId, String checkInId) =>
      '${projectId}_$checkInId.jpg';

  String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }
}

/// 备份包元信息
class BackupManifest {
  final int formatVersion;
  final DateTime? exportedAt;
  final int projectCount;
  final int checkInCount;

  const BackupManifest({
    required this.formatVersion,
    this.exportedAt,
    required this.projectCount,
    required this.checkInCount,
  });

  factory BackupManifest.fromJson(Map<String, dynamic> m) => BackupManifest(
        formatVersion: (m['formatVersion'] as int?) ?? 0,
        exportedAt: m['exportedAt'] == null
            ? null
            : DateTime.tryParse(m['exportedAt'] as String),
        projectCount: (m['projectCount'] as int?) ?? 0,
        checkInCount: (m['checkInCount'] as int?) ?? 0,
      );
}

/// 备份包结构化数据（照片路径为相对文件名）
class BackupData {
  final List<Project> projects;
  final List<CheckIn> checkins;
  const BackupData({required this.projects, required this.checkins});
}

/// 解包结果
class BackupContent {
  final BackupManifest manifest;
  final BackupData data;
  final Map<String, Uint8List> photos;
  const BackupContent({
    required this.manifest,
    required this.data,
    required this.photos,
  });
}

/// 导入预览（含与本机重复的项目数）
class BackupPreview {
  final BackupManifest manifest;
  final BackupData data;
  final Map<String, Uint8List> photos;
  final int duplicateProjectCount;
  const BackupPreview({
    required this.manifest,
    required this.data,
    required this.photos,
    required this.duplicateProjectCount,
  });

  int get projectCount => data.projects.length;
  int get checkInCount => data.checkins.length;
}

/// 合并筛选结果（待导入项目 / 记录 + 需先删除的覆盖 id + 跳过数）
class ImportSelection {
  final List<Project> projects;
  final List<CheckIn> checkins;
  final Set<String> replaceIds;
  final int skipped;
  const ImportSelection({
    required this.projects,
    required this.checkins,
    required this.replaceIds,
    required this.skipped,
  });
}

/// 导入结果统计
class ImportResult {
  final int importedProjects;
  final int importedCheckIns;
  final int skippedProjects;
  final int restoredPhotos;
  const ImportResult({
    required this.importedProjects,
    required this.importedCheckIns,
    required this.skippedProjects,
    required this.restoredPhotos,
  });
}

/// 备份 / 恢复业务异常（携带可直接展示给用户的中文文案）
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}