import 'dart:io';

import 'package:camera/camera.dart';
import 'package:changing/data/file_store.dart';
import 'package:changing/models/models.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/services/location_service.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

/// 对齐拍照页
/// 对应 PRD FR-02：拍摄时显示上一张记录点的半透明参考图虚影，对齐构图。
class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  int _cameraIndex = 0;

  /// 参考图开关（默认开启）
  bool _showGhost = true;

  /// 参考图透明度（0.0 ~ 1.0）
  double _ghostOpacity = 0.18;

  /// P4：构图辅助线开关（默认开启）
  bool _showGrid = true;

  String? _projectId;
  Project? _project;
  CheckIn? _reference; // 上一张记录点（参考图）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // 读取路由参数
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _projectId = args['projectId'] as String?;
      }
      if (_projectId != null) {
        final repo = context.read<ProjectRepository>();
        _project = repo.byId(_projectId!);
        _reference = await repo.latestCheckIn(_projectId!);
        if (mounted) setState(() {});
      }
      await _initCamera();
    });
  }

  Future<void> _initCamera({int? index}) async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _initializing = false);
        return;
      }
      if (index == null) {
        // 首次打开：优先后置摄像头
        final backIndex = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = backIndex >= 0 ? backIndex : 0;
      } else {
        _cameraIndex = index;
      }
      _controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _initializing = false);
    } catch (e) {
      if (mounted) setState(() => _initializing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      c?.dispose();
      _controller = null;
      if (mounted) setState(() => _initializing = true);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// P3：关闭前二次确认，避免误触丢失本次拍摄
  Future<void> _confirmClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃本次拍摄？'),
        content: const Text('关闭后本次取景不会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续拍摄'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context);
  }

  /// 切换前后摄像头
  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _initializing = true);
    await _controller?.dispose();
    _controller = null;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initCamera(index: _cameraIndex);
  }

  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _projectId == null) return;
    try {
      final file = await c.takePicture();
      await _recordPhoto(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('拍照失败，请重试')),
        );
      }
    }
  }

  /// 从相册导入照片作为本次记录
  Future<void> _importPhoto() async {
    if (_projectId == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (picked == null) return; // 用户取消
      await _recordPhoto(picked.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入照片失败，请重试')),
        );
      }
    }
  }

  /// 记录照片公共流程：可选备注 -> 定位 -> 持久化 -> 入库 -> 关闭相机
  Future<void> _recordPhoto(String sourcePath) async {
    final repo = context.read<ProjectRepository>();
    final projectId = _projectId!;

    // 1. 可选备注（P3：跳过备注也保存照片，不再丢照片）
    final note = await _askNote();

    // 2. 复制到 FileStore 持久目录
    final checkInId = const Uuid().v4();
    final persistentPath =
        await FileStore.instance.photoPath(projectId, checkInId);
    await File(sourcePath).copy(persistentPath);
    // 若来源是缓存目录（拍照），删除临时文件
    if (sourcePath != persistentPath) {
      try {
        await File(sourcePath).delete();
      } catch (_) {}
    }

    // 3. 从照片 EXIF 读取 GPS 位置（无 GPS 信息则静默降级为 null）
    final loc = await LocationService.instance.readFromExif(persistentPath);

    // 4. 入库
    await repo.addCheckIn(
      projectId: projectId,
      date: DateTime.now(),
      photoPath: persistentPath,
      note: (note == null || note.isEmpty) ? null : note,
      latitude: loc?.latitude,
      longitude: loc?.longitude,
    );

    // 5. 关闭相机，返回详情页
    if (mounted) Navigator.pop(context);
  }

  /// 弹备注输入对话框，返回备注文本（null=跳过备注，照片仍保存）。
  /// P3：原「取消」会连同照片一起丢弃，用户本意往往只是不写备注；
  /// 现改为「跳过备注」（保存照片、note=null），返回键=跳过。
  /// 放弃本次拍摄请走顶部关闭按钮（有二次确认）。
  Future<String?> _askNote() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
        ),
        title: const Text('添加备注'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          style: TextStyle(fontSize: AppDimens.fontBody(ctx)),
          decoration: InputDecoration(
            hintText: '记录此刻的想法（可选）',
            hintStyle: TextStyle(
              fontSize: AppDimens.fontBody(ctx),
              color: AppColors.textWeak,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('跳过备注',
                style: TextStyle(
                    fontSize: AppDimens.fontBody(ctx),
                    color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Text('保存',
                style: TextStyle(
                    fontSize: AppDimens.fontBody(ctx), color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    // 从 repo 实时读取，拍照后 count 变化能即时反映在标题上
    final liveProject = _projectId == null
        ? null
        : context.watch<ProjectRepository>().byId(_projectId!);
    final projectName = liveProject?.name ?? _project?.name ?? '变化项目';
    final count = liveProject?.count ?? _project?.count ?? 0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 取景区（相机画面 / 未就绪占位）
          Positioned.fill(
            child: _buildViewfinder(),
          ),
          // 顶部渐变 scrim：保证标题/关闭在亮场景（过曝天空）下可读
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x73000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          // 底部渐变 scrim：保证快门区控件可读
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0x73000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          // 顶部栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$projectName · 第 ${count + 1} 次记录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppDimens.fontTitle(context),
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _confirmClose,
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 底部：参考图开关 + 快门
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 参考图开关 + 透明度 + 辅助线开关
                    _GhostControls(
                      showGhost: _showGhost,
                      opacity: _ghostOpacity,
                      showGrid: _showGrid,
                      onToggle: (v) => setState(() => _showGhost = v),
                      onOpacity: (v) => setState(() => _ghostOpacity = v),
                      onGridToggle: (v) => setState(() => _showGrid = v),
                    ),
                    const SizedBox(height: 16),
                    // 快门区
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CircleButton(
                          icon: Icons.photo_library_outlined,
                          onTap: _importPhoto,
                        ),
                        GestureDetector(
                          onTap: () {
                            // G6：快门中等强度触感，模拟实体按键确认感
                            HapticFeedback.mediumImpact();
                            _takePhoto();
                          },
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: Center(
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _CircleButton(
                          icon: Icons.refresh,
                          onTap: _switchCamera,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinder() {
    if (_initializing) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      // P2：失败兜底——重试 + 关闭，不再让用户卡死在一行文字上
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 56, color: Colors.white54),
            const SizedBox(height: 12),
            const Text(
              '相机未授权或打开失败',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              '请在系统设置中允许相机权限后重试',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() => _initializing = true);
                    _initCamera(index: _cameraIndex);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('重试'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(c),
        // 半透明参考图虚影（上一张照片）
        // P4：cover 与相机预览同基准——contain 会在两侧/上下留黑边，
        // 虚影与实时画面构图错位，失去对齐意义
        if (_showGhost && _reference != null)
          IgnorePointer(
            child: Opacity(
              opacity: _ghostOpacity,
              child: Image.file(
                File(_reference!.photoPath),
                fit: BoxFit.cover,
              ),
            ),
          ),
        // P4：构图辅助线（可开关）
        if (_showGrid) CustomPaint(painter: _CrosshairPainter()),
      ],
    );
  }
}

/// 参考图控制（开关 + 透明度滑条 + 辅助线开关）
class _GhostControls extends StatelessWidget {
  final bool showGhost;
  final double opacity;
  final bool showGrid;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onOpacity;
  final ValueChanged<bool> onGridToggle;

  const _GhostControls({
    required this.showGhost,
    required this.opacity,
    required this.showGrid,
    required this.onToggle,
    required this.onOpacity,
    required this.onGridToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.overlayDark,
        borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _switchRow(
            context,
            label: '参考图',
            value: showGhost,
            onChanged: onToggle,
          ),
          if (showGhost)
            Slider(
              value: opacity,
              min: 0.05,
              max: 0.6,
              activeColor: AppColors.primary,
              // P4：未激活轨道用白 24%，深色面板上不再几乎不可见
              inactiveColor: Colors.white24,
              onChanged: onOpacity,
            ),
          // P4：辅助线开关（与参考图开关并列，窄屏也不挤）
          _switchRow(
            context,
            label: '辅助线',
            value: showGrid,
            onChanged: onGridToggle,
          ),
        ],
      ),
    );
  }

  /// 深色面板专用开关行。
  /// 修复开关 UI：全局 Switch 主题是浅色（关闭态浅米轨道 + 白滑块），
  /// 直接放在深色面板上像两块突兀的浅色补丁。这里局部覆盖为深色适配——
  /// 开启=橙轨道白滑块、关闭=半透明白轨道 + 浅白滑块，并缩小尺寸更紧凑。
  Widget _switchRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: AppDimens.fontBody(context), color: Colors.white),
          ),
          const Spacer(),
          SwitchTheme(
            data: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : Colors.white70,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primary
                    : Colors.white24,
              ),
              trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            ),
            child: Transform.scale(
              scale: 0.8,
              child: Switch(
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 十字辅助线（头部 / 肩线 / 脚部对齐锚点）
class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.crosshair
      ..strokeWidth = 1.5;

    // 纵向中线
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    // 横向三等分线（肩线 / 脚部）
    for (var i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: AppColors.overlayDark,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}
