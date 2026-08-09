import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_user_error.dart';

void main() {
  group('aiUserErrorMessage', () {
    test('unknown exceptions never expose exception text', () {
      final message = aiUserErrorMessage(
        const FormatException('Unexpected character at offset 17'),
        operation: AiUserOperation.history,
      );

      expect(message, '无法读取 AI 记录，请重试');
      expect(message, isNot(contains('FormatException')));
      expect(message, isNot(contains('offset')));
    });

    test('provider authentication text is replaced with an action', () {
      final message = aiUserErrorMessage(
        AiProviderException(
          'Incorrect API key sk-secret from upstream',
          statusCode: 401,
        ),
        operation: AiUserOperation.connect,
      );

      expect(message, 'API Key 无效或没有访问权限，请检查设置');
      expect(message, isNot(contains('sk-secret')));
      expect(message, isNot(contains('401')));
    });

    test('protocol and schema details become a model recovery hint', () {
      final message = aiUserErrorMessage(
        AiProviderException('JSON schema validation failed at entities[3]'),
        operation: AiUserOperation.graph,
      );

      expect(message, 'AI 返回的内容无法处理，请重试；如果仍然失败，请更换模型');
      expect(message, isNot(contains('JSON')));
      expect(message, isNot(contains('schema')));
    });

    test('network and timeout failures have distinct recovery actions', () {
      expect(
        aiUserErrorMessage(
          TimeoutException('request timeout'),
          operation: AiUserOperation.chat,
        ),
        '等待响应超时，请检查网络后重试',
      );
      expect(
        aiUserErrorMessage(
          AiProviderException('stream connection reset by peer'),
          operation: AiUserOperation.chat,
        ),
        '连接中断，请检查网络后重试',
      );
    });
  });

  group('aiProviderHttpErrorMessage', () {
    test('server bodies and status codes never become UI copy', () {
      final message = aiProviderHttpErrorMessage(
        500,
        providerMessage: '<html>nginx upstream failed trace=abc</html>',
      );

      expect(message, 'AI 服务暂时不可用，请稍后重试');
      expect(message, isNot(contains('500')));
      expect(message, isNot(contains('nginx')));
      expect(message, isNot(contains('trace')));
    });

    test('known provider categories still produce a useful action', () {
      expect(
        aiProviderHttpErrorMessage(
          400,
          providerMessage: 'model_not_found: internal-model-id',
        ),
        '没有找到所选模型，请重新选择模型',
      );
      expect(
        aiProviderHttpErrorMessage(
          429,
          providerMessage: 'insufficient_quota billing error',
        ),
        '可用额度不足，请检查服务商账户后重试',
      );
    });
  });
}
