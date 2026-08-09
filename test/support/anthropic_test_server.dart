import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef AnthropicRequestHandler =
    Future<void> Function(HttpRequest request, Map<String, dynamic> body);

final class AnthropicTestServer {
  AnthropicTestServer._(this._server, this._handler);

  final HttpServer _server;
  final AnthropicRequestHandler _handler;
  late final StreamSubscription<HttpRequest> _subscription;

  static Future<AnthropicTestServer> start(
    AnthropicRequestHandler handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final result = AnthropicTestServer._(server, handler);
    result._subscription = server.listen(result._handle);
    return result;
  }

  String get baseUrl => 'http://${_server.address.address}:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    try {
      final source = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(source);
      if (decoded is! Map) throw const FormatException('Expected object');
      await _handler(
        request,
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (error, stack) {
      try {
        request.response.statusCode = 500;
        request.response.write('$error\n$stack');
      } on StateError {
        // The adapter may intentionally close the socket during cancellation.
      }
      await request.response.close();
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}

Future<void> sendAnthropicSse(HttpRequest request, String body) async {
  request.response.statusCode = 200;
  request.response.headers.contentType = ContentType(
    'text',
    'event-stream',
    charset: 'utf-8',
  );
  request.response.write(body);
  await request.response.close();
}

Future<void> sendAnthropicJson(
  HttpRequest request,
  Map<String, Object?> body,
) async {
  request.response.statusCode = 200;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

String anthropicToolUseSse({String stopReason = 'tool_use'}) =>
    '''
data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-sonnet-5","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":42,"output_tokens":1}}}

data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"search_book","input":{}}}

data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":\\"张居正\\"}"}}

data: {"type":"content_block_stop","index":0}

data: {"type":"message_delta","delta":{"stop_reason":"$stopReason","stop_sequence":null},"usage":{"output_tokens":17}}

data: {"type":"message_stop"}

''';

String anthropicTextSse(String text) =>
    '''
data: {"type":"message_start","message":{"id":"msg_2","type":"message","role":"assistant","content":[],"model":"claude-sonnet-5","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":3,"output_tokens":1}}}

data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":${jsonEncode(text)}}}

data: {"type":"content_block_stop","index":0}

data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":2}}

data: {"type":"message_stop"}

''';
