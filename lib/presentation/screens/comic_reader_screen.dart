import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/comic_reading_preferences.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/comic/comic_models.dart';
import '../controllers/comic_reader_controller.dart';
import '../widgets/reader/comic_reader_body.dart';
import '../widgets/reader/comic_reader_chrome.dart';

/// Full-screen comic reader host.
class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.database,
    required this.item,
    this.readingPreferences,
  });

  final AppDatabase database;
  final ReadingItem item;
  final ComicReadingPreferences? readingPreferences;

  static Future<void> open(
    BuildContext context, {
    required AppDatabase database,
    required ReadingItem item,
    ComicReadingPreferences? readingPreferences,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: false,
        builder: (_) => ComicReaderScreen(
          database: database,
          item: item,
          readingPreferences: readingPreferences,
        ),
      ),
    );
  }

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late final ComicReaderController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = ComicReaderController(
      database: widget.database,
      item: widget.item,
      readingPreferences: widget.readingPreferences,
    )..open();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Toolbar back / error-page back: always leave the reader.
  void _exitReader() {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      // Imperative [pop] — not [maybePop] — so PopScope.canPop cannot block.
      nav.pop();
    }
  }

  /// Escape: dismiss chrome first when visible, then leave.
  void _handleDismiss() {
    if (_controller.chromeVisible) {
      _controller.hideChrome();
      return;
    }
    _exitReader();
  }

  /// Semantic next/prev mapped through reading direction.
  void _turn({required bool forward}) {
    if (forward) {
      _controller.goForward();
    } else {
      _controller.goBackward();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rtl = _controller.direction == ComicReadDirection.rtl;

    if (key == LogicalKeyboardKey.escape) {
      _handleDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.pageDown) {
      _turn(forward: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _turn(forward: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _turn(forward: !rtl);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _turn(forward: rtl);
      return KeyEventResult.handled;
    }
    if (_controller.mode == ComicReaderMode.vertical) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _turn(forward: true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _turn(forward: false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final bg = Color(_controller.readingTheme.backgroundArgb);
          // Do not set canPop:false while chrome is open — that made toolbar
          // [maybePop] / some back paths only hide chrome. Esc still dismisses
          // chrome first via [_handleDismiss].
          return Scaffold(
            backgroundColor: bg,
            body: _buildBody(bg),
          );
        },
      ),
    );
  }

  Widget _buildBody(Color bg) {
    if (_controller.openError != null) {
      return _ErrorBody(
        message: _controller.openError.toString(),
        onBack: _exitReader,
      );
    }
    if (!_controller.isReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: bg),
        ComicReaderBody(controller: _controller),
        if (_controller.brightness < 0.999)
          IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(
                alpha: (1.0 - _controller.brightness).clamp(0.0, 1.0),
              ),
            ),
          ),
        IgnorePointer(
          ignoring: !_controller.chromeVisible,
          child: AnimatedOpacity(
            opacity: _controller.chromeVisible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: ComicReaderChrome(
              controller: _controller,
              onBack: _exitReader,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final macLead =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS ? 78.0 : 0.0;
    // Top inset from app MediaQuery; left clears traffic lights on macOS.
    return SafeArea(
      minimum: EdgeInsets.only(left: macLead),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onBack, child: const Text('返回')),
            ],
          ),
        ),
      ),
    );
  }
}
