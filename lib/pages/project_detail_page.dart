import 'dart:async';
import 'dart:io';

import 'package:changing/models/models.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:changing/widgets/app_photo.dart';
import 'package:changing/widgets/slider_compare.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 项目详情页 —— 展示项目下所有记录点的照片时间轴（缩略图列表 + 拍照时间）。
/// 顶部提供：删除项目、拍照、进入对比。
class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({super.key});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  String? _projectId;
  Project? _project;
  List<CheckIn> _checkIns = [];
  bool _loading = true;

  /// 照片网格每行列数（像手机相册一样可缩放调整，范围 2 ~ 6）
  int _columnCount = 3;

  /// D3：「双指缩放」提示是否显示（首次捏合或 5 秒后淡出）
  bool _showPinchHint = true;
  Timer? _hintTimer;

  /// D3：捏合调整列数后短暂浮现的「N 列」气泡
  bool _showColumnToast = false;
  Timer? _columnToastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showPinchHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _columnToastTimer?.cancel();
    super.dispose();
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
    // 按时间升序（旧在前），列表展示用「最新在前」更直观，故反转
    list.sort((a, b) => b.date.compareTo(a.date));
    setState(() {
      _checkIns = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectName = _project?.name ?? '项目详情';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          projectName,
          style: TextStyle(
            fontSize: AppDimens.fontTitle(context),
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          // 删除项目
          IconButton(
            icon:
                const Icon(Icons.delete_outline, color: AppColors.textPrimary),
            tooltip: '删除项目',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      // 底部操作：拍照 + 对比
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _checkIns.length < 2
                      ? null
                      : () => Navigator.pushNamed(context, '/compare',
                          arguments: {'projectId': _projectId}),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    // T-04：描边用 line，与 SecondaryButton 统一
                    side: const BorderSide(color: AppColors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMedium),
                    ),
                  ),
                  icon: const Icon(Icons.compare_outlined),
                  label: Text('对比',
                      style: TextStyle(fontSize: AppDimens.fontBody(context))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openCapture,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMedium),
                    ),
                  ),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text('拍照记录',
                      style: TextStyle(fontSize: AppDimens.fontBody(context))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_checkIns.isEmpty) {
      // U-08：空态用相机图标 + 三步引导，替代大灰图占半屏
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_camera_outlined,
                    size: 44, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 20),
              Text(
                '还没有记录点',
                style: TextStyle(
                    fontSize: AppDimens.fontTitle(context),
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '点击下方「拍照记录」开始记录变化',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppDimens.fontSmall(context),
                    // T-01：引导文案是信息文字，不用装饰色
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              const _ThreeStepGuide(),
            ],
          ),
        ),
      );
    }

    final margin = AppDimens.margin(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 统计头部 + 缩放列数提示
        Padding(
          padding: EdgeInsets.fromLTRB(margin, 8, margin, 12),
          child: Row(
            children: [
              Text(
                '共 ${_checkIns.length} 张记录',
                style: TextStyle(
                    fontSize: AppDimens.fontBody(context),
                    color: AppColors.textSecondary),
              ),
              const Spacer(),
              // D3：缩放到列数提示（5 秒或首次捏合后淡出，不再常驻）
              // D4：≤2 张走大卡片布局，捏合调列数无意义，不显示提示
              AnimatedOpacity(
                opacity: (_showPinchHint && _checkIns.length > 2) ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pinch,
                          size: 16, color: AppColors.primaryDark),
                      const SizedBox(width: 4),
                      Text(
                        '$_columnCount 列 · 双指缩放',
                        style: TextStyle(
                            fontSize: AppDimens.fontSmall(context),
                            color: AppColors.primaryDark),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 照片网格（多行多列，可捏合缩放调整列数）
        Expanded(
          child: Stack(
            children: [
              GestureDetector(
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onScaleEnd: _handleScaleEnd,
                child: _buildPhotoArea(margin),
              ),
              // D3：列数调整后的即时反馈气泡
              Positioned(
                left: 0,
                right: 0,
                top: 24,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showColumnToast ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xB3000000),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$_columnCount 列',
                          style: TextStyle(
                            fontSize: AppDimens.fontBody(context),
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
        ),
      ],
    );
  }

  /// D4：照片区按数量自适应——
  /// ≤2 张：大卡片（单张近全宽 / 两张并排），不再挤在小网格里；
  /// ≥12 张：按月分组 + 吸顶月份头，长列表滚动时始终知道在哪个月；
  /// 其余：常规网格（可捏合调列数）。
  ///
  /// U-08：2–11 张时照片往往只占半屏，下方大片死区。在照片区下方追加
  /// 「第一张 → 最近一张」迷你滑块对比（约 260dp），把死区变成变化叙事，
  /// 点击进入对比页并带上首尾两张的初始 index。
  Widget _buildPhotoArea(double margin) {
    if (_checkIns.length <= 2) {
      return _buildLargeCards(margin);
    }
    if (_checkIns.length >= 12) {
      return _buildMonthGrouped(margin);
    }
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: margin),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columnCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _checkIns.length,
          itemBuilder: (_, i) => _PhotoGridItem(
            checkIn: _checkIns[i],
            checkIns: _checkIns,
            index: i,
          ),
        ),
        // U-08：死区利用——首尾迷你对比（_checkIns 为降序：0 最新、last 最早）
        if (_checkIns.length >= 2) ...[
          const SizedBox(height: 24),
          _MiniComparePreview(
            oldest: _checkIns.last,
            newest: _checkIns.first,
            oldestLabel: _checkIns.last.recordLabel(0),
            newestLabel:
                _checkIns.first.recordLabel(_checkIns.length - 1),
            onOpen: () => Navigator.pushNamed(context, '/compare', arguments: {
              'projectId': _projectId,
              'leftIndex': 0,
              'rightIndex': _checkIns.length - 1,
            }),
          ),
        ],
      ],
    );
  }

  /// D4：少量照片大卡片布局
  /// U-08：2 张时同样在下方补迷你对比，填掉半屏死区
  Widget _buildLargeCards(double margin) {
    final single = _checkIns.length == 1;
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: margin),
      children: [
        if (single)
          AspectRatio(
            aspectRatio: 3 / 4,
            child: _PhotoGridItem(
              checkIn: _checkIns[0],
              checkIns: _checkIns,
              index: 0,
            ),
          )
        else
          Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: _PhotoGridItem(
                      checkIn: _checkIns[i],
                      checkIns: _checkIns,
                      index: i,
                    ),
                  ),
                ),
              ],
            ],
          ),
        if (!single) ...[
          const SizedBox(height: 24),
          _MiniComparePreview(
            oldest: _checkIns.last,
            newest: _checkIns.first,
            oldestLabel: _checkIns.last.recordLabel(0),
            newestLabel: _checkIns.first.recordLabel(_checkIns.length - 1),
            onOpen: () => Navigator.pushNamed(context, '/compare', arguments: {
              'projectId': _projectId,
              'leftIndex': 0,
              'rightIndex': _checkIns.length - 1,
            }),
          ),
        ],
      ],
    );
  }

  /// D4：≥12 张按月分组（最新月在前），月份头吸顶
  Widget _buildMonthGrouped(double margin) {
    // _checkIns 已按时间降序，顺序分组即「最新月在前」
    final groups = <_MonthGroup>[];
    for (var i = 0; i < _checkIns.length; i++) {
      final c = _checkIns[i];
      final key = '${c.date.year}-${c.date.month}';
      if (groups.isEmpty || groups.last.key != key) {
        groups.add(_MonthGroup(
          key: key,
          label: '${c.date.year} 年 ${c.date.month} 月',
          startIndex: i,
          items: [],
        ));
      }
      groups.last.items.add(i);
    }

    return CustomScrollView(
      slivers: [
        for (final g in groups)
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _MonthHeaderDelegate(
                  label: g.label,
                  count: g.items.length,
                  margin: margin,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(margin, 0, margin, 12),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columnCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, j) {
                      final i = g.items[j];
                      return _PhotoGridItem(
                        checkIn: _checkIns[i],
                        checkIns: _checkIns,
                        index: i,
                      );
                    },
                    childCount: g.items.length,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// 双指捏合缩放，动态调整每行列数（2 ~ 6 列）
  /// 记录手势过程中的缩放方向，在手势结束时一次性调整一列，体验接近系统相册。
  double _lastScale = 1.0;

  void _handleScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    // 累积缩放，仅记录方向（放大 or 缩小），不在此处 setState 避免抖动
    _lastScale = details.scale;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    // 手势结束：按净缩放方向调整一列
    var changed = false;
    if (_lastScale > 1.15) {
      if (_columnCount > 2) {
        _columnCount--;
        changed = true;
      }
    } else if (_lastScale < 0.85) {
      if (_columnCount < 6) {
        _columnCount++;
        changed = true;
      }
    }
    if (!changed) return;
    // D3：首次捏合后隐藏常驻提示，并浮现「N 列」气泡反馈
    _hintTimer?.cancel();
    _columnToastTimer?.cancel();
    setState(() {
      _showPinchHint = false;
      _showColumnToast = true;
    });
    _columnToastTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showColumnToast = false);
    });
  }

  Future<void> _openCapture() async {
    if (_projectId == null) return;
    // 等待拍照/导入页返回，然后刷新相册，确保能看到最新照片
    await Navigator.pushNamed(context, '/capture',
        arguments: {'projectId': _projectId});
    if (mounted) await _load();
  }

  Future<void> _confirmDelete() async {
    if (_projectId == null) return;
    final count = _checkIns.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
        ),
        title: const Text('删除项目'),
        content: Text(
          '将删除「${_project?.name ?? ''}」及其 $count 张照片记录，此操作不可恢复。确定删除？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<ProjectRepository>().deleteProject(_projectId!);
    if (mounted) Navigator.pop(context);
  }
}

/// U-08：空态三步引导「1 拍照 → 2 对齐 → 3 坚持」
class _ThreeStepGuide extends StatelessWidget {
  const _ThreeStepGuide();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.photo_camera_outlined, '拍照'),
      (Icons.center_focus_strong_outlined, '对齐'),
      (Icons.trending_up, '坚持'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward,
                  size: 14, color: AppColors.textWeak),
            ),
          Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.fieldFill,
                  borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                ),
                child: Icon(steps[i].$1,
                    size: 22, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Text(
                '${i + 1} ${steps[i].$2}',
                style: TextStyle(
                  fontSize: AppDimens.fontSmall(context),
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// U-08：迷你滑块对比预览——把「照片少时的半屏死区」变成变化叙事。
/// 复用对比页的 [SliderCompare]，可直接拖动扫视首尾差异；
/// 点标题行进入完整对比页（带首尾初始 index）。
class _MiniComparePreview extends StatefulWidget {
  final CheckIn oldest;
  final CheckIn newest;
  final String oldestLabel;
  final String newestLabel;
  final VoidCallback onOpen;

  const _MiniComparePreview({
    required this.oldest,
    required this.newest,
    required this.oldestLabel,
    required this.newestLabel,
    required this.onOpen,
  });

  @override
  State<_MiniComparePreview> createState() => _MiniComparePreviewState();
}

class _MiniComparePreviewState extends State<_MiniComparePreview> {
  double _pos = 0.5;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows,
                    size: 18, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '看看变化 · 第一张 → 最近一张',
                    style: TextStyle(
                      fontSize: AppDimens.fontBody(context),
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '完整对比',
                  style: TextStyle(
                    fontSize: AppDimens.fontSmall(context),
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textWeak),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
          child: SizedBox(
            height: 260,
            width: double.infinity,
            child: SliderCompare(
              leftFile: File(widget.oldest.photoPath),
              rightFile: File(widget.newest.photoPath),
              leftLabel: widget.oldestLabel,
              rightLabel: widget.newestLabel,
              pos: _pos,
              fit: BoxFit.cover,
              onPos: (p) => setState(() => _pos = p),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '左右拖动分隔线，扫视这段时间的变化',
          style: TextStyle(
            fontSize: AppDimens.fontSmall(context),
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// D4：月份分组（key 用于相邻合并，startIndex 保留组内首张的全局索引）
class _MonthGroup {
  final String key;
  final String label;
  final int startIndex;
  final List<int> items;
  _MonthGroup({
    required this.key,
    required this.label,
    required this.startIndex,
    required this.items,
  });
}

/// D4：吸顶月份头（背景与页面同色，滚动时不露出下方照片）
class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final int count;
  final double margin;
  _MonthHeaderDelegate({
    required this.label,
    required this.count,
    required this.margin,
  });

  static const double _height = 40;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: _height,
      color: AppColors.background,
      padding: EdgeInsets.symmetric(horizontal: margin),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppDimens.fontBody(context),
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count 张',
            style: TextStyle(
              fontSize: AppDimens.fontSmall(context),
              // T-01：月分组张数是信息文字
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MonthHeaderDelegate oldDelegate) =>
      oldDelegate.label != label ||
      oldDelegate.count != count ||
      oldDelegate.margin != margin;
}

/// 照片网格项：正方形缩略图 + 底部时间条
class _PhotoGridItem extends StatelessWidget {
  final CheckIn checkIn;
  final List<CheckIn> checkIns;
  final int index;
  const _PhotoGridItem({
    required this.checkIn,
    required this.checkIns,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 单击即打开查看页（对齐系统相册肌肉记忆；双击保留兼容）
      onTap: () {
        Navigator.pushNamed(context, '/photo_viewer',
            arguments: {'checkIns': checkIns, 'index': index});
      },
      onDoubleTap: () {
        Navigator.pushNamed(context, '/photo_viewer',
            arguments: {'checkIns': checkIns, 'index': index});
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 缩略图（统一容错组件）；G6：Hero 与查看页配对，点按放大过渡
            Hero(
              tag: 'photo_${checkIn.id}',
              child: AppPhoto(path: checkIn.photoPath),
            ),
            // D2：有备注的照片右上角加角标
            if (checkIn.note != null && checkIn.note!.isNotEmpty)
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.sticky_note_2,
                    size: 16, color: Colors.white),
              ),
            // 底部时间条（渐变遮罩，保证文字可读）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x99000000)],
                  ),
                ),
                child: Text(
                  _formatTime(checkIn.date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDimens.fontCaption(context),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// D2：网格内只显示「MM-DD」（同年省年份），完整时间留给查看页
  String _formatTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final md = '${two(d.month)}-${two(d.day)}';
    if (d.year == DateTime.now().year) return md;
    return '${d.year}-$md';
  }
}
