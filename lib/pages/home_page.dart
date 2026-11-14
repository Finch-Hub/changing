import 'package:changing/models/models.dart';
import 'package:changing/pages/mine_page.dart';
import 'package:changing/providers/project_repository.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:changing/widgets/common.dart';
import 'package:changing/widgets/project_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// 首页「记录」—— 项目列表
/// 对应 PRD 附录 C：驱动用户「回来拍」。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProjectRepository>();
    final projects = repo.projects;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _buildHome(repo, projects),
            // TabBar 中间是拍摄，IndexedStack 占位
            const SizedBox.shrink(),
            const _MinePlaceholder(),
          ],
        ),
      ),
      bottomNavigationBar: AppTabBar(
        currentIndex: _tabIndex,
        onTap: (i) {
          if (i == 1) {
            _goCapture();
            return;
          }
          setState(() => _tabIndex = i);
        },
      ),
    );
  }

  void _goCapture() {
    final repo = context.read<ProjectRepository>();
    final projects = repo.projects;
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建一个变化项目')),
      );
      return;
    }
    if (projects.length == 1) {
      Navigator.pushNamed(context, '/capture',
          arguments: {'projectId': projects.first.id});
      return;
    }
    // 多项目时让用户选择要记录的项目
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: projects.length,
          itemBuilder: (_, i) => ListTile(
            leading: const Icon(Icons.photo_camera_outlined,
                color: AppColors.primary),
            title: Text(projects[i].name),
            subtitle: Text('${projects[i].count} 张记录'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/capture',
                  arguments: {'projectId': projects[i].id});
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHome(ProjectRepository repo, List<Project> projects) {
    final margin = AppDimens.margin(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 导航区
        Padding(
          padding: EdgeInsets.fromLTRB(margin, 16, margin, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '观变',
                      style: TextStyle(
                        fontSize: AppDimens.fontDisplay(context),
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Everything is changing',
                      style: TextStyle(
                        fontSize: AppDimens.fontSmall(context),
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showCreateDialog(context),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
        ),
        // H3：项目数并入列表上方一行弱文字（原先独占一行 + 24 间距，
        // 头部三行压两行，首屏多露出约 40dp 给项目卡片）
        Padding(
          padding: EdgeInsets.fromLTRB(margin, 12, margin, 12),
          child: Text(
            '${projects.length} 个进行中的变化项目',
            style: TextStyle(
              fontSize: AppDimens.fontSmall(context),
              color: AppColors.textWeak,
            ),
          ),
        ),
        // 项目列表 / 空态
        Expanded(
          child: projects.isEmpty
              ? _EmptyState(onCreate: () => _showCreateDialog(context))
              : ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: margin),
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 24),
                  itemBuilder: (_, i) => ProjectCard(
                    project: projects[i],
                    lastRecordDate: repo.lastDateOf(projects[i].id),
                    onTap: () => _openProject(projects[i]),
                  ),
                ),
        ),
      ],
    );
  }

  void _openProject(Project project) {
    // 进入项目详情页（照片时间轴列表 + 删除/对比/拍照入口）
    Navigator.pushNamed(context, '/project',
        arguments: {'projectId': project.id});
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const CreateProjectDialog(),
    );
  }
}

/// 新建项目弹层
/// 对应 PRD FR-01 与附录 C「新建项目弹层」
class CreateProjectDialog extends StatefulWidget {
  const CreateProjectDialog({super.key});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _nameCtrl = TextEditingController();
  ProjectType _type = ProjectType.fitness;
  RecordFrequency _frequency = RecordFrequency.weekly;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
      ),
      title: Text(
        '新建变化项目',
        style: TextStyle(
          fontSize: AppDimens.fontTitle(context),
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      // 小屏设备（如 320x640）下内容会溢出，需可滚动 + 限制高度
      scrollable: true,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              style: TextStyle(fontSize: AppDimens.fontBody(context)),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '如：减脂 90 天',
                hintStyle: TextStyle(
                  fontSize: AppDimens.fontBody(context),
                  color: AppColors.textWeak,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 类型标签（固定 3 列等宽，整齐两行）
            _FieldLabel('类型'),
            const SizedBox(height: 8),
            _chipGrid(
              children: ProjectType.values.map((t) {
                final selected = t == _type;
                return _TagChip(
                  label: t.label,
                  selected: selected,
                  onTap: () {
                    // G6：类型选择轻触感
                    HapticFeedback.selectionClick();
                    setState(() => _type = t);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // 记录频率（固定 3 列等宽）
            _FieldLabel('记录频率'),
            const SizedBox(height: 8),
            _chipGrid(
              children: RecordFrequency.values.map((f) {
                final selected = f == _frequency;
                return _TagChip(
                  label: f.label,
                  selected: selected,
                  onTap: () {
                    // G6：频率选择轻触感
                    HapticFeedback.selectionClick();
                    setState(() => _frequency = f);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
                fontSize: AppDimens.fontBody(context),
                color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          // 名称为空时禁用（内联校验，替代原先被对话框挡住的 SnackBar）
          onPressed: _nameCtrl.text.trim().isEmpty
              ? null
              : () => _create(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(
            '创建',
            style: TextStyle(
                fontSize: AppDimens.fontBody(context), color: Colors.white),
          ),
        ),
      ],
    );
  }

  /// 固定 3 列等宽胶囊布局（替代 Wrap 的参差换行）
  Widget _chipGrid({required List<Widget> children}) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 3) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var j = i; j < i + 3; j++) ...[
                if (j > i) const SizedBox(width: 8),
                Expanded(
                  child: j < children.length
                      ? children[j]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return; // 按钮已禁用，双保险
    await context.read<ProjectRepository>().createProject(
          name: name,
          type: _type,
          frequency: _frequency,
        );
    if (mounted) Navigator.pop(context);
  }
}

/// 对话框内字段小标题（流式字号）
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppDimens.fontBody(context),
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// 对话框内可选标签（流式字号，紧凑尺寸）
class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.background,
          borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
          // 未选中态加描边，避免与对话框白底几乎无边界
          border: selected
              ? null
              : Border.all(color: AppColors.line, width: 1),
        ),
        // 小屏 3 列等宽下「自定义 / 不定期」可能超宽：
        // 用 scaleDown 整体缩字而不是截断成「自…」
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: AppDimens.fontBody(context),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.primaryDark : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 空态
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 80, color: AppColors.textWeak),
          const SizedBox(height: 16),
          Text(
            '还没有变化项目',
            style: TextStyle(
                fontSize: AppDimens.fontTitle(context),
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            '创建第一个项目，开始记录变化',
            style: TextStyle(
                fontSize: AppDimens.fontSmall(context),
                color: AppColors.textWeak),
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: '新建项目', onPressed: onCreate),
        ],
      ),
    );
  }
}

/// 「我的」占位（真实页面在 MinePage，IndexedStack 中显示）
class _MinePlaceholder extends StatelessWidget {
  const _MinePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const MinePlaceholderView();
  }
}
