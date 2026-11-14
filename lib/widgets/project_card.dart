import 'package:changing/models/models.dart';
import 'package:changing/theme/app_theme.dart';
import 'package:changing/widgets/app_photo.dart';
import 'package:flutter/material.dart';

/// 项目卡片（首页「记录」列表项）
/// 对应设计规格 §首页：封面 220 + 内容 140
class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;

  /// 最近一次记录时间（null 表示尚无记录）
  final DateTime? lastRecordDate;

  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    this.lastRecordDate,
  });

  @override
  Widget build(BuildContext context) {
    // 封面高度流式：随屏宽缩放（基准 220，小屏缩小、大屏放大）
    final coverHeight = 220.0 * AppDimens.scale(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
          // H2：轻阴影增加卡片层次（白卡不再「平贴」在米白底上）
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面（流式高度，类型渐变色占位 / 真实照片）
            SizedBox(
              height: coverHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  project.coverPath != null
                      ? AppPhoto(path: project.coverPath!)
                      : _TypeCover(type: project.type),
                  // H2：有封面时左上角叠加类型角标，保留类型信息
                  if (project.coverPath != null)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0x8C000000),
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusSmall),
                        ),
                        child: Text(
                          project.type.label,
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
            // 内容区
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppDimens.fontTitle(context),
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (project.streak > 0)
                        _StreakBadge(streak: project.streak),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _buildMeta(project),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppDimens.fontSmall(context),
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (project.monthMissed) ...[
                    const SizedBox(height: 8),
                    // H2：橙色小徽章替代纯文字，更醒目
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusSmall),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.notifications_active_outlined,
                              size: 13, color: AppColors.primaryDark),
                          const SizedBox(width: 4),
                          Text(
                            '本月未记录',
                            style: TextStyle(
                              fontSize: AppDimens.fontCaption(context),
                              fontWeight: FontWeight.w500,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildMeta(Project p) {
    final remind = p.remind != null ? ' · ${p.remind}提醒' : '';
    final last = lastRecordDate != null ? ' · ${_ago(lastRecordDate!)}' : '';
    return '${p.count} 张记录$last$remind';
  }

  /// 「最近记录：x 天前」的相对时间文案
  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 1) return '最近 ${diff.inDays} 天前';
    if (diff.inHours >= 1) return '最近 ${diff.inHours} 小时前';
    return '最近刚刚';
  }
}

class _TypeCover extends StatelessWidget {
  final ProjectType type;
  const _TypeCover({required this.type});

  @override
  Widget build(BuildContext context) {
    final palette = type.palette;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: Center(
        child: Text(
          type.label,
          style: TextStyle(
            fontSize: AppDimens.fontDisplay(context),
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 连续记录徽章
class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
      ),
      child: Text(
        '已连续 $streak 周',
        style: TextStyle(
          fontSize: AppDimens.fontCaption(context),
          fontWeight: FontWeight.w500,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}
