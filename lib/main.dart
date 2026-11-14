import 'package:changing/pages/capture_page.dart';
import 'package:changing/pages/compare_page.dart';
import 'package:changing/pages/home_page.dart';
import 'package:changing/pages/lapse_page.dart';
import 'package:changing/pages/mine_page.dart';
import 'package:changing/pages/photo_viewer_page.dart';
import 'package:changing/pages/project_detail_page.dart';
import 'package:changing/providers/app_settings.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChangingApp());
}

class ChangingApp extends StatelessWidget {
  const ChangingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectRepository()),
        ChangeNotifierProvider(create: (_) => AppSettings()..load()),
      ],
      child: MaterialApp(
        title: '观变',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // 中文本地化：日期范围选择器等系统 Material 控件显示中文
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        // 限制系统字体最大缩放，避免超高倍字体放大导致固定尺寸组件溢出
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final clamped = media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.8,
              maxScaleFactor: 1.3,
            ),
          );
          return MediaQuery(data: clamped, child: child!);
        },
        routes: {
          '/': (_) => const HomePage(),
          '/capture': (_) => const CapturePage(),
          '/compare': (_) => const ComparePage(),
          '/lapse': (_) => const LapsePage(),
          '/mine': (_) => const MinePage(),
          '/project': (_) => const ProjectDetailPage(),
          '/photo_viewer': (_) => const PhotoViewerPage(),
        },
        initialRoute: '/',
      ),
    );
  }
}
