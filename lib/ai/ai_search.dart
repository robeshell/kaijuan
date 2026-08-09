import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_log.dart';
import 'ai_models.dart';
import 'ai_cancel.dart';
import 'ai_user_error.dart';

/// Web search backend for book-chat「联网」(user BYOK).
enum AiSearchProviderKind {
  tavily,
  brave;

  String get storageValue => name;

  String get displayName => switch (this) {
    AiSearchProviderKind.tavily => 'Tavily',
    AiSearchProviderKind.brave => 'Brave Search',
  };

  String get hintUrl => switch (this) {
    AiSearchProviderKind.tavily => 'https://tavily.com',
    AiSearchProviderKind.brave => 'https://brave.com/search/api',
  };

  static AiSearchProviderKind fromStorage(String? value) {
    for (final k in AiSearchProviderKind.values) {
      if (k.storageValue == value) return k;
    }
    return AiSearchProviderKind.tavily;
  }
}

class AiWebSearchHit {
  const AiWebSearchHit({
    required this.title,
    required this.url,
    this.snippet = '',
  });

  final String title;
  final String url;
  final String snippet;

  String toPromptLine(int index) {
    final snip = snippet.trim();
    final body = snip.isEmpty ? '' : ' — $snip';
    return '$index. $title ($url)$body';
  }
}

/// Builds a short search query. Long shortcut prompts (「概括整本书…」) make
/// poor web queries — prefer book title + intent keywords.
String buildAiWebSearchQuery({
  required String userText,
  required String bookTitle,
  String? bookAuthor,
}) {
  final title = bookTitle.trim();
  final author = (bookAuthor ?? '').trim();
  final raw = userText.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (raw.isEmpty) return title;

  String withBook(String topic) {
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (author.isNotEmpty) author,
      topic,
    ];
    return parts.join(' ').trim();
  }

  // Shortcut / instruction-style prompts → topic-focused queries.
  if (raw.contains('时代') || raw.contains('背景') || raw.contains('制度')) {
    return withBook('历史背景 时代');
  }
  if (raw.contains('人物') || raw.contains('关系')) {
    return withBook('主要人物');
  }
  if (raw.contains('整本书') ||
      raw.contains('主线') ||
      raw.contains('主题') ||
      raw.contains('概括') ||
      raw.contains('讲什么')) {
    return withBook('内容简介 主题 评价');
  }
  if (raw.contains('这一章') || raw.contains('总结')) {
    return withBook('章节 内容');
  }

  // Short free-form questions: keep user text + book title.
  if (raw.length <= 48) {
    return title.isEmpty ? raw : '$raw $title';
  }
  // Long free-form: clip user text.
  final clip = raw.length > 60 ? '${raw.substring(0, 60)}…' : raw;
  return title.isEmpty ? clip : '$clip $title';
}

/// Fetches a few web results for optional book-chat 延展.
class AiWebSearchService {
  AiWebSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AiWebSearchHit>> search({
    required AiSearchProviderKind provider,
    required String apiKey,
    required String query,
    int maxResults = 5,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final q = query.trim();
    final key = apiKey.trim();
    if (q.isEmpty) return const [];
    if (key.isEmpty) {
      throw AiProviderException('未配置联网搜索 Key');
    }
    final n = maxResults.clamp(1, 8);
    AiLog.d(
      'webSearch start provider=${provider.displayName} '
      'key=${AiLog.maskKey(key)} q="${AiLog.bodyPreview(q, max: 80)}"',
    );
    final sw = Stopwatch()..start();
    try {
      final hits = await switch (provider) {
        AiSearchProviderKind.tavily => _tavily(key, q, n, cancelToken),
        AiSearchProviderKind.brave => _brave(key, q, n, cancelToken),
      };
      cancelToken?.throwIfCancelled();
      AiLog.d(
        'webSearch ok in ${sw.elapsedMilliseconds}ms hits=${hits.length}',
      );
      return hits;
    } catch (e) {
      AiLog.d('webSearch fail in ${sw.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  Future<List<AiWebSearchHit>> _tavily(
    String key,
    String q,
    int n,
    CancelToken? cancelToken,
  ) async {
    final uri = Uri.parse('https://api.tavily.com/search');
    // Current Tavily docs require Authorization: Bearer; body api_key kept
    // for older gateways that still accept it.
    final response = await _awaitCancelable(
      _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: jsonEncode({
              'api_key': key,
              'query': q,
              'max_results': n,
              'include_answer': false,
              'search_depth': 'basic',
            }),
          )
          .timeout(const Duration(seconds: 25)),
      cancelToken,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(
        _httpError(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const [];
    final results = decoded['results'];
    if (results is! List) return const [];
    final out = <AiWebSearchHit>[];
    for (final row in results) {
      if (row is! Map) continue;
      final title = '${row['title'] ?? ''}'.trim();
      final url = '${row['url'] ?? ''}'.trim();
      final snippet = '${row['content'] ?? row['snippet'] ?? ''}'.trim();
      if (title.isEmpty && url.isEmpty) continue;
      out.add(
        AiWebSearchHit(
          title: title.isEmpty ? url : title,
          url: url,
          snippet: snippet,
        ),
      );
      if (out.length >= n) break;
    }
    return out;
  }

  Future<List<AiWebSearchHit>> _brave(
    String key,
    String q,
    int n,
    CancelToken? cancelToken,
  ) async {
    final uri = Uri.https('api.search.brave.com', '/res/v1/web/search', {
      'q': q,
      'count': '$n',
    });
    final response = await _awaitCancelable(
      _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Accept-Encoding': 'gzip',
              'X-Subscription-Token': key,
            },
          )
          .timeout(const Duration(seconds: 25)),
      cancelToken,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(
        _httpError(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const [];
    final web = decoded['web'];
    if (web is! Map) return const [];
    final results = web['results'];
    if (results is! List) return const [];
    final out = <AiWebSearchHit>[];
    for (final row in results) {
      if (row is! Map) continue;
      final title = '${row['title'] ?? ''}'.trim();
      final url = '${row['url'] ?? ''}'.trim();
      final snippet = '${row['description'] ?? ''}'.trim();
      if (title.isEmpty && url.isEmpty) continue;
      out.add(
        AiWebSearchHit(
          title: title.isEmpty ? url : title,
          url: url,
          snippet: snippet,
        ),
      );
      if (out.length >= n) break;
    }
    return out;
  }

  static String _httpError(int code, String body) =>
      aiProviderHttpErrorMessage(code, providerMessage: body);
}

Future<T> _awaitCancelable<T>(Future<T> future, CancelToken? cancelToken) {
  if (cancelToken == null) return future;
  cancelToken.throwIfCancelled();
  final completer = Completer<T>();
  void cancel() {
    if (!completer.isCompleted) {
      completer.completeError(AiProviderException('已取消'));
    }
  }

  cancelToken.addCancelListener(cancel);
  future
      .then(
        (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
      )
      .whenComplete(() => cancelToken.removeCancelListener(cancel));
  return completer.future;
}
