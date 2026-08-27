import 'package:flutter/material.dart';

class SaveToChip extends StatelessWidget {
  final String? saveDir;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const SaveToChip({
    super.key,
    required this.saveDir,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final active = saveDir != null && saveDir!.isNotEmpty;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_open,
              size: 18,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              active ? saveDir! : '保存到：默认目录',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close, size: 14),
            ),
          ],
        ]),
      ),
    );
  }
}
