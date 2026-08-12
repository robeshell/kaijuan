import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../controllers/book_ai_mind_map_coordinator.dart';
import '../ai_typography.dart';

class BookAiActionConfirmationCard extends StatelessWidget {
  const BookAiActionConfirmationCard({
    required this.prompt,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  final BookAiProductActionPrompt prompt;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = prompt.selected;
    return Material(
      key: const ValueKey<String>('ai-product-action-confirmation-card'),
      color: colors.surfaceContainerHighest.withValues(alpha: 0.34),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              prompt.title,
              style: TextStyle(
                color: context.appPrimaryText,
                fontSize: context.aiBodySize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              prompt.summary,
              style: TextStyle(
                color: context.appSecondaryText,
                fontSize: context.aiDetailSize,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            if (selected == null)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onReject, child: const Text('取消')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: onApprove, child: const Text('确认生成')),
                ],
              )
            else
              Text(
                selected ? '已确认，正在准备正文…' : '已取消此操作',
                style: TextStyle(
                  color: context.appSecondaryText,
                  fontSize: context.appCaptionSize,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
