import 'dart:io';

import 'package:changing/models/models.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/services/media_export_service.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 照片详情查看页 —— 左右滑动浏览多张照片，双击/缩放查看大图 + 基础信息（时间、地理位置、备注）。
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({super.key});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  List<CheckIn> _checkIns = [];
  int _index = 0;

  final PageController _pageController = PageController();

  /// 每页独立的缩放控制器。
  /// 修复「往回翻页黑页」：原先所有页共享一个 GlobalKey + 一个
  /// TransformationController，GlobalKey 要求全局唯一，多页同时挂载时
  /// 相邻页的 InteractiveViewer 状态错乱，回翻即渲染成黑页。
  final Map<int, TransformationController> _transforms = {};

  /// 当前页是否处于放大态（仅用于 gating 单击切换面板）
  bool _currentZoomed = false;

  /// V2：顶栏 + 信息面板显隐（默认显示，单击照片切换）
  bool _showInfo = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  TransformationController _transformFor(int i) =>
      _transforms.putIfAbsent(i, () => TransformationController());

  Future<void> _load() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['checkIns'] is List && args['index'] is int) {
      _checkIns =
          (args['checkIns'] as List).whereType<CheckIn>().toList();
      _index = (args['index'] as int).clamp(0, _checkIns.length - 1);
      if (mounted) {
        setState(() {});
        // 定位到初始照片
        if (_checkIns.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_index);
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final t in _transforms.values) {
      t.dispose();
    }
    super.dispose();
  }

  /// V2：单击照片切换顶栏 + 信息面板（放大状态下不响应，避免误触）
  void _toggleInfo() {
    if (_currentZoomed) return;
    setState(() => _showInfo = !_showInfo);
  }

  /// V3：分享当前照片（调起系统分享面板）
  Future<void> _share() async {
    if (_checkIns.isEmpty) return;
    final c = _checkIns[_index];
    try {
      await MediaExportService.instance.shareFile(
        c.photoPath,
        text: '观变 · 变化记录',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享失败，请重试')),
        );
      }
    }
  }

  /// V3：删除当前照片（二次确认；删空则退出查看页）
  Future<void> _confirmDelete() async {
    if (_checkIns.isEmpty) return;
    final c = _checkIns[_index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
        ),
        title: const Text('删除这张照片？'),
        content: const Text('删除后不可恢复，确定删除？'),
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

    await context.read<ProjectRepository>().deleteCheckIn(c);
    if (!mounted) return;
    final removedIndex = _index;
    setState(() {
      _checkIns.removeAt(removedIndex);
      // 释放被删页及其后各页的缩放控制器（索引整体前移，旧控制器不再对应）
      for (final k in _transforms.keys.toList()) {
        if (k >= removedIndex) {
          _transforms.remove(k)!.dispose();
        }
      }
      if (_checkIns.isEmpty) return;
      if (_index >= _checkIns.length) _index = _checkIns.length - 1;
      _currentZoomed = false;
    });
    if (_checkIns.isEmpty) {
      Navigator.pop(context);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkIns.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final c = _checkIns[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      // V2：顶栏随单击显隐（沉浸式看大图）；V3：分享 / 删除入口
      appBar: _showInfo
          ? AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              title: Text(
                '${_index + 1} / ${_checkIns.length}',
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: '分享',
                  onPressed: _share,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除',
                  onPressed: _confirmDelete,
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          // 图片区铺满全屏（可左右滑动 + 双击缩放 + 单击切换面板）
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _checkIns.length,
              onPageChanged: (i) {
                setState(() {
                  _index = i;
                  _currentZoomed = false;
                });
              },
              itemBuilder: (_, i) => _ZoomablePhoto(
                // 每页独立 Key + 独立缩放控制器，回翻不再黑页
                key: ValueKey(_checkIns[i].id),
                checkIn: _checkIns[i],
                controller: _transformFor(i),
                onTap: _toggleInfo,
                onZoomChanged: (z) {
                  if (i == _index) _currentZoomed = z;
                },
              ),
            ),
          ),
          // V2：底部信息面板，单击照片时滑入/滑出
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: _showInfo ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _InfoPanel(checkIn: c),
            ),
          ),
          // V2：隐藏面板时给一个可点的「信息」入口，避免用户找不到恢复方式
          if (!_showInfo)
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: GestureDetector(
                onTap: () => setState(() => _showInfo = true),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0x8C000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.info_outline,
                      size: 22, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单页照片：自带 InteractiveViewer + 独立缩放控制器 + 双击围绕触点缩放。
/// 每页一个实例（ValueKey 区分），彼此状态隔离，修复回翻黑页。
class _ZoomablePhoto extends StatefulWidget {
  final CheckIn checkIn;
  final TransformationController controller;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePhoto({
    super.key,
    required this.checkIn,
    required this.controller,
    required this.onTap,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final GlobalKey _viewerKey = GlobalKey();
  Offset? _doubleTapPos;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTransform);
    super.dispose();
  }

  void _onTransform() {
    final z = widget.controller.value.getMaxScaleOnAxis() > 1.01;
    if (z != _zoomed) {
      _zoomed = z;
      widget.onZoomChanged(z);
    }
  }

  /// 双击切换放大/还原，放大围绕双击触点（而非左上角原点）。
  void _toggleZoom() {
    if (_zoomed) {
      widget.controller.value = Matrix4.identity();
    } else {
      const s = 2.5;
      final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
      final center = box != null && box.hasSize
          ? box.size.center(Offset.zero)
          : Offset.zero;
      final p = _doubleTapPos ?? center;
      // T(p) · S(s) · T(-p)：围绕触点 p 缩放 s 倍（手写矩阵，
      // 避免 vector_math 的 translate/scale 在新版被弃用）
      widget.controller.value = Matrix4(
        s, 0, 0, p.dx * (1 - s),
        0, s, 0, p.dy * (1 - s),
        0, 0, 1, 0,
        0, 0, 0, 1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        key: _viewerKey,
        transformationController: widget.controller,
        minScale: 1.0,
        maxScale: 5.0,
        child: Center(
          // G6：与详情页网格项配对的 Hero 过渡
          child: Hero(
            tag: 'photo_${widget.checkIn.id}',
            child: Image.file(
              File(widget.checkIn.photoPath),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    size: 64, color: Colors.white54),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部信息面板：时间 + 地理位置 + 备注
class _InfoPanel extends StatelessWidget {
  final CheckIn checkIn;

  const _InfoPanel({required this.checkIn});

  @override
  Widget build(BuildContext context) {
    String? locationText;
    if (checkIn.hasLocation) {
      final lat = checkIn.latitude!;
      final lng = checkIn.longitude!;
      final latDir = lat >= 0 ? 'N' : 'S';
      final lngDir = lng >= 0 ? 'E' : 'W';
      locationText = '${lat.abs().toStringAsFixed(5)}° $latDir, '
          '${lng.abs().toStringAsFixed(5)}° $lngDir';
    }
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: const BoxDecoration(
          color: Colors.black,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(context, Icons.schedule, '时间', _formatTime(checkIn.date)),
            if (checkIn.hasLocation) ...[
              const SizedBox(height: 10),
              _row(
                context,
                Icons.location_on_outlined,
                '位置',
                locationText ?? '未知位置',
              ),
            ],
            if (checkIn.note != null && checkIn.note!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _row(context, Icons.notes_outlined, '备注', checkIn.note!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white54),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppDimens.fontSmall(context) * 0.9,
              color: Colors.white54,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: AppDimens.fontSmall(context),
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
