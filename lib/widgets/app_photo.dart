import 'dart:io';

import 'package:changing/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// 统一照片组件（G5）：内置加载容错，文件缺失/损坏时回退占位图，
/// 避免首页封面、对比页等处出现红屏。
class AppPhoto extends StatelessWidget {
  final String path;
  final BoxFit fit;

  /// 占位背景色（默认页面底色；深色场景可传黑色）
  final Color placeholderColor;

  const AppPhoto({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.placeholderColor = AppColors.background,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return _placeholder();
    }
    return Image.file(
      file,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: placeholderColor,
      child: const Center(
        child: Icon(Icons.broken_image_outlined,
            size: 32, color: AppColors.textWeak),
      ),
    );
  }
}
