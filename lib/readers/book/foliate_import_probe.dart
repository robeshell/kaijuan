import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'book_rendition_session.dart';
import 'foliate_js_bridge.dart';

abstract interface class EpubImportProbe {
  Future<FoliateImportSnapshot> inspect(String path);
}

/// Opens an EPUB through the same Foliate parser used by the visible reader.
///
/// This follows Anx Reader's import path: a short-lived headless WebView emits
/// `onMetadata`, then both the WebView and loopback server are unconditionally
/// disposed. It deliberately has no dependency on reader controllers or DB.
class FoliateJsImportProbe implements EpubImportProbe {
  const FoliateJsImportProbe({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;

  /// Minimal Foliate style payload required by `epub.js` Loader on every page,
  /// including metadata-only probes that never create a rendition.
  static const Map<String, Object?> metadataProbeStyle = {'allowScript': false};

  /// Builds the metadata probe URL with the same Loader contract as reading.
  static Uri buildProbeUri(BookRenditionSession session) {
    return session.probeUri.replace(
      queryParameters: {
        'url': jsonEncode(session.bookUri.toString()),
        'style': jsonEncode(metadataProbeStyle),
      },
    );
  }

  @override
  Future<FoliateImportSnapshot> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) throw const FoliateImportException('文件不存在');

    BookRenditionSession? session;
    HeadlessInAppWebView? webView;
    final result = Completer<FoliateImportSnapshot>();
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    try {
      session = await BookRenditionSession.open(
        file,
        onTiming: (timing) {
          if (kDebugMode) debugPrint('[FoliateImport] $timing');
        },
      );
      final readerUri = buildProbeUri(session);
      webView = HeadlessInAppWebView(
        initialSize: const Size(1, 1),
        initialUrlRequest: URLRequest(url: WebUri.uri(readerUri)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          supportZoom: false,
          isInspectable: kDebugMode,
        ),
        onWebViewCreated: (controller) {
          session?.mark('probe-webview-created');
          controller.addJavaScriptHandler(
            handlerName: 'onMetadata',
            callback: (arguments) {
              final snapshot = FoliateImportSnapshot.fromHandlerArguments(
                arguments,
              );
              if (snapshot == null || snapshot.sectionCount <= 0) {
                fail(const FoliateImportException('EPUB 没有可读取的 spine'));
              } else if (!result.isCompleted) {
                session?.mark('probe-metadata-ready');
                result.complete(snapshot);
              }
              return null;
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'onProbeError',
            callback: (arguments) {
              final message = arguments.isEmpty
                  ? '未知错误'
                  : arguments.first.toString();
              fail(FoliateImportException('Foliate 解析失败：$message'));
              return null;
            },
          );
        },
        onLoadStart: (_, _) => session?.mark('probe-load-start'),
        onLoadStop: (_, _) => session?.mark('probe-load-stop'),
        onProgressChanged: (_, progress) {
          if (progress == 100) session?.mark('probe-page-ready');
        },
        onReceivedError: (_, request, error) {
          if (request.isForMainFrame == true) {
            fail(FoliateImportException('Foliate 加载失败：${error.description}'));
          }
        },
        onConsoleMessage: (_, message) {
          if (kDebugMode) debugPrint('[FoliateImport] ${message.message}');
        },
      );
      await webView.run();
      return await result.future.timeout(
        timeout,
        onTimeout: () => throw const FoliateImportException('EPUB 元数据读取超时'),
      );
    } on FoliateImportException {
      rethrow;
    } catch (error) {
      throw FoliateImportException('无法读取 EPUB：$error');
    } finally {
      await webView?.dispose();
      await session?.close();
    }
  }
}

class FoliateImportException implements Exception {
  const FoliateImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
