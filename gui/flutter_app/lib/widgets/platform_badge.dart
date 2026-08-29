import 'package:flutter/material.dart';

/// 平台元信息：显示名 / 品牌色 / 图标
class PlatformMeta {
  final String label;
  final Color color;
  final IconData icon;

  const PlatformMeta(this.label, this.color, this.icon);
}

const Map<String, PlatformMeta> kPlatformMeta = {
  'douyin': PlatformMeta('抖音', Color(0xFFFE2C55), Icons.music_note),
  'tiktok': PlatformMeta('TikTok', Color(0xFF010101), Icons.music_note),
  'bili': PlatformMeta('B站', Color(0xFFFB7299), Icons.live_tv),
  'youtube': PlatformMeta('YouTube', Color(0xFFE62117), Icons.smart_display_outlined),
  'update': PlatformMeta('更新', Color(0xFF4C8DFF), Icons.system_update_alt),
};

PlatformMeta platformMeta(String key) =>
    kPlatformMeta[key] ??
    const PlatformMeta('其他', Colors.grey, Icons.download);

/// 平台彩色小徽标（图标+名称）。TikTok 的纯黑在深色主题下不可读，自动换青色。
class PlatformBadge extends StatelessWidget {
  final String platform;
  final double fontSize;
  final double iconSize;
  final EdgeInsets padding;

  const PlatformBadge(
    this.platform, {
    super.key,
    this.fontSize = 11,
    this.iconSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  });

  @override
  Widget build(BuildContext context) {
    final meta = platformMeta(platform);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = platform == 'tiktok' && dark
        ? const Color(0xFF25F4EE)
        : meta.color;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: iconSize, color: color),
          const SizedBox(width: 3),
          Text(
            meta.label,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.0,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
