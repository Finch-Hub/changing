import 'package:changing/providers/app_settings.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 「我的」页面
/// 对应 PRD FR-07 隐私保护、FR-08 商业化。
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final margin = AppDimens.margin(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(margin, 16, margin, 0),
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
                    // M3：品牌区三行压两行——英文 slogan 与中文 slogan 合并一行
                    const SizedBox(height: 4),
                    Text(
                      'Everything is changing · 定格当下，回看改变',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppDimens.fontSmall(context),
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 会员卡
              Padding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                child: _MemberCard(premium: settings.premium),
              ),
              const SizedBox(height: 24),
              // 存储与同步
              _SectionLabel(label: '存储与同步', margin: margin),
              _SettingsGroup(
                margin: margin,
                children: [
                  _SwitchCell(
                    icon: Icons.cloud_outlined,
                    label: '云端备份',
                    // M3：副文案显示上次备份时间 / 尚未备份
                    subtitle: settings.lastBackupAt == null
                        ? '尚未备份'
                        : '上次备份：${_formatBackupTime(settings.lastBackupAt!)}',
                    value: settings.cloudBackup,
                    onChanged: settings.setCloudBackup,
                  ),
                  // 数据批量导入 / 导出（换机迁移）
                  _NavCell(
                    icon: Icons.swap_horiz,
                    label: '备份与恢复',
                    onTap: () => Navigator.of(context).pushNamed('/backup'),
                  ),
                  // M2：未上线功能置灰 + 「即将上线」，不再留可点但无反应的行
                  _NavCell(
                    icon: Icons.lock_outline,
                    label: '隐私相册',
                    comingSoon: true,
                    onTap: () => _comingSoon(context, '隐私相册'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // 通用
              _SectionLabel(label: '通用', margin: margin),
              _SettingsGroup(
                margin: margin,
                children: [
                  _NavCell(
                    icon: Icons.notifications_outlined,
                    label: '提醒设置',
                    comingSoon: true,
                    onTap: () => _comingSoon(context, '提醒设置'),
                  ),
                  _SwitchCell(
                    icon: Icons.fingerprint,
                    label: '应用锁',
                    value: settings.appLock,
                    onChanged: settings.setAppLock,
                  ),
                  _NavCell(
                    icon: Icons.description_outlined,
                    label: '隐私政策与用户协议',
                    onTap: () => _showPrivacyPolicy(context),
                  ),
                ],
              ),
              // 底部留白：首页 TabBar 高约 98+，避免末项被遮挡
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

/// M3：备份时间格式化（同年省年份）
String _formatBackupTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final md = '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  if (d.year == DateTime.now().year) return md;
  return '${d.year}-$md';
}

/// M2：未上线功能点击反馈（替代死回调）
void _comingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$feature 即将上线，敬请期待')),
  );
}

/// M2：隐私政策与用户协议（内置文本页）
void _showPrivacyPolicy(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('隐私政策')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            '观变 · 隐私政策与用户协议\n\n'
            '一、数据存储\n'
            '观变采用本地优先策略：您的照片、项目与记录默认仅存储在设备本地，'
            '不会上传至任何服务器。云端备份为可选功能，需您手动开启并授权。\n\n'
            '二、权限说明\n'
            '· 相机：用于拍摄变化记录照片；\n'
            '· 相册：用于导入照片、保存导出的对比图与缩时影片；\n'
            '· 位置：仅从照片 EXIF 中读取拍摄位置（可选展示），不主动采集定位。\n\n'
            '三、数据删除\n'
            '删除项目将同时删除其全部照片文件，此操作不可恢复。'
            '卸载应用将清除全部本地数据。\n\n'
            '四、用户协议\n'
            '您应对自己拍摄、导入的内容负责，不得记录侵犯他人隐私或违反法律法规的内容。'
            '导出与分享功能产生的内容由您自行决定传播范围。\n\n'
            '五、联系我们\n'
            '如有隐私相关问题，请通过应用商店页面与我们联系。',
            style: TextStyle(
              fontSize: AppDimens.fontSmall(context),
              color: AppColors.textPrimary,
              height: 1.8,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 会员卡（渐变背景）
class _MemberCard extends StatelessWidget {
  final bool premium;
  const _MemberCard({required this.premium});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
      ),
      // 不设固定高度：小屏（如 320 宽）下「升级会员」按钮与文字横向挤不下会
      // 溢出，改为内容自适应高度，按钮在窄屏自动换到下一行
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 280;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // M3：头像 84 → 56dp，会员卡整体更紧凑；会员加皇冠标识
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '记',
                            style: TextStyle(
                              fontSize: AppDimens.fontTitle(context),
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      if (premium)
                        const Positioned(
                          right: -4,
                          top: -6,
                          child: Icon(Icons.workspace_premium,
                              size: 22, color: Color(0xFFE8B93C)),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          premium ? '会员版' : '免费版',
                          style: TextStyle(
                            fontSize: AppDimens.fontTitle(context),
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          premium ? '云端备份 · 无限项目' : '本地存储 · 3 个项目',
                          style: TextStyle(
                            fontSize: AppDimens.fontSmall(context),
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!premium && !compact)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusMedium),
                        border: Border.all(color: AppColors.primaryDark),
                      ),
                      child: Text(
                        '升级会员',
                        style: TextStyle(
                          fontSize: AppDimens.fontSmall(context),
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                ],
              ),
              // 窄屏：升级会员按钮换行放到底部
              if (!premium && compact) ...[
                const SizedBox(height: 12),
                Container(
                  alignment: Alignment.center,
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                    border: Border.all(color: AppColors.primaryDark),
                  ),
                  child: Text(
                    '升级会员',
                    style: TextStyle(
                      fontSize: AppDimens.fontSmall(context),
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final double margin;
  const _SectionLabel({required this.label, required this.margin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 0, margin, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppDimens.fontBody(context),
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final double margin;
  final List<Widget> children;
  const _SettingsGroup({required this.margin, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: margin),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 56, color: AppColors.background),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SwitchCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// M3：可选副文案（如云端备份的「上次备份：…」）
  final String? subtitle;

  const _SwitchCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: AppDimens.fontBody(context),
                      color: AppColors.textPrimary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                        fontSize: AppDimens.fontCaption(context),
                        color: AppColors.textWeak),
                  ),
                ],
              ],
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

class _NavCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// M2：未上线功能——置灰 + 「即将上线」角标，点击给 SnackBar 反馈
  final bool comingSoon;

  const _NavCell({
    required this.icon,
    required this.label,
    required this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon,
                color: comingSoon
                    ? AppColors.textWeak
                    : AppColors.textSecondary,
                size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: AppDimens.fontBody(context),
                    color: comingSoon
                        ? AppColors.textWeak
                        : AppColors.textPrimary),
              ),
            ),
            if (comingSoon)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '即将上线',
                  style: TextStyle(
                    fontSize: AppDimens.fontCaption(context),
                    color: AppColors.textWeak,
                  ),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.textWeak),
          ],
        ),
      ),
    );
  }
}

/// 供首页 IndexedStack 复用的「我的」视图（无 Scaffold/AppBar）
class MinePlaceholderView extends StatelessWidget {
  const MinePlaceholderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const MinePage();
  }
}
