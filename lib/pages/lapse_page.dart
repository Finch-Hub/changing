import 'dart:io';

import 'package:changing/models/models.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/services/lapse_service.dart';
import 'package:changing/services/media_export_service.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:changing/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

/// 缩时影片生成
/// 对应 PRD FR-04：一键把项目内所有记录点合成缩时影片。
class LapsePage extends StatefulWidget {
  const LapsePage({super.key});

  @override
  State<LapsePage> createState() => _LapsePageState();
}

class _LapsePageState extends State<LapsePage> {
  String? _projectId;
  Project? _project;
  List<CheckIn> _checkIns = [];
  bool _loading = true;
  bool _generating = false;

  // 选项
  String _range = '全部'; // 全部 / 最近3个月 / 自定义
  bool _withSubtitle = true;
  String _bgm = '无';

  /// L2：自定义时间范围（null 表示未选择）
  DateTimeRange? _customRange;

  /// L3：生成进度（0~1，null 表示未在生成）
  double? _progress;

  VideoPlayerController? _player;

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
    list.sort((a, b) => a.date.compareTo(b.date));
    setState(() {
      _checkIns = list;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  List<CheckIn> _filtered() {
    if (_range == '最近3个月') {
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      return _checkIns.where((c) => c.date.isAfter(cutoff)).toList();
    }
    if (_range == '自定义' && _customRange != null) {
      final start = DateTime(
          _customRange!.start.year, _customRange!.start.month, _customRange!.start.day);
      final end = DateTime(_customRange!.end.year, _customRange!.end.month,
              _customRange!.end.day)
          .add(const Duration(days: 1));
      return _checkIns
          .where((c) => !c.date.isBefore(start) && c.date.isBefore(end))
          .toList();
    }
    return _checkIns;
  }

  /// L2：选择自定义时间范围
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final first = _checkIns.isEmpty
        ? now.subtract(const Duration(days: 365))
        : _checkIns.first.date;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: first, end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _customRange = picked);
    }
  }

  /// L2：选择背景音乐（内置合成旋律，免版权）
  Future<void> _pickBgm() async {
    final picked = await showModalBottomSheet<String>(
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
                '背景音乐',
                style: TextStyle(
                  fontSize: AppDimens.fontBody(ctx),
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final name in const ['无', '轻快', '舒缓'])
              ListTile(
                leading: Icon(
                  name == '无'
                      ? Icons.music_off_outlined
                      : Icons.music_note_outlined,
                  color: name == _bgm
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                title: Text(name),
                trailing: name == _bgm
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, name),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _bgm = picked);
    }
  }

  Future<void> _generate() async {
    final list = _filtered();
    if (list.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记录不足，至少需要 2 张记录点')),
      );
      return;
    }
    setState(() {
      _generating = true;
      _progress = 0;
    });
    try {
      // L2：BGM 由服务内置合成（免版权），按选择传入风格
      final path = await LapseService.instance.generateLapse(
        checkIns: list,
        withSubtitle: _withSubtitle,
        bgmStyle: _bgm == '无' ? null : _bgm,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      setState(() {
        _generating = false;
        _progress = null;
      });
      await _initPlayer(path);
      // L4：写入系统相册，用户在相册里找得到
      final saved =
          await MediaExportService.instance.saveVideoToGallery(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved ? '缩时影片已保存到相册' : '缩时影片已生成'),
            action: SnackBarAction(
              label: '分享',
              onPressed: () => MediaExportService.instance.shareFile(
                path,
                text: '${_project?.name ?? '观变'} 的缩时影片',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _generating = false;
        _progress = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
    }
  }

  Future<void> _initPlayer(String path) async {
    _player?.dispose();
    _player = VideoPlayerController.file(File(path));
    await _player!.initialize();
    await _player!.setLooping(true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final projectName = _project?.name ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '生成缩时影片',
          style: TextStyle(
            fontSize: AppDimens.fontTitle(context),
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(projectName),
    );
  }

  Widget _buildContent(String projectName) {
    final margin = AppDimens.margin(context);
    final filtered = _filtered();

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 视频预览（L1：全宽 + 3:4 匹配输出比例）
          _VideoPreview(
            count: filtered.length,
            player: _player,
            generating: _generating,
            progress: _progress,
          ),
          const SizedBox(height: 24),
          // 时间范围
          _GroupLabel(label: '时间范围'),
          const SizedBox(height: 8),
          SegmentedSelector<String>(
            options: const ['全部', '最近3个月', '自定义'],
            selected: _range,
            labelOf: (s) => s,
            onSelect: (s) {
              setState(() => _range = s);
              // L2：选「自定义」立即弹日期范围选择器
              if (s == '自定义') _pickCustomRange();
            },
          ),
          // L2：自定义范围回显
          if (_range == '自定义') ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickCustomRange,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      BorderRadius.circular(AppDimens.radiusMedium),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range,
                        size: 18, color: AppColors.primaryDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _customRange == null
                            ? '点击选择起止日期'
                            : '${_fmtDate(_customRange!.start)} ~ '
                                '${_fmtDate(_customRange!.end)}',
                        style: TextStyle(
                          fontSize: AppDimens.fontSmall(context),
                          color: _customRange == null
                              ? AppColors.textWeak
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          // 选项
          _GroupLabel(label: '选项'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
            ),
            child: Column(
              children: [
                _OptionSwitch(
                  label: '日期字幕',
                  value: _withSubtitle,
                  onChanged: (v) => setState(() => _withSubtitle = v),
                ),
                const Divider(
                    height: 1, indent: 16, color: AppColors.background),
                _OptionValue(
                  label: '背景音乐',
                  value: _bgm,
                  onTap: _pickBgm,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 操作按钮
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: '预览',
                  icon: Icons.play_arrow,
                  onPressed: _player == null || !_player!.value.isInitialized
                      ? null
                      : () => _player!.play(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: PrimaryButton(
                  label: _generating ? '生成中…' : '生成并导出',
                  icon: Icons.movie_outlined,
                  onPressed: _generating ? null : _generate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  final int count;
  final VideoPlayerController? player;
  final bool generating;

  /// L3：生成进度（0~1）
  final double? progress;

  const _VideoPreview({
    required this.count,
    required this.player,
    required this.generating,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    // L1：全宽 + 3:4（与 FFmpeg 输出 1080×1440 一致），不再收缩成窄条
    return SizedBox(
      width: double.infinity,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (generating)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      progress == null
                          ? '正在合成…'
                          : '正在合成 ${(progress! * 100).round()}%',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white24,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                )
              else if (player != null && player!.value.isInitialized)
                Stack(
                  fit: StackFit.expand,
                  children: [
                    // L1：视频铺满预览框（FittedBox 裁切适配，消除黑边）
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: player!.value.size.width,
                        height: player!.value.size.height,
                        child: VideoPlayer(player!),
                      ),
                    ),
                    // L3：播放/暂停 + 进度条
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: const Color(0x66000000),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                player!.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                player!.value.isPlaying
                                    ? player!.pause()
                                    : player!.play();
                              },
                            ),
                            Expanded(
                              child: VideoProgressIndicator(
                                player!,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: AppColors.primary,
                                  bufferedColor: Colors.white38,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_circle_outline,
                        size: 64, color: Colors.white70),
                    const SizedBox(height: 8),
                    Text(
                      '$count 张记录 · 视频预览',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: AppDimens.fontBody(context)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日期短文案（yyyy-MM-dd）
String _fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: AppDimens.fontBody(context),
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _OptionSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _OptionSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: AppDimens.fontBody(context),
                  color: AppColors.textPrimary),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.switchOn,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _OptionValue extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _OptionValue(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: AppDimens.fontBody(context),
                    color: AppColors.textPrimary),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                  fontSize: AppDimens.fontBody(context),
                  color: AppColors.textSecondary),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textWeak),
          ],
        ),
      ),
    );
  }
}
