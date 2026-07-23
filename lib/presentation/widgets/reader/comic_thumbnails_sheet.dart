import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../controllers/comic_reader_controller.dart';
import 'comic_page_image.dart';

/// Grid thumbnail sheet for jumping to a comic page.
Future<void> showComicThumbnailsSheet(
  BuildContext context, {
  required ComicReaderController controller,
}) {
  final theme = controller.readingTheme;
  final bg = Color(theme.backgroundArgb);
  final fg = theme.isDark ? const Color(0xFFF2F2F4) : const Color(0xFF1C1C1E);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: bg,
    showDragHandle: true,
    builder: (context) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final count = controller.pageCount;
          final current = controller.pageIndex;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.x4,
                      AppSpacing.x1,
                      AppSpacing.x4,
                      AppSpacing.x2,
                    ),
                    child: Text(
                      '页面',
                      style: TextStyle(
                        color: fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x3,
                        0,
                        AppSpacing.x3,
                        AppSpacing.x4,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: AppSpacing.x2,
                        crossAxisSpacing: AppSpacing.x2,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: count,
                      itemBuilder: (context, index) {
                        final selected = index == current;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              controller.jumpTo(index);
                              Navigator.of(context).pop();
                            },
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : fg.withValues(alpha: 0.2),
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ComicPageImage(
                                    controller: controller,
                                    pageIndex: index,
                                    fit: BoxFit.cover,
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: ColoredBox(
                                      color: Colors.black54,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                          horizontal: 4,
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
