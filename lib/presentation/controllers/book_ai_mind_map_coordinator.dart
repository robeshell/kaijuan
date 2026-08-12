import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/ai_chat.dart';
import '../../ai/ai_mind_map.dart';
import 'book_ai_conversation_controller.dart';
import 'book_ai_mind_map_controller.dart';

typedef BookAiMindMapScopeChoice = ({int value, String label, String subtitle});

class BookAiMindMapScopePrompt {
  BookAiMindMapScopePrompt({required this.title, required this.choices});

  final String title;
  final List<BookAiMindMapScopeChoice> choices;
  final Completer<int?> completer = Completer<int?>();
  int? selectedValue;
}

class BookAiProductActionPrompt {
  BookAiProductActionPrompt({
    required this.proposalId,
    required this.title,
    required this.summary,
    this.scopeLabel,
    this.targetLabel,
    this.revisionLabel,
    this.externalWrite = false,
  });

  final String proposalId;
  final String title;
  final String summary;
  final String? scopeLabel;
  final String? targetLabel;
  final String? revisionLabel;
  final bool externalWrite;
  final Completer<bool?> completer = Completer<bool?>();
  bool? selected;
}

/// Owns native mind-map attachment, reveal, pointer, layout, and scope-choice
/// interaction state for the book AI workspace.
class BookAiMindMapCoordinator extends ChangeNotifier {
  BookAiMindMapCoordinator({
    required this.conversation,
    required this.mindMapConversation,
    required this.currentWorkKey,
    required this.persist,
  });

  final BookAiConversationController conversation;
  final BookAiMindMapController mindMapConversation;
  final String? Function() currentWorkKey;
  final Future<void> Function() persist;

  String? _revealArtifactId;
  bool _pointerActive = false;
  Timer? _pointerIdleTimer;
  BookAiMindMapScopePrompt? _scopePrompt;
  BookAiProductActionPrompt? _actionPrompt;

  String? get revealArtifactId => _revealArtifactId;
  bool get pointerActive => _pointerActive;
  BookAiMindMapScopePrompt? get scopePrompt => _scopePrompt;
  BookAiProductActionPrompt? get actionPrompt => _actionPrompt;
  String? get activeArtifactId => mindMapConversation.attachedArtifactId;

  AiBookMindMap? get activeMindMap {
    final id = activeArtifactId;
    return id == null ? null : mapForArtifact(id);
  }

  AiBookMindMap? mapForArtifact(String artifactId) {
    for (final message
        in conversation.session.messagesFor(currentWorkKey()).reversed) {
      final map = message.mindMap;
      if (map == null) continue;
      if (artifactIdFor(message, map) == artifactId) return map;
    }
    return null;
  }

  String artifactIdFor(AiChatMessage message, AiBookMindMap map) =>
      map.artifactId ?? message.turnId ?? 'mind-map:${map.scopeFingerprint}';

  bool beginEditing(AiChatMessage message, {required bool enabled}) {
    final map = message.mindMap;
    if (map == null || !enabled) return false;
    mindMapConversation.attachArtifact(artifactIdFor(message, map));
    return true;
  }

  void detachArtifact() => mindMapConversation.detachArtifact();

  void setPointerActive(bool active) {
    // Debounce leave events: MouseRegion enter/exit fires around dense node
    // cards and was swapping ListView physics every frame → whole-panel jump.
    _pointerIdleTimer?.cancel();
    if (active) {
      if (_pointerActive) return;
      _pointerActive = true;
      notifyListeners();
      return;
    }
    _pointerIdleTimer = Timer(const Duration(milliseconds: 120), () {
      if (!_pointerActive) return;
      _pointerActive = false;
      notifyListeners();
    });
  }

  void reveal(String artifactId) {
    _revealArtifactId = artifactId;
    notifyListeners();
  }

  void consumeReveal(AiChatMessage message) {
    if (_revealArtifactId != message.turnId &&
        _revealArtifactId != message.mindMap?.artifactId) {
      return;
    }
    _revealArtifactId = null;
    notifyListeners();
  }

  Future<int?> requestScope({
    required String title,
    required List<BookAiMindMapScopeChoice> choices,
    VoidCallback? onOpened,
  }) async {
    cancelScope();
    final prompt = BookAiMindMapScopePrompt(title: title, choices: choices);
    _scopePrompt = prompt;
    notifyListeners();
    onOpened?.call();
    final selected = await prompt.completer.future;
    if (identical(_scopePrompt, prompt)) {
      _scopePrompt = null;
      notifyListeners();
    }
    return selected;
  }

  void selectScope(int value) {
    final prompt = _scopePrompt;
    if (prompt == null || prompt.completer.isCompleted) return;
    prompt.selectedValue = value;
    notifyListeners();
    prompt.completer.complete(value);
  }

  void cancelScope() {
    final prompt = _scopePrompt;
    if (prompt == null) return;
    if (!prompt.completer.isCompleted) prompt.completer.complete(null);
    _scopePrompt = null;
    notifyListeners();
  }

  Future<bool?> requestActionConfirmation({
    required String proposalId,
    required String title,
    required String summary,
    String? scopeLabel,
    String? targetLabel,
    String? revisionLabel,
    bool externalWrite = false,
    VoidCallback? onOpened,
  }) async {
    cancelActionPrompt();
    final prompt = BookAiProductActionPrompt(
      proposalId: proposalId,
      title: title,
      summary: summary,
      scopeLabel: scopeLabel,
      targetLabel: targetLabel,
      revisionLabel: revisionLabel,
      externalWrite: externalWrite,
    );
    _actionPrompt = prompt;
    notifyListeners();
    onOpened?.call();
    final result = await prompt.completer.future;
    if (identical(_actionPrompt, prompt)) {
      _actionPrompt = null;
      notifyListeners();
    }
    return result;
  }

  void selectActionConfirmation(bool approved) {
    final prompt = _actionPrompt;
    if (prompt == null || prompt.completer.isCompleted) return;
    prompt.selected = approved;
    notifyListeners();
    prompt.completer.complete(approved);
  }

  void cancelActionPrompt() {
    final prompt = _actionPrompt;
    if (prompt == null) return;
    if (!prompt.completer.isCompleted) prompt.completer.complete(null);
    _actionPrompt = null;
    notifyListeners();
  }

  void updateLayout(AiChatMessage message, AiMindMapLayout layout) {
    final sourceMap = message.mindMap;
    if (sourceMap == null) return;
    final workKey = currentWorkKey();
    final session = conversation.session;
    final messages = List<AiChatMessage>.from(session.messagesFor(workKey));
    var index = messages.indexWhere(
      (candidate) => identical(candidate, message),
    );
    if (index < 0 && message.turnId != null) {
      index = messages.lastIndexWhere(
        (candidate) =>
            candidate.role == message.role &&
            candidate.turnId == message.turnId &&
            candidate.mindMap?.scopeFingerprint == sourceMap.scopeFingerprint,
      );
    }
    if (index < 0) return;
    final currentMap = messages[index].mindMap;
    if (currentMap == null || currentMap.layout == layout) return;
    messages[index] = messages[index].copyWith(
      mindMap: currentMap.copyWith(layout: layout),
    );
    conversation.hydrate(session.withMessagesFor(workKey, messages));
    notifyListeners();
    unawaited(persist());
  }

  @override
  void dispose() {
    _pointerIdleTimer?.cancel();
    cancelScope();
    cancelActionPrompt();
    super.dispose();
  }
}
