import 'dart:io';
import 'dart:ui' as ui;

import 'package:changing/models/models.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/services/compare_export_service.dart';
import 'package:changing/services/media_export_service.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:changing/widgets/app_photo.dart';
import 'package:changing/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// 对比模式
enum CompareMode { slider, sideBySide, overlay }

/// 对比视图
/// 对应 PRD FR-03：并排 / 左右滑块 / 透明叠加三种方式对比任意两个记录点。
class ComparePage extends StatefulWidget {
  const ComparePage({super.key});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  String? _projectId;
  Project? _project;
  List<CheckIn> _checkIns = [];
  bool _loading = true;

  CompareMode _mode = CompareMode.slider;
  int _leftIndex = 0; // 较早（旧）
  int _rightIndex = 0; // 较晚（新）
  double _sliderPos = 0.5;
  double _overlayOpacity = 0.5; // 叠加模式独立透明度，避免与滑块位置互相干扰

  /// 两图构图基准：true=裁切对齐（cover，默认），false=完整显示（contain）
  bool _fitCover = true;

  /// C5：对比视图截图边界（导出当前模式所见即所得）
  final GlobalKey _compareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) _projectId = args['projectId'] as String?;
    if (_projectId == null) {
      setState(() => _loading = false);
      return;
    }
    final repo = context.read<ProjectRepository>();
    _project = repo.byId(_projectId!);
    final list = await repo.getCheckIns(_projectId!);
    // 按时间升序（旧在前）
    list.sort((a, b) => a.date.compareTo(b.date));
    setState(() {
      _checkIns = list;
      if (list.length >= 2) {
        _leftIndex = 0;
        _rightIndex = list.length - 1;
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectName = _project?.name ?? '对比';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '$projectName · 对比',
          style: TextStyle(
            fontSize: AppDimens.fontTitle(context),
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _export,
            child: Text(
              '导出',
              style: TextStyle(
                  fontSize: AppDimens.fontBody(context),
                  color: AppColors.primary),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _checkIns.length < 2
              ? const _InsufficientView()
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final margin = AppDimens.margin(context);
    final left = _checkIns[_leftIndex];
    final right = _checkIns[_rightIndex];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: Column(
        children: [
          // 模式切换
          SegmentedSelector<CompareMode>(
            options: CompareMode.values,
            selected: _mode,
            labelOf: (m) => switch (m) {
              CompareMode.slider => '滑块',
              CompareMode.sideBySide => '并排',
              CompareMode.overlay => '叠加',
            },
            onSelect: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 12),
          // 记录选择：任选两张对比（不再固定首尾）
          _RecordPickerRow(
            leftLabel: left.monthLabel,
            rightLabel: right.monthLabel,
            onPickLeft: () => _pickRecord(isLeft: true),
            onPickRight: () => _pickRecord(isLeft: false),
          ),
          const SizedBox(height: 12),
          // 构图基准切换：裁切对齐 / 完整显示
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => setState(() => _fitCover = !_fitCover),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _fitCover ? Icons.crop_free : Icons.fit_screen,
                      size: 14,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _fitCover ? '裁切对齐' : '完整显示',
                      style: TextStyle(
                        fontSize: AppDimens.fontCaption(context),
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 对比视图区（RepaintBoundary 供 C5 截图导出）
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
              child: RepaintBoundary(
                key: _compareKey,
                child: Container(
                  color: Colors.black,
                  // G6：模式切换 200ms 淡入淡出，替代生硬跳变
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey(_mode),
                      child: _buildCompareView(left, right),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 提示文案（随模式切换）
          Text(
            _modeDescription(_mode),
            style: TextStyle(
                fontSize: AppDimens.fontSmall(context),
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          // 操作按钮
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: '分享',
                  icon: Icons.share,
                  onPressed: _share,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: PrimaryButton(
                  label: '缩时影片',
                  icon: Icons.movie_outlined,
                  onPressed: () => Navigator.pushNamed(context, '/lapse',
                      arguments: {'projectId': _projectId}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 各对比模式的描述文案
  String _modeDescription(CompareMode mode) {
    switch (mode) {
      case CompareMode.slider:
        return '拖动分隔线，左右扫视新旧差异';
      case CompareMode.sideBySide:
        return '左右并排对照，一眼看清变化';
      case CompareMode.overlay:
        return '上下拖动调节透明度，叠加观察';
    }
  }

  Widget _buildCompareView(CheckIn left, CheckIn right) {
    final lFile = File(left.photoPath);
    final rFile = File(right.photoPath);
    final fit = _fitCover ? BoxFit.cover : BoxFit.contain;

    switch (_mode) {
      case CompareMode.slider:
        return _SliderCompare(
          leftFile: lFile,
          rightFile: rFile,
          leftLabel: left.monthLabel,
          rightLabel: right.monthLabel,
          pos: _sliderPos,
          fit: fit,
          onPos: (p) => setState(() => _sliderPos = p),
        );
      case CompareMode.sideBySide:
        return _SideBySideCompare(
          leftFile: lFile,
          rightFile: rFile,
          leftLabel: left.monthLabel,
          rightLabel: right.monthLabel,
          fit: fit,
        );
      case CompareMode.overlay:
        return _OverlayCompare(
          leftFile: lFile,
          rightFile: rFile,
          leftLabel: left.monthLabel,
          rightLabel: right.monthLabel,
          opacity: _overlayOpacity,
          fit: fit,
          onOpacity: (v) => setState(() => _overlayOpacity = v),
        );
    }
  }

  /// 弹出记录选择器：从项目全部记录中任选一张作为「旧」或「新」
  Future<void> _pickRecord({required bool isLeft}) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                isLeft ? '选择较早的记录（旧）' : '选择较晚的记录（新）',
                style: TextStyle(
                  fontSize: AppDimens.fontBody(ctx),
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _checkIns.length,
                itemBuilder: (_, i) {
                  final c = _checkIns[i];
                  final selected = isLeft ? i == _leftIndex : i == _rightIndex;
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, i),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusSmall),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(c.photoPath), fit: BoxFit.cover),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: AppColors.overlayDark,
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                c.monthLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: AppDimens.fontCaption(ctx),
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          if (selected)
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: AppColors.primary, width: 3),
                                borderRadius: BorderRadius.circular(
                                    AppDimens.radiusSmall),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isLeft) {
        _leftIndex = picked;
      } else {
        _rightIndex = picked;
      }
      // 保持旧在前、新在后
      if (_leftIndex > _rightIndex) {
        final t = _leftIndex;
        _leftIndex = _rightIndex;
        _rightIndex = t;
      }
    });
  }

  /// C5：导出当前模式的对比图。
  /// 并排模式走高清合成（含日期标注）；滑块/叠加模式截取当前视图，
  /// 所见即所得，不再「无论什么模式都导出并排图」。
  Future<String> _exportCurrent() async {
    if (_mode == CompareMode.sideBySide) {
      return CompareExportService.instance.exportSideBySide(
        _checkIns[_leftIndex],
        _checkIns[_rightIndex],
      );
    }
    final boundary = _compareKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw const FormatException('对比视图未就绪');
    }
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw const FormatException('截图失败');
    }
    final base = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(base.path, 'exports'));
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final outPath = p.join(
      outDir.path,
      'compare_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await File(outPath).writeAsBytes(byteData.buffer.asUint8List());
    return outPath;
  }

  Future<void> _export() async {
    if (_checkIns.length < 2) return;
    try {
      final path = await _exportCurrent();
      // 写入系统相册，用户在相册里找得到（不再只留在私有目录）
      final saved =
          await MediaExportService.instance.saveImageToGallery(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved ? '对比图已保存到相册' : '对比图已导出'),
          action: SnackBarAction(label: '分享', onPressed: () => _share()),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败，请重试')),
        );
      }
    }
  }

  /// 分享当前对比图：导出 → 调起系统分享面板
  Future<void> _share() async {
    if (_checkIns.length < 2) return;
    try {
      final path = await _exportCurrent();
      await MediaExportService.instance.shareFile(
        path,
        text: '${_project?.name ?? '观变'} 的变化对比',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享失败，请重试')),
        );
      }
    }
  }
}

/// 记录选择行：「旧 [月份 ▾] → 新 [月份 ▾]」
class _RecordPickerRow extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final VoidCallback onPickLeft;
  final VoidCallback onPickRight;

  const _RecordPickerRow({
    required this.leftLabel,
    required this.rightLabel,
    required this.onPickLeft,
    required this.onPickRight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _pickChip(context, '旧', leftLabel, onPickLeft)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward,
              size: 16, color: AppColors.textSecondary),
        ),
        Expanded(child: _pickChip(context, '新', rightLabel, onPickRight)),
      ],
    );
  }

  Widget _pickChip(
      BuildContext context, String tag, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$tag · $label',
              style: TextStyle(
                fontSize: AppDimens.fontCaption(context),
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more,
                size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// 滑块对比（拖动分隔线）
///
/// 布局：底层铺「右图（新）」全图，顶层用 [ClipRect] 让「左图（旧）」
/// 只露出分隔线左侧部分，拖动分隔线即可左右扫视新旧差异。
class _SliderCompare extends StatefulWidget {
  final File leftFile;
  final File rightFile;
  final String leftLabel;
  final String rightLabel;
  final double pos;
  final BoxFit fit;
  final ValueChanged<double> onPos;

  const _SliderCompare({
    required this.leftFile,
    required this.rightFile,
    required this.leftLabel,
    required this.rightLabel,
    required this.pos,
    required this.fit,
    required this.onPos,
  });

  @override
  State<_SliderCompare> createState() => _SliderCompareState();
}

class _SliderCompareState extends State<_SliderCompare> {
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
              if (widget.pos > 0.15)
                _DateLabel(
                    text: widget.leftLabel, alignment: Alignment.topLeft),
              if (widget.pos < 0.85)
                _DateLabel(
                    text: widget.rightLabel, alignment: Alignment.topRight),
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

/// 并排对比
class _SideBySideCompare extends StatelessWidget {
  final File leftFile;
  final File rightFile;
  final String leftLabel;
  final String rightLabel;
  final BoxFit fit;

  const _SideBySideCompare({
    required this.leftFile,
    required this.rightFile,
    required this.leftLabel,
    required this.rightLabel,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(child: AppPhoto(path: leftFile.path, fit: fit)),
            Container(width: 3, color: Colors.white),
            Expanded(child: AppPhoto(path: rightFile.path, fit: fit)),
          ],
        ),
        _DateLabel(text: leftLabel, alignment: Alignment.topLeft),
        _DateLabel(text: rightLabel, alignment: Alignment.topRight),
      ],
    );
  }
}

/// 叠加对比（透明度混合，可拖动上下调节）
class _OverlayCompare extends StatefulWidget {
  final File leftFile;
  final File rightFile;
  final String leftLabel;
  final String rightLabel;
  final double opacity;
  final BoxFit fit;
  final ValueChanged<double> onOpacity;

  const _OverlayCompare({
    required this.leftFile,
    required this.rightFile,
    required this.leftLabel,
    required this.rightLabel,
    required this.opacity,
    required this.fit,
    required this.onOpacity,
  });

  @override
  State<_OverlayCompare> createState() => _OverlayCompareState();
}

class _OverlayCompareState extends State<_OverlayCompare> {
  /// C6：拖动中显示透明度数值气泡
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 垂直拖动调节透明度：上滑增加、下滑减少
      onVerticalDragStart: (_) => setState(() => _dragging = true),
      onVerticalDragEnd: (_) => setState(() => _dragging = false),
      onVerticalDragCancel: () => setState(() => _dragging = false),
      onVerticalDragUpdate: (d) {
        final newValue =
            (widget.opacity - d.delta.dy / 300).clamp(0.0, 1.0);
        widget.onOpacity(newValue);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppPhoto(path: widget.leftFile.path, fit: widget.fit),
          Opacity(
            opacity: widget.opacity,
            child: AppPhoto(path: widget.rightFile.path, fit: widget.fit),
          ),
          // C6：月份角标（新图用主色底区分新旧层）
          _DateLabel(text: widget.leftLabel, alignment: Alignment.topLeft),
          _DateLabel(
            text: widget.rightLabel,
            alignment: Alignment.topRight,
            highlight: true,
          ),
          // C6：右侧垂直透明度进度轨
          Positioned(
            right: 10,
            top: 48,
            bottom: 48,
            child: IgnorePointer(
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: widget.opacity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // C6：拖动时浮现「新图 xx%」气泡
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _dragging ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '新图 ${(widget.opacity * 100).round()}%',
                      style: TextStyle(
                        fontSize: AppDimens.fontCaption(context),
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateLabel extends StatelessWidget {
  final String text;
  final Alignment alignment;

  /// 高亮（叠加模式的新图层用主色底区分）
  final bool highlight;
  const _DateLabel({
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

class _InsufficientView extends StatelessWidget {
  const _InsufficientView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '记录不足，至少需要 2 张记录点才能对比',
        style: TextStyle(
            fontSize: AppDimens.fontBody(context),
            color: AppColors.textSecondary),
      ),
    );
  }
}
