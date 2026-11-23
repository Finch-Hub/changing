import 'package:changing/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// 「我的」页面
/// 对应 PRD FR-07 隐私保护、FR-08 商业化。
///
/// U-01/02/03（UI 改动报告 2026-11-23）：本页只呈现「真实存在的能力」。
/// 会员订阅 / 云端备份 / 应用锁均无后端实现，统一按 comingSoon 条目展示，
/// 不再提供点击无反应的胶囊按钮或「开了却不生效」的开关。
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
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
              // 会员卡（U-01：只展示真实的本地存储能力）
              Padding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                child: const _MemberCard(),
              ),
              const SizedBox(height: 24),
              // 存储与同步
              _SectionLabel(label: '存储与同步', margin: margin),
              _SettingsGroup(
                margin: margin,
                children: [
                  // U-02：云端备份无后端实现，空开关会误导用户以为照片已安全。
                  // 降级为「即将上线」条目；真实的换机迁移走下方「备份与恢复」。
                  _NavCell(
                    icon: Icons.cloud_outlined,
                    label: '云端备份',
                    comingSoon: true,
                    onTap: () => _comingSoon(context, '云端备份'),
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
                  // U-03：应用锁未接 local_auth，开启后并不拦截，降为「即将上线」。
                  _NavCell(
                    icon: Icons.fingerprint,
                    label: '应用锁',
                    comingSoon: true,
                    onTap: () => _comingSoon(context, '应用锁'),
                  ),
                  _NavCell(
                    icon: Icons.description_outlined,
                    label: '隐私政策与用户协议',
                    onTap: () => _showPrivacyPolicy(context),
                  ),
                ],
              ),
              // 底部留白：首页 TabBar 高约 84+安全区（U-07），避免末项被遮挡
              const SizedBox(height: 108),
            ],
          ),
        ),
      ),
    );
  }
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

/// 账户卡（渐变背景）
///
/// U-01：会员订阅尚未接入（`in_app_purchase` 仅存在于 pubspec），
/// 「升级会员」胶囊与「云端备份 · 无限项目 / 3 个项目」权益文案均无代码支撑，
/// 一并删除。卡片只陈述真实能力：本地存储、不限项目数量。
class _MemberCard extends StatelessWidget {
  const _MemberCard();

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
      child: Row(
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
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的记录',
                  style: TextStyle(
                    fontSize: AppDimens.fontTitle(context),
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '本地存储 · 不限项目',
                  style: TextStyle(
                    fontSize: AppDimens.fontSmall(context),
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
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
                // T-01：comingSoon 行仍可点击（有 SnackBar 反馈），非禁用态，
                // 图标统一 textSecondary 保证 3:1 可辨
                color: AppColors.textSecondary,
                size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: AppDimens.fontBody(context),
                    color: comingSoon
                        ? AppColors.textSecondary
                        : AppColors.textPrimary),
              ),
            ),
            if (comingSoon)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.fieldFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '即将上线',
                  style: TextStyle(
                    fontSize: AppDimens.fontCaption(context),
                    // T-01：状态标签是信息文字
                    color: AppColors.textSecondary,
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
