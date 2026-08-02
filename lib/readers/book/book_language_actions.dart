import 'package:flutter/services.dart';

/// Language operations exposed by the book reader.
///
/// The first two operations are available from the selection menu. The
/// whole-book operation is deliberately part of the contract now so a future
/// AI provider can be added without changing the reader UI contract.
enum BookLanguageOperation {
  dictionary,
  selectionTranslation,
  fullBookTranslation,
}

class BookLanguageRequest {
  const BookLanguageRequest({
    required this.operation,
    required this.text,
    this.itemId,
    this.cfi,
    this.sourceLanguage,
    this.targetLanguage,
  });

  final BookLanguageOperation operation;
  final String text;
  final String? itemId;
  final String? cfi;
  final String? sourceLanguage;
  final String? targetLanguage;
}

enum BookLanguageActionStatus { opened, unavailable, unsupported, failed }

class BookLanguageActionResult {
  const BookLanguageActionResult({
    required this.status,
    this.message,
    this.content,
  });

  const BookLanguageActionResult.opened()
    : status = BookLanguageActionStatus.opened,
      message = null,
      content = null;

  final BookLanguageActionStatus status;
  final String? message;

  /// Optional in-app result reserved for an AI provider.
  final String? content;

  bool get handled => status == BookLanguageActionStatus.opened;
}

/// Replaceable language backend used by [BookReaderController].
///
/// A future AI backend can return an in-app result instead of opening a
/// platform application. Keeping the request operation-based also leaves a
/// clean seam for full-book translation.
abstract interface class BookLanguageProvider {
  Future<BookLanguageActionResult> execute(BookLanguageRequest request);
}

/// Uses installed platform capabilities and does not make network requests.
class PlatformBookLanguageProvider implements BookLanguageProvider {
  const PlatformBookLanguageProvider();

  static const _channel = MethodChannel('com.kaijuan.reader/language');

  @override
  Future<BookLanguageActionResult> execute(BookLanguageRequest request) async {
    final text = request.text.trim();
    if (text.isEmpty) {
      return const BookLanguageActionResult(
        status: BookLanguageActionStatus.unavailable,
        message: '没有可查询的文字',
      );
    }

    final method = switch (request.operation) {
      BookLanguageOperation.dictionary => 'openDictionary',
      BookLanguageOperation.selectionTranslation => 'openTranslation',
      BookLanguageOperation.fullBookTranslation => null,
    };
    if (method == null) {
      return const BookLanguageActionResult(
        status: BookLanguageActionStatus.unsupported,
        message: '整本翻译将在 AI 功能接入后提供',
      );
    }

    try {
      final opened = await _channel.invokeMethod<bool>(method, {'text': text});
      if (opened == true) return const BookLanguageActionResult.opened();
      return BookLanguageActionResult(
        status: BookLanguageActionStatus.unavailable,
        message: request.operation == BookLanguageOperation.dictionary
            ? '当前设备没有可用的词典应用'
            : '当前设备没有可用的翻译能力',
      );
    } on MissingPluginException {
      return const BookLanguageActionResult(
        status: BookLanguageActionStatus.unsupported,
        message: '当前平台暂不支持词典和翻译',
      );
    } on PlatformException catch (error) {
      return BookLanguageActionResult(
        status: BookLanguageActionStatus.failed,
        message: error.message ?? '打开语言工具失败',
      );
    } catch (_) {
      return const BookLanguageActionResult(
        status: BookLanguageActionStatus.failed,
        message: '打开语言工具失败',
      );
    }
  }
}

/// Placeholder backend for the future AI integration.
///
/// It is intentionally not selected as the default backend yet. The AI layer
/// can later implement [BookLanguageProvider] for both selected text and a
/// full-book translation task.
class AiBookLanguageProvider implements BookLanguageProvider {
  const AiBookLanguageProvider();

  @override
  Future<BookLanguageActionResult> execute(BookLanguageRequest request) async {
    return const BookLanguageActionResult(
      status: BookLanguageActionStatus.unsupported,
      message: 'AI 语言能力尚未配置',
    );
  }
}
