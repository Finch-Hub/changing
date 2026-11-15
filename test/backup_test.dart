import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:changing/data/database.dart';
import 'package:changing/models/models.dart';
import 'package:changing/services/backup_service.dart';
import 'package:changing/theme/app_theme.dart' show ProjectType, RecordFrequency;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final service = BackupService.instance;

  Project proj(String id, String name, {int count = 0, bool archived = false}) =>
      Project(
        id: id,
        name: name,
        type: ProjectType.fitness,
        frequency: RecordFrequency.weekly,
        count: count,
        archived: archived,
      );

  CheckIn check(
    String id,
    String projectId,
    DateTime date, {
    String? note,
    double? lat,
    double? lng,
    String photoPath = '/old/dir/x.jpg',
  }) =>
      CheckIn(
        id: id,
        projectId: projectId,
        date: date,
        photoPath: photoPath,
        note: note,
        latitude: lat,
        longitude: lng,
      );

  group('备份包纯字节打包 / 解包', () {
    test('往返一致：项目 / 记录 / 照片 / 备注 / 位置完整保留', () {
      final projects = [proj('p1', '减脂 90 天', count: 1)];
      final checkins = [
        check('c1', 'p1', DateTime(2026, 11, 12, 9, 30),
            note: '第一天', lat: 31.23, lng: 121.47),
      ];
      final photos = {'p1_c1.jpg': Uint8List.fromList([1, 2, 3, 4, 5])};
      final manifest = {
        'formatVersion': BackupService.formatVersion,
        'app': 'changing',
        'exportedAt': DateTime(2026, 11, 14).toIso8601String(),
        'projectCount': 1,
        'checkInCount': 1,
      };
      final data = {
        'projects': projects.map((e) => e.toMap()).toList(),
        'checkins': checkins.map((e) {
          final m = e.toMap();
          m['photoPath'] = 'p1_c1.jpg';
          return m;
        }).toList(),
      };

      final bytes =
          service.encodePackage(manifest: manifest, data: data, photos: photos);
      final content = service.decodePackage(bytes);

      expect(content.manifest.formatVersion, BackupService.formatVersion);
      expect(content.manifest.projectCount, 1);
      expect(content.data.projects.length, 1);
      expect(content.data.projects.first.name, '减脂 90 天');
      expect(content.data.checkins.length, 1);
      final c = content.data.checkins.first;
      expect(c.note, '第一天');
      expect(c.latitude, 31.23);
      expect(c.longitude, 121.47);
      expect(c.date, DateTime(2026, 11, 12, 9, 30));
      expect(content.photos['p1_c1.jpg'], Uint8List.fromList([1, 2, 3, 4, 5]));
    });

    test('data.json 中照片路径为相对文件名（换机重映射前提）', () {
      final bytes = service.encodePackage(
        manifest: {'formatVersion': 1, 'projectCount': 0, 'checkInCount': 1},
        data: {
          'projects': [],
          'checkins': [
            check('c1', 'p1', DateTime(2026, 1, 1),
                    photoPath: '/data/user/0/com.changing/app_flutter/photos/p1_c1.jpg')
                .toMap()
              ..['photoPath'] = 'p1_c1.jpg',
          ],
        },
        photos: {'p1_c1.jpg': Uint8List.fromList([9])},
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final dataFile = archive.files.firstWhere((f) => f.name == 'data.json');
      final data =
          jsonDecode(utf8.decode(dataFile.content as List<int>)) as Map<String, dynamic>;
      final first = (data['checkins'] as List).first as Map<String, dynamic>;
      expect(first['photoPath'], 'p1_c1.jpg');
    });

    test('损坏文件抛 BackupException', () {
      expect(
        () => service.decodePackage(Uint8List.fromList([0, 1, 2, 3])),
        throwsA(isA<BackupException>()),
      );
    });

    test('缺少 manifest / data 抛 BackupException', () {
      final archive = Archive();
      final bytes = utf8.encode('{}');
      archive.addFile(ArchiveFile('random.txt', bytes.length, bytes));
      final encoded = ZipEncoder().encode(archive)!;
      expect(
        () => service.decodePackage(Uint8List.fromList(encoded)),
        throwsA(isA<BackupException>()),
      );
    });

    test('格式版本过新抛 BackupException', () {
      final bytes = service.encodePackage(
        manifest: {
          'formatVersion': BackupService.formatVersion + 99,
          'projectCount': 0,
          'checkInCount': 0,
        },
        data: {'projects': [], 'checkins': []},
        photos: {},
      );
      expect(
        () => service.decodePackage(bytes),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('合并策略筛选（selectForImport）', () {
    final backupProjects = [proj('p1', '备份P1'), proj('p2', '备份P2')];
    final backupCheckIns = [
      check('c1', 'p1', DateTime(2026, 1, 1)),
      check('c2', 'p2', DateTime(2026, 2, 2)),
    ];

    test('跳过重复：已存在项目及其记录被排除，仅保留新项目', () {
      final sel = service.selectForImport(
        backupProjects: backupProjects,
        backupCheckIns: backupCheckIns,
        existingIds: {'p1'},
        overwrite: false,
      );
      expect(sel.skipped, 1);
      expect(sel.projects.map((e) => e.id), ['p2']);
      expect(sel.checkins.map((e) => e.id), ['c2']);
      expect(sel.replaceIds, isEmpty);
    });

    test('覆盖更新：已存在项目纳入导入并记入 replaceIds', () {
      final sel = service.selectForImport(
        backupProjects: backupProjects,
        backupCheckIns: backupCheckIns,
        existingIds: {'p1'},
        overwrite: true,
      );
      expect(sel.skipped, 0);
      expect(sel.projects.map((e) => e.id).toSet(), {'p1', 'p2'});
      expect(sel.checkins.map((e) => e.id).toSet(), {'c1', 'c2'});
      expect(sel.replaceIds, {'p1'});
    });

    test('全新设备：无重复时全部导入', () {
      final sel = service.selectForImport(
        backupProjects: backupProjects,
        backupCheckIns: backupCheckIns,
        existingIds: {},
        overwrite: false,
      );
      expect(sel.skipped, 0);
      expect(sel.projects.length, 2);
      expect(sel.checkins.length, 2);
      expect(sel.replaceIds, isEmpty);
    });
  });

  group('数据库批量导入事务', () {
    final db = AppDatabase.instance;

    setUp(() async {
      final d = await db.db;
      await d.delete('checkins');
      await d.delete('projects');
    });

    test('插入新项目与记录', () async {
      await db.importBackupData(
        projects: [proj('p1', '项目1', count: 1)],
        checkins: [check('c1', 'p1', DateTime(2026, 1, 1), note: '备注')],
        replaceProjectIds: {},
      );
      final projects = await db.getProjects(includeArchived: true);
      expect(projects.length, 1);
      final checks = await db.getCheckIns('p1');
      expect(checks.length, 1);
      expect(checks.first.note, '备注');
    });

    test('replaceProjectIds 先删后插：旧记录被替换', () async {
      await db.insertProject(proj('p1', '旧名', count: 1));
      await db.insertCheckIn(check('c1', 'p1', DateTime(2026, 1, 1)));

      await db.importBackupData(
        projects: [proj('p1', '新名', count: 1)],
        checkins: [check('c1new', 'p1', DateTime(2026, 5, 5), note: '覆盖')],
        replaceProjectIds: {'p1'},
      );

      final p1 = await db.getProject('p1');
      expect(p1!.name, '新名');
      final checks = await db.getCheckIns('p1');
      expect(checks.length, 1);
      expect(checks.first.id, 'c1new');
      expect(checks.first.note, '覆盖');
    });

    test('事务回滚：插入失败时整体不写入', () async {
      await db.insertProject(proj('p1', '原有项目'));
      // 注入含 projects 表不存在列的原始行，使事务内 INSERT 抛 SQL 错误
      final badRow = proj('p2', '不该出现').toMap()
        ..['nonexistent_column'] = 'x';
      await expectLater(
        db.importBackupData(
          rawProjectRows: [badRow],
          rawCheckInRows: [check('c2', 'p2', DateTime(2026, 1, 1)).toMap()],
        ),
        throwsA(anything),
      );
      final projects = await db.getProjects(includeArchived: true);
      expect(projects.length, 1);
      expect(projects.first.id, 'p1'); // p2 未写入，回滚成功
      expect(await db.getCheckIns('p2'), isEmpty);
    });
  });
}