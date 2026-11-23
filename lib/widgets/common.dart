import 'package:changing/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 底部 TabBar（凸起主按钮）
/// 对应设计规格 §2 组件清单：TabBar（凸起主按钮）
class AppTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // U-07：总高 98 → 84，首屏多让出 14dp 给项目卡片（凸起快门仍 64dp）
      height: 84 + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          _TabItem(
            icon: Icons.auto_stories_outlined,
            label: '记录',
            selected: currentIndex == 0,
            onTap: () {
              // G6：Tab 切换轻触感
              HapticFeedback.selectionClick();
              onTap(0);
            },
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: () {
                  // G6：快门入口用中等强度触感，区别于普通 Tab
                  HapticFeedback.mediumImpact();
                  onTap(1);
                },
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    // T-02：中央圆用 primaryDark（白图标 4.09:1，达 UI 部件 3:1）
                    color: AppColors.primaryDark,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x33C95F1E),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
          _TabItem(
            icon: Icons.person_outline,
            label: '我的',
            selected: currentIndex == 2,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(2);
            },
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              // U-07：图标 26 → 24，配合 TabBar 收紧到 84dp
              size: 24,
              // T-01：未选中是可点击的导航项（非禁用态），用 textSecondary
              color: selected ? AppColors.primaryDark : AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: AppDimens.fontCaption(context),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color:
                    selected ? AppColors.primaryDark : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 胶囊分段选择器
/// 对应设计规格 §2：胶囊分段选择器（对比 / 缩时）
class SegmentedSelector<T> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;

  const SegmentedSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
      ),
      child: Row(
        children: options.map((o) {
          final isSelected = o == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                // G6：胶囊选中轻触感
                HapticFeedback.selectionClick();
                onSelect(o);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color:
                      isSelected ? AppColors.primaryLight : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(AppDimens.radiusLarge - 4),
                ),
                alignment: Alignment.center,
                child: Text(
                  labelOf(o),
                  style: TextStyle(
                    // T-02：选中态 primaryDark on primaryLight 3.57:1，
                    // 字号提到 18fp + w600 进大字档（3:1）达标
                    fontSize: isSelected
                        ? AppDimens.buttonFontSize
                        : AppDimens.fontBody(context),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.primaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 主按钮（橙实底白字）
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
        ),
        textStyle: const TextStyle(
            fontSize: AppDimens.buttonFontSize, fontWeight: FontWeight.w600),
      ),
      child: icon == null
          ? Text(label)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(label),
              ],
            ),
    );
  }
}

/// 次按钮（白底描边）
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        // T-04：描边由 textWeak 改 line + 实底填充，弱化「线框感」
        side: const BorderSide(color: AppColors.line),
        backgroundColor: AppColors.surface,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
        ),
        textStyle: const TextStyle(
            fontSize: AppDimens.buttonFontSize, fontWeight: FontWeight.w600),
      ),
      child: icon == null
          ? Text(label)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(label),
              ],
            ),
    );
  }
}
