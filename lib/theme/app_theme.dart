import 'package:flutter/material.dart';

/// 设计规格包 · 全局设计 Token（暖橙主题）
/// 来源：《变化记录App-设计规格包》§1 全局设计规范
class AppColors {
  // 品牌色
  static const primary = Color(0xFFE8783C); // 主色 温暖橙
  static const primaryDark = Color(0xFFC95F1E); // 主色深（文字/描边）
  static const primaryLight = Color(0xFFFBEDE3); // 主色浅底（选中态底）

  // 通用
  static const background = Color(0xFFFAF7F2); // 页面背景 暖米白
  static const surface = Color(0xFFFFFFFF); // 卡片/表面
  static const line = Color(0xFFE9E2D6); // 分隔线 / 未选中描边
  static const textPrimary = Color(0xFF2B2118); // 正文
  static const textSecondary = Color(0xFF7D7161); // 辅助文字（加深，保证对比度）
  static const textWeak = Color(0xFFB8AD9F); // 弱化文字（仅装饰性用途）

  // 语义色
  static const danger = Color(0xFFD64545); // 危险操作（删除等）
  static const success = Color(0xFF1A9D5C);
  static const warning = Color(0xFFD97A06);
  static const info = Color(0xFF3B6FE0);

  // 开关
  static const switchOn = Color(0xFFE8783C);
  static const switchOff = Color(0xFFE3DCD2); // 关闭态轨道：暖灰，融入页面

  // 覆盖层（拍摄页 / 对比视图底）
  static const overlayDark = Color(0x59000000); // rgba(0,0,0,0.35)
  static const ghostOverlay = Color(0x2EFFFFFF); // rgba(255,255,255,0.18) 参考图虚影
  static const crosshair = Color(0x73FFFFFF); // rgba(255,255,255,0.45) 十字辅助线
}

/// 设计规格包 · 圆角 / 字号 / 间距
///
/// 字号为「流式」：随屏幕宽度与系统字体缩放因子动态计算，
/// 兼容不同长宽、不同分辨率（含 vivo X200 Pro mini 等高密度小屏）的手机。
class AppDimens {
  // 圆角
  static const radiusSmall = 8.0;
  static const radiusMedium = 16.0;
  static const radiusLarge = 24.0;

  // 基准字号（以 375dp 设计宽为基准），实际值 = 基准 * 宽度缩放系数
  static const _fontDisplayBase = 30.0;
  static const _fontTitleBase = 22.0;
  static const _fontBodyBase = 16.0;
  static const _fontSmallBase = 13.0;

  // 设计基准宽度（dp），用于计算宽度缩放系数
  static const _designWidth = 375.0;

  /// 宽度缩放系数：窄屏缩小、宽屏放大，限制在 [0.85, 1.25] 避免极端
  static double scale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final s = w / _designWidth;
    return s.clamp(0.85, 1.25);
  }

  // 流式字号（逻辑像素，含屏幕宽度缩放）
  static double fontDisplay(BuildContext context) =>
      _fontDisplayBase * scale(context);
  static double fontTitle(BuildContext context) =>
      _fontTitleBase * scale(context);
  static double fontBody(BuildContext context) =>
      _fontBodyBase * scale(context);
  static double fontSmall(BuildContext context) =>
      _fontSmallBase * scale(context);

  /// 说明性小字（角标 / Tab 文字 / 徽章）：保底 11px，
  /// 避免小屏 scale=0.85 时「fontSmall - 4」缩到 ~7px 难以辨认。
  static double fontCaption(BuildContext context) {
    final v = fontSmall(context) - 1;
    return v < 11 ? 11 : v;
  }

  // 间距（8 的倍数）
  static const gapXs = 8.0;
  static const gapSm = 16.0;
  static const gapMd = 24.0;
  static const gapLg = 32.0;

  // 边距（弹性：小屏 20 / 标准 24 / 大屏 32）
  static double margin(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 20.0;
    if (w < 480) return 24.0;
    return 32.0;
  }

  // 最小触控热区
  static const minTouchTarget = 44.0;
}

/// 项目类型标签（决定封面渐变色与默认频率）
enum ProjectType { fitness, family, pet, plant, skincare, custom }

extension ProjectTypeX on ProjectType {
  String get label {
    switch (this) {
      case ProjectType.fitness:
        return '健身';
      case ProjectType.family:
        return '家庭';
      case ProjectType.pet:
        return '宠物';
      case ProjectType.plant:
        return '植物';
      case ProjectType.skincare:
        return '护肤';
      case ProjectType.custom:
        return '自定义';
    }
  }

  /// 封面占位渐变色（设计规格 · 类型配色）
  List<Color> get palette {
    switch (this) {
      case ProjectType.fitness:
        return const [Color(0xFFE8783C), Color(0xFFC95F1E)];
      case ProjectType.family:
        return const [Color(0xFFF2A9C0), Color(0xFFE8783C)];
      case ProjectType.pet:
        return const [Color(0xFFC9B28C), Color(0xFF8C7A5B)];
      case ProjectType.plant:
        return const [Color(0xFF7FAE6B), Color(0xFF4E7A3E)];
      case ProjectType.skincare:
        return const [Color(0xFFF0C7A6), Color(0xFFD89A6E)];
      case ProjectType.custom:
        return const [Color(0xFFA8B8C9), Color(0xFF6E8298)];
    }
  }

  static ProjectType fromLabel(String label) {
    return ProjectType.values.firstWhere(
      (e) => e.label == label,
      orElse: () => ProjectType.custom,
    );
  }
}

/// 记录频率（决定提醒文案与默认节奏）
enum RecordFrequency { weekly, monthly, yearly, irregular }

extension RecordFrequencyX on RecordFrequency {
  String get label {
    switch (this) {
      case RecordFrequency.weekly:
        return '每周';
      case RecordFrequency.monthly:
        return '每月';
      case RecordFrequency.yearly:
        return '每年';
      case RecordFrequency.irregular:
        return '不定期';
    }
  }

  static RecordFrequency fromLabel(String label) {
    return RecordFrequency.values.firstWhere(
      (e) => e.label == label,
      orElse: () => RecordFrequency.irregular,
    );
  }
}

/// 应用主题
///
/// 组件级主题在此统一收口（G1）：AppBar / Dialog / SnackBar / Switch /
/// 输入框 / 按钮全部对齐暖橙设计体系，各页面不再重复写样式。
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.primaryDark,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.background,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      titleLarge: const TextStyle(
        fontSize: AppDimens._fontDisplayBase,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: const TextStyle(
        fontSize: AppDimens._fontTitleBase,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: const TextStyle(
        fontSize: AppDimens._fontBodyBase,
        color: AppColors.textPrimary,
      ),
      bodyMedium: const TextStyle(
        fontSize: AppDimens._fontSmallBase,
        color: AppColors.textSecondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
      ),
    ),
    // SnackBar：悬浮圆角，不再压住底部按钮；深色底 + 白字
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
      ),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      actionTextColor: AppColors.primaryLight,
    ),
    // Switch：开启=主色橙轨道，关闭=暖灰轨道，thumb 恒白、无默认描边
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.switchOff,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    // 输入框：暖米白填充底，聚焦主色描边
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF4EFE7),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    // 主按钮：橙实底白字、16 圆角（对话框内用 TextButton 不受影响）
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}
