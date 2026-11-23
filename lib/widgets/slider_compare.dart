import 'dart:io';

import 'package:changing/theme/app_theme.dart';
import 'package:changing/widgets/app_photo.dart';
import 'package:flutter/material.dart';

/// 滑块对比组件（拖动分隔线左右扫视新旧差异）
///
/// 布局：底层铺「右图（新）」全图，顶层用 [ClipRect] 让「左图（旧）」
/// 只露出分隔线左侧部分，拖动分隔线即可左右扫视新旧差异。
///
/// U-08：由对比页私有组件抽为共享组件，供项目详情页的
/// 「第一张 → 最近一张」迷你预览复用（同一套手势与视觉语言）。
class SliderCompare extends StatefulWidget {
  final File leftFile;
  final File rightFile;
  final String leftLabel;
  final String rightLabel;
  final double pos;
  final BoxFit fit;
  final ValueChanged<double> onPos;

  /// 是否显示日期角标（迷你预览空间有限时可关闭）
  final bool showLabels;

  const SliderCompare({
    super.key,
    required this.leftFile,
    required this.rightFile,
    required this.leftLabel,
    required this.rightLabel,
    required this.pos,
    required this.fit,
    required this.onPos,
    this.showLabels = true,
  });

  @override
  State<SliderCompare> createState() => _SliderCompareState();
}

class _SliderCompareState extends State<SliderCompare> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // 分隔线中心 x 坐标（0 ~ w），随 pos 变化
        final dividerX = widget.pos * w;

        return GestureDetector(
          // 用 globalPosition 精确换算：手指在屏幕上横向滑动，
          // 立即把分隔线移到手指位置，避免 localPosition 基准偏移导致的跳动。
          onHorizontalDragStart: (d) => _updateFrom(d.globalPosition),
          onHorizontalDragUpdate: (d) => _updateFrom(d.globalPosition),
          onTapDown: (d) => _updateFrom(d.globalPosition),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 底层：右图（新），铺满
              AppPhoto(path: widget.rightFile.path, fit: widget.fit),

              // 顶层：左图（旧），裁剪到分隔线左侧
              ClipRect(
                clipper: _LeftClip(pos: widget.pos),
                child: AppPhoto(path: widget.leftFile.path, fit: widget.fit),
              ),

              // 分隔线
              Positioned(
                left: dividerX - 1.5,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(width: 3, color: Colors.white),
                ),
              ),

              // 拖动滑块
              Positioned(
                left: dividerX - 14,
                top: h / 2 - 14,
                child: IgnorePointer(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.compare_arrows,
                        size: 16, color: Colors.black54),
                  ),
                ),
              ),

              // 日期标注（跟随滑块左右区域动态切换）
              if (widget.showLabels) ...[
                if (widget.pos > 0.15)
                  SliderDateLabel(
                      text: widget.leftLabel, alignment: Alignment.topLeft),
                if (widget.pos < 0.85)
                  SliderDateLabel(
                      text: widget.rightLabel, alignment: Alignment.topRight),
              ],
            ],
          ),
        );
      },
    );
  }

  void _updateFrom(Offset globalPosition) {
    // 取当前组件的全局边界，把手指全局坐标换算成 0~1 的本地比例
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final localX = box.globalToLocal(globalPosition).dx;
    final w = box.size.width;
    if (w <= 0) return;
    widget.onPos((localX / w).clamp(0.0, 1.0));
  }
}

/// 自定义裁剪：只显示左侧 [0, pos] 比例的区域（宽度方向）
class _LeftClip extends CustomClipper<Rect> {
  final double pos;
  const _LeftClip({required this.pos});

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * pos.clamp(0.0, 1.0), size.height);
  }

  @override
  bool shouldReclip(_LeftClip oldClipper) => oldClipper.pos != pos;
}

/// 对比视图日期角标（半透明黑底白字，保证任意照片上可读）
class SliderDateLabel extends StatelessWidget {
  final String text;
  final Alignment alignment;

  /// 高亮（叠加模式的新图层用主色底区分）
  final bool highlight;

  const SliderDateLabel({
    super.key,
    required this.text,
    required this.alignment,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.primary.withValues(alpha: 0.85)
              : const Color(0x8C000000), // 0.55 透明度，保证白字可读
          borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: AppDimens.fontCaption(context), color: Colors.white),
        ),
      ),
    );
  }
}