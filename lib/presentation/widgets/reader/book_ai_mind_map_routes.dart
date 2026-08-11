import 'package:flutter/material.dart';

import '../../../ai/ai_chat.dart';
import '../../../ai/ai_mind_map.dart';
import '../../controllers/book_ai_mind_map_coordinator.dart';
import '../../controllers/book_reader_controller.dart';
import 'book_ai_mind_map_fullscreen.dart';

/// Native navigation for mind-map artifacts and their reader evidence links.
abstract final class BookAiMindMapRoutes {
  static void openFullscreen(
    BuildContext context, {
    required AiChatMessage message,
    required BookAiMindMapCoordinator coordinator,
    required ValueChanged<AiMindMapEvidence> onOpenEvidence,
  }) {
    final map = message.mindMap;
    if (map == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookAiMindMapFullscreen(
          title: map.root.title.isEmpty ? '思维导图' : map.root.title,
          map: map,
          onLayoutChanged: (layout) =>
              coordinator.updateLayout(message, layout),
          onOpenEvidence: onOpenEvidence,
        ),
      ),
    );
  }

  static void openEvidence(
    BuildContext context, {
    required BookReaderController reader,
    required AiMindMapEvidence evidence,
  }) {
    final index = evidence.sectionIndex - 1;
    if (index < 0 || index >= reader.sectionCount) return;
    reader.goToSection(index, progressInSection: evidence.progressInSection);
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
    });
  }
}
