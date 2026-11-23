import 'dart:io';
import 'dart:ui' as ui;

import 'package:changing/models/models.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/services/compare_export_service.dart';
import 'package:changing/services/media_export_service.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:changing/widgets/app_photo.dart';
import 'package:changing/widgets/common.dart';
import 'package:changing/widgets/slider_compare.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// 对比模式
enum CompareMode { slider, sideBySide, overlay }

/// U-08：归一化对比页初始左右下标（纯逻辑，便于单测）。
/// 传入 null 时退回首尾；越界裁剪到合法范围；左 >= 右（含相等）时退回首尾，
/// 保证「旧在前、新在后」且两张不同。
({int left, int right}) resolveCompareIndices({
  required int length,
  int? initLeft,
  int? initRight,
}) {
  if (length < 2) return (left: 0, right: 0);
  final last = length - 1;
  var l = (initLeft ?? 0).clamp(0, last);
  var r = (initRight ?? last).clamp(0, last);
  if (l >= r) {
    l = 0;
    r = last;
  }
  return (left: l, right: r);
}

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
    int? initLeft;
    int? initRight;
    if (args is Map) {
      _projectId = args['projectId'] as String?;
      // U-08：详情页迷你对比跳转时带上首尾初始 index
      initLeft = args['leftIndex'] as int?;
      initRight = args['rightIndex'] as int?;
    }
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
        final idx = resolveCompareIndices(
          length: list.length,
          initLeft: initLeft,
          initRight: initRight,
        );
        _leftIndex = idx.left;
        _rightIndex = idx.right;
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
                  // T-02：primary on bg 仅 2.74:1，改 primaryDark(3.82) + w600
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark),
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
          // U-04：标签精确到「第 N 次 · MM-DD」，同月多次记录也能分辨
          _RecordPickerRow(
            leftLabel: left.recordLabel(_leftIndex),
            rightLabel: right.recordLabel(_rightIndex),
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
    // U-04：视图内角标同样带序号 + 日期，与选择器文案一致
    final lLabel = left.recordLabel(_leftIndex);
    final rLabel = right.recordLabel(_rightIndex);

    switch (_mode) {
      case CompareMode.slider:
        return SliderCompare(
          leftFile: lFile,
          rightFile: rFile,
          leftLabel: lLabel,
          rightLabel: rLabel,
          pos: _sliderPos,
          fit: fit,
          onPos: (p) => setState(() => _sliderPos = p),
        );
      case CompareMode.sideBySide:
        return _SideBySideCompare(
          leftFile: lFile,
          rightFile: rFile,
          leftLabel: lLabel,
          rightLabel: rLabel,
          fit: fit,
        );
      case CompareMode.overlay:
        return _OverlayCompare(
          leftFile: lFile,
          rightFile: rFile,
          leftLabel: lLabel,
          rightLabel: rLabel,
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
                                // U-04：网格角标带序号，同月缩略图可区分
                                c.recordLabel(i),
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
            // U-04：标签变长（第 N 次 · MM-DD），窄屏允许折两行而非截断
            Flexible(
              child: Text(
                '$tag · $label',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppDimens.fontCaption(context),
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
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
        SliderDateLabel(text: leftLabel, alignment: Alignment.topLeft),
        SliderDateLabel(text: rightLabel, alignment: Alignment.topRight),
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
          SliderDateLabel(text: widget.leftLabel, alignment: Alignment.topLeft),
          SliderDateLabel(
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
