import 'package:changing/models/models.dart';
import 'package:changing/pages/compare_page.dart' show resolveCompareIndices;
import 'package:changing/pages/home_page.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/providers/app_settings.dart';
import 'package:changing/theme/app_theme.dart'
    show ProjectType, ProjectTypeX, RecordFrequency, RecordFrequencyX;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // 桌面测试环境初始化 sqflite FFI
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Project model', () {
    test('toMap / fromMap 往返一致', () {
      final p = Project(
        id: 'p1',
        name: '减脂 90 天',
        type: ProjectType.fitness,
        frequency: RecordFrequency.weekly,
        streak: 3,
        remind: '每周五',
        count: 5,
        monthMissed: true,
        archived: true,
      );
      final restored = Project.fromMap(p.toMap());
      expect(restored.id, 'p1');
      expect(restored.name, '减脂 90 天');
      expect(restored.type, ProjectType.fitness);
      expect(restored.frequency, RecordFrequency.weekly);
      expect(restored.streak, 3);
      expect(restored.remind, '每周五');
      expect(restored.count, 5);
      expect(restored.monthMissed, isTrue);
      expect(restored.archived, isTrue);
    });

    test('fromLabel 未知标签回退', () {
      expect(ProjectTypeX.fromLabel('不存在的类型'), ProjectType.custom);
      expect(RecordFrequencyX.fromLabel('不存在的频率'), RecordFrequency.irregular);
    });

    test('copyWith 保留未修改字段', () {
      final p = Project(
        id: 'p1',
        name: 'A',
        type: ProjectType.pet,
        frequency: RecordFrequency.monthly,
        coverPath: '/x/y.jpg',
      );
      final updated = p.copyWith(archived: true);
      expect(updated.coverPath, '/x/y.jpg');
      expect(updated.archived, isTrue);
      expect(updated.name, 'A');
    });
  });

  group('CheckIn model', () {
    test('monthLabel 补零', () {
      final c = CheckIn(
        id: 'c1',
        projectId: 'p1',
        date: DateTime(2026, 3, 5),
        photoPath: '/a.jpg',
      );
      expect(c.monthLabel, '2026-03');
    });

    test('U-04 dayLabel 同年只到 MM-DD、跨年带年份', () {
      final thisYear = DateTime.now().year;
      final c = CheckIn(
        id: 'c1',
        projectId: 'p1',
        date: DateTime(thisYear, 3, 5),
        photoPath: '/a.jpg',
      );
      expect(c.dayLabel, '03-05');
      final old = CheckIn(
        id: 'c2',
        projectId: 'p1',
        date: DateTime(thisYear - 1, 11, 8),
        photoPath: '/b.jpg',
      );
      expect(old.dayLabel, '${thisYear - 1}-11-08');
    });

    test('U-04 recordLabel 序号 = 升序下标 + 1，同月两次可区分', () {
      final y = DateTime.now().year;
      final a = CheckIn(
          id: 'a', projectId: 'p1', date: DateTime(y, 11, 1), photoPath: '/a');
      final b = CheckIn(
          id: 'b', projectId: 'p1', date: DateTime(y, 11, 8), photoPath: '/b');
      // 两条记录同属 11 月：monthLabel 相同，recordLabel 必须不同
      expect(a.monthLabel, b.monthLabel);
      expect(a.recordLabel(0), '第 1 次 · 11-01');
      expect(b.recordLabel(1), '第 2 次 · 11-08');
      expect(a.recordLabel(0) == b.recordLabel(1), isFalse);
    });

    test('toMap / fromMap 往返一致', () {
      final c = CheckIn(
        id: 'c1',
        projectId: 'p1',
        date: DateTime(2026, 11, 12, 9, 30),
        photoPath: '/a.jpg',
        note: '备注',
      );
      final restored = CheckIn.fromMap(c.toMap());
      expect(restored.date, c.date);
      expect(restored.note, '备注');
    });
  });

  group('U-08 对比页初始下标归一化', () {
    test('未传入时退回首尾', () {
      final r = resolveCompareIndices(length: 5);
      expect(r.left, 0);
      expect(r.right, 4);
    });

    test('传入合法首尾 index 原样保留', () {
      final r = resolveCompareIndices(length: 4, initLeft: 0, initRight: 3);
      expect(r.left, 0);
      expect(r.right, 3);
    });

    test('越界裁剪到合法范围', () {
      final r = resolveCompareIndices(length: 3, initLeft: -5, initRight: 99);
      expect(r.left, 0);
      expect(r.right, 2);
    });

    test('左右相等或倒置时退回首尾（保证两张不同、旧在前）', () {
      final same = resolveCompareIndices(length: 4, initLeft: 2, initRight: 2);
      expect(same.left, 0);
      expect(same.right, 3);
      final reversed =
          resolveCompareIndices(length: 4, initLeft: 3, initRight: 1);
      expect(reversed.left, 0);
      expect(reversed.right, 3);
    });

    test('记录不足 2 张时不产生非法下标', () {
      final r = resolveCompareIndices(length: 1, initLeft: 0, initRight: 5);
      expect(r.left, 0);
      expect(r.right, 0);
    });
  });

  testWidgets('HomePage 空态展示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ProjectRepository()),
          ChangeNotifierProvider(create: (_) => AppSettings()),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有变化项目'), findsOneWidget);
    expect(find.text('新建项目'), findsOneWidget);
  });

  test('FileStore photoPath 路径格式', () async {
    // photoPath 依赖 path_provider，纯 Dart 环境不可用，跳过
  }, skip: 'path_provider 需要平台通道，单测环境不可用');
}
