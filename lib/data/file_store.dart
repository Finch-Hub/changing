import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 照片文件存储（本地优先）
/// 照片原图与缩略图均存设备本地；云端同步为可选（V1.1）。
class FileStore {
  FileStore._();
  static final FileStore instance = FileStore._();

  Directory? _photoDir;

  Future<Directory> _ensureDir() async {
    if (_photoDir != null) return _photoDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _photoDir = dir;
    return dir;
  }

  /// 原图路径
  Future<String> photoPath(String projectId, String checkInId) async {
    final dir = await _ensureDir();
    return p.join(dir.path, '${projectId}_$checkInId.jpg');
  }

  /// 判断某条记录是否已有照片文件
  Future<bool> hasPhoto(String projectId, String checkInId) async {
    final f = File(await photoPath(projectId, checkInId));
    return f.existsSync();
  }

  /// 删除某条记录的照片文件
  Future<void> deletePhoto(String projectId, String checkInId) async {
    final f = File(await photoPath(projectId, checkInId));
    if (await f.exists()) await f.delete();
  }

  /// 删除某个项目下的所有照片文件（前缀匹配 `projectId_`）
  Future<void> deleteProjectPhotos(String projectId) async {
    final dir = await _ensureDir();
    if (!await dir.exists()) return;
    final prefix = '${projectId}_';
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(prefix)) {
        try {
          await entity.delete();
        } catch (_) {
          // 单个文件删除失败不阻断整体流程
        }
      }
    }
  }
}
