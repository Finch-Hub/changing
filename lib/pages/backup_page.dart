import 'package:changing/models/models.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/services/backup_service.dart';
import 'package:changing/services/media_export_service.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 备份与恢复（数据批量导入 / 导出，换机迁移）
///
/// 导出：勾选项目 → 打包 `.changing` → 系统分享面板传出。
/// 导入：选备份包 → 预览（项目/照片/重复数）→ 选合并策略 → 落库刷新。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final BackupService _backup = BackupService.instance;

  bool _busy = false;
  String _busyLabel = '';
  double? _progress;

  void _setBusy(String label, [double? progress]) {
    setState(() {
      _busy = true;
      _busyLabel = label;
      _progress = progress;
    });
  }

  void _clearBusy() {
    setState(() {
      _busy = false;
      _busyLabel = '';
      _progress = null;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- 导出 ----------------

  Future<void> _startExport() async {
    final repo = context.read<ProjectRepository>();
    final projects = repo.projects;
    if (projects.isEmpty) {
      _toast('还没有可导出的项目');
      return;
    }
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _ExportSelectDialog(projects: projects),
    );
    if (selected == null || selected.isEmpty) return;
    await _runExport(selected);
  }

  Future<void> _runExport(Set<String> ids) async {
    _setBusy('正在打包备份…', 0);
    try {
      final file = await _backup.exportBackup(
        projectIds: ids,
        onProgress: (done, total) {
          if (mounted && total > 0) {
            setState(() => _progress = done / total);
          }
        },
      );
      _clearBusy();
      final sizeMb = (await file.length()) / 1024 / 1024;
      await MediaExportService.instance.shareFile(
        file.path,
        text: '观变备份包（${sizeMb.toStringAsFixed(1)} MB）',
      );
      _toast('备份已生成，请在分享面板中选择保存或发送方式');
    } on BackupException catch (e) {
      _clearBusy();
      _toast(e.message);
    } catch (_) {
      _clearBusy();
      _toast('导出失败，请重试');
    }
  }

  // ---------------- 导入 ----------------

  Future<void> _startImport() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    final path = file?.path;
    if (path == null) {
      if (file != null) _toast('无法读取所选文件');
      return;
    }

    _setBusy('正在解析备份包…');
    BackupPreview preview;
    try {
      preview = await _backup.previewBackup(path);
    } on BackupException catch (e) {
      _clearBusy();
      _toast(e.message);
      return;
    } catch (_) {
      _clearBusy();
      _toast('备份包解析失败，文件可能已损坏');
      return;
    }
    _clearBusy();

    if (!mounted) return;
    final choice = await showDialog<_ImportChoice>(
      context: context,
      builder: (_) => _ImportPreviewDialog(preview: preview),
    );
    if (choice == null) return;
    await _runImport(preview, choice.overwrite);
  }

  Future<void> _runImport(BackupPreview preview, bool overwrite) async {
    _setBusy('正在导入…', 0);
    try {
      final res = await _backup.importBackup(
        preview,
        overwrite: overwrite,
        onProgress: (done, total) {
          if (mounted && total > 0) {
            setState(() => _progress = done / total);
          }
        },
      );
      if (mounted) await context.read<ProjectRepository>().load();
      _clearBusy();
      final skipped =
          res.skippedProjects > 0 ? '，跳过 ${res.skippedProjects} 个重复项目' : '';
      _toast('导入完成：${res.importedProjects} 个项目 / '
          '${res.importedCheckIns} 条记录$skipped');
    } on BackupException catch (e) {
      _clearBusy();
      _toast(e.message);
    } catch (_) {
      _clearBusy();
      _toast('导入失败，请重试');
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final margin = AppDimens.margin(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('备份与恢复')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(margin, 8, margin, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '换手机时，用备份包把全部项目、照片与记录完整迁移到新设备。'
                '备份仅保存在你选择的位置，不会上传服务器。',
                style: TextStyle(
                  fontSize: AppDimens.fontSmall(context),
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              _ActionCard(
                icon: Icons.upload_file,
                title: '导出备份',
                subtitle: '打包项目与照片为 .changing 文件，分享到新手机或网盘',
                buttonLabel: '选择项目并导出',
                onPressed: _busy ? null : _startExport,
              ),
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.download_for_offline_outlined,
                title: '导入备份',
                subtitle: '选择旧手机导出的 .changing 文件，恢复到本机',
                buttonLabel: '选择备份文件',
                onPressed: _busy ? null : _startImport,
              ),
              if (_busy) ...[
                const SizedBox(height: 24),
                _BusyIndicator(label: _busyLabel, progress: _progress),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 功能卡片（图标 + 标题 + 说明 + 操作按钮）
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
                ),
                child: Icon(icon, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: AppDimens.fontTitle(context),
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: AppDimens.fontSmall(context),
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// 进度指示（确定进度条 / 不定进度条）
class _BusyIndicator extends StatelessWidget {
  final String label;
  final double? progress;
  const _BusyIndicator({required this.label, this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppDimens.fontSmall(context),
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.switchOff,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 导出项目选择弹窗（默认全选，可全选/清空）
class _ExportSelectDialog extends StatefulWidget {
  final List<Project> projects;
  const _ExportSelectDialog({required this.projects});

  @override
  State<_ExportSelectDialog> createState() => _ExportSelectDialogState();
}

class _ExportSelectDialogState extends State<_ExportSelectDialog> {
  late Set<String> _selected = widget.projects.map((e) => e.id).toSet();

  @override
  Widget build(BuildContext context) {
    final allSelected = _selected.length == widget.projects.length;
    return AlertDialog(
      title: const Text('选择要导出的项目'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '已选 ${_selected.length} / ${widget.projects.length}',
                  style: TextStyle(
                    fontSize: AppDimens.fontSmall(context),
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selected = allSelected
                          ? <String>{}
                          : widget.projects.map((e) => e.id).toSet();
                    });
                  },
                  child: Text(allSelected ? '清空' : '全选'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final proj in widget.projects)
                    CheckboxListTile(
                      value: _selected.contains(proj.id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(proj.id);
                          } else {
                            _selected.remove(proj.id);
                          }
                        });
                      },
                      title: Text(proj.name),
                      subtitle: Text(
                        '${proj.type.label} · ${proj.count} 条记录'
                        '${proj.archived ? ' · 已归档' : ''}',
                      ),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('导出'),
        ),
      ],
    );
  }
}

/// 导入预览弹窗的返回结果（是否覆盖重复项目）
class _ImportChoice {
  final bool overwrite;
  const _ImportChoice({required this.overwrite});
}

/// 导入预览弹窗（展示统计 + 重复提示 + 覆盖开关）
class _ImportPreviewDialog extends StatefulWidget {
  final BackupPreview preview;
  const _ImportPreviewDialog({required this.preview});

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  bool _overwrite = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.preview.manifest;
    final dup = widget.preview.duplicateProjectCount;
    final exported = m.exportedAt == null
        ? '未知时间'
        : '${m.exportedAt!.year}-${m.exportedAt!.month.toString().padLeft(2, '0')}-'
            '${m.exportedAt!.day.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: const Text('导入预览'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreviewRow(label: '项目数', value: '${widget.preview.projectCount} 个'),
            _PreviewRow(label: '记录数', value: '${widget.preview.checkInCount} 条'),
            _PreviewRow(label: '照片数', value: '${widget.preview.photos.length} 张'),
            _PreviewRow(label: '导出时间', value: exported),
            if (dup > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
                ),
                child: Text(
                  '本机已有 $dup 个相同项目。默认跳过重复，只导入新项目；'
                  '开启下方开关则用备份覆盖这些项目。',
                  style: TextStyle(
                    fontSize: AppDimens.fontCaption(context),
                    color: AppColors.primaryDark,
                    height: 1.5,
                  ),
                ),
              ),
              SwitchListTile(
                value: _overwrite,
                onChanged: (v) => setState(() => _overwrite = v),
                title: const Text('覆盖本机重复项目'),
                subtitle: const Text('关闭则跳过重复项目'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _ImportChoice(overwrite: _overwrite)),
          child: const Text('开始导入'),
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _PreviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppDimens.fontSmall(context),
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppDimens.fontSmall(context),
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}