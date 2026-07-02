import 'package:flutter/material.dart';

// 侧边栏单个项目组件
class HomeSidebarItem extends StatefulWidget {
  final IconData icon; // 图标
  final String? title; // 标题（可选）
  final bool isSelected; // 是否选中
  final VoidCallback onTap; // 点击事件

  const HomeSidebarItem({
    super.key,
    required this.icon,
    this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<HomeSidebarItem> createState() => _HomeSidebarItemState();
}

class _HomeSidebarItemState extends State<HomeSidebarItem> {
  bool _isHovered = false; // 鼠标悬停状态

  @override
  void didUpdateWidget(HomeSidebarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当选中状态发生变化时，重置悬停状态
    if (oldWidget.isSelected != widget.isSelected) {
      _isHovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // 当前主题
    final colorScheme = theme.colorScheme; // 颜色方案
    final colorConfig = _calculateColorConfig(context, colorScheme); // 颜色配置
    final double itemHeight = 52.0; // 高度

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0), // 外边距
      child: MouseRegion(
        // 鼠标悬停区域 - 已选中时禁用悬停效果
        onEnter: widget.isSelected
            ? null
            : (_) => setState(() => _isHovered = true),
        onExit: widget.isSelected
            ? null
            : (_) => setState(() => _isHovered = false),
        cursor: widget.isSelected
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.isSelected ? null : widget.onTap, // 已选中时禁用点击
          child: Stack(
            // 层叠布局
            alignment: Alignment.center,
            children: [
              _buildSelectedBackground(colorScheme, itemHeight), // 选中背景
              _buildHoverAndContentLayer(
                context,
                colorConfig,
                colorScheme,
                itemHeight,
              ), // 悬停与内容层
            ],
          ),
        ),
      ),
    );
  }

  _ColorConfig _calculateColorConfig(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    // 激活状态 - 优先级最高，忽略悬停状态
    if (widget.isSelected) {
      return _ColorConfig(
        backgroundColor: Colors.transparent,
        iconColor: colorScheme.onPrimary,
        textColor: colorScheme.primary,
        iconContainerColor: colorScheme.primary,
      );
    }

    // 未激活的悬停状态
    if (_isHovered) {
      return _ColorConfig(
        backgroundColor: colorScheme.onSurface.withAlpha(20),
        iconColor: Colors.white,
        textColor: colorScheme.onSurface,
        iconContainerColor: colorScheme.onSurface.withAlpha(153),
      );
    }

    // 未激活的默认状态
    return _ColorConfig(
      backgroundColor: Colors.transparent,
      iconColor: Colors.white,
      textColor: colorScheme.onSurface,
      iconContainerColor: colorScheme.onSurface.withAlpha(102),
    );
  }

  Widget _buildSelectedBackground(ColorScheme colorScheme, double height) {
    return AnimatedOpacity(
      // 透明度动画
      duration: const Duration(milliseconds: 100),
      opacity: widget.isSelected ? 1.0 : 0.0,
      child: Container(
        height: height,
        width: 200.0,
        decoration: BoxDecoration(
          color: colorScheme.primary.withAlpha((255 * 0.08).round()),
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }

  Widget _buildHoverAndContentLayer(
    BuildContext context,
    _ColorConfig colorConfig,
    ColorScheme colorScheme,
    double height,
  ) {
    // 定义尺寸常量
    const double itemWidth = 200.0;
    const double iconLeftPadding = 16.0;
    const double iconSize = 36.0;
    const double iconTotalWidth = iconLeftPadding + iconSize;
    const double textAreaWidth = itemWidth - iconTotalWidth;

    return AnimatedContainer(
      // 背景动画
      duration: const Duration(milliseconds: 75),
      curve: Curves.easeOut,
      height: height,
      width: itemWidth,
      decoration: BoxDecoration(
        color: colorConfig.backgroundColor,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          // 左侧图标区域
          Padding(
            padding: const EdgeInsets.only(left: iconLeftPadding),
            child: Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: colorConfig.iconContainerColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                size: 22.0,
                color: colorConfig.iconColor,
              ),
            ),
          ),
          // 右侧文字区域 - 在剩余宽度的 1/3 位置
          if (widget.title != null)
            SizedBox(
              width: textAreaWidth,
              child: Align(
                alignment: const Alignment(-0.33, 0.0),
                child: Text(
                  widget.title!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 14,
                    fontWeight: widget.isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    letterSpacing: _getLetterSpacing(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 根据当前语言获取合适的字母间距
  // 中文（简体、繁体）使用 3.0，其他语言使用 1.0
  double _getLetterSpacing(BuildContext context) {
    final currentLocale = Localizations.localeOf(context);
    final languageCode = currentLocale.languageCode;

    // 中文（简体 zh 和繁体 zh_Hant/zh_TW）使用较大的字母间距
    if (languageCode == 'zh') {
      return 3.0;
    }

    // 其他语言使用较小的字母间距
    return 1.0;
  }
}

class _ColorConfig {
  final Color backgroundColor; // 背景色
  final Color iconColor; // 图标颜色
  final Color textColor; // 文字颜色
  final Color iconContainerColor; // 图标容器颜色

  _ColorConfig({
    required this.backgroundColor,
    required this.iconColor,
    required this.textColor,
    required this.iconContainerColor,
  });
}
