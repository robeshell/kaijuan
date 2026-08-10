import 'dart:async';
import 'dart:io';

import 'ai_models.dart';

/// The operation that failed, used only to choose a useful generic fallback.
enum AiUserOperation {
  connect,
  loadModels,
  search,
  chat,
  outline,
  mindMap,
  graph,
  language,
  history,
}

/// Converts an internal or provider failure into calm, actionable UI copy.
///
/// Never returns the original unknown exception text. Technical details belong
/// in [AiLog], not in SnackBars or error panels.
String aiUserErrorMessage(Object error, {required AiUserOperation operation}) {
  final providerError = error is AiProviderException ? error : null;
  final statusCode = providerError?.statusCode;
  final detail = providerError?.message ?? error.toString();
  final normalized = detail.toLowerCase();

  if (_containsAny(normalized, const ['已取消', '已停止', 'cancelled', 'canceled'])) {
    return '已停止';
  }

  if (statusCode != null) {
    final statusMessage = aiProviderHttpErrorMessage(
      statusCode,
      providerMessage: detail,
    );
    if (statusMessage.isNotEmpty) return statusMessage;
  }

  if (error is TimeoutException ||
      _containsAny(normalized, const ['timeout', 'timed out', '超时'])) {
    return '等待响应超时，请检查网络后重试';
  }
  if (error is SocketException ||
      error is HandshakeException ||
      _containsAny(normalized, const [
        'socketexception',
        'handshakeexception',
        'clientexception',
        'connection reset',
        'connection refused',
        'failed host lookup',
        'network is unreachable',
        '流式响应意外中断',
        '流式响应等待超时',
      ])) {
    return '连接中断，请检查网络后重试';
  }

  if (_containsAny(normalized, const [
    '自动续写多次后仍未结束',
    '自动续写没有返回内容',
    '自动续写返回了无效内容',
  ])) {
    return '回答很长，已保留生成内容。请缩小问题范围后重试';
  }

  if (_containsAny(normalized, const [
    'context length',
    'maximum context',
    'max_tokens',
    'token limit',
    'length limit',
    '长度上限',
    '输出被截断',
    '汇总不完整',
  ])) {
    return '内容较长，当前模型未能完整处理。请更换支持更长内容的模型后重试';
  }

  if (_containsAny(normalized, const [
    'invalid api key',
    'incorrect api key',
    'authentication',
    'unauthorized',
    '密钥无效',
    'key 无效',
    '没有权限',
    '无权限',
  ])) {
    return 'API Key 无效或没有访问权限，请检查设置';
  }
  if (_containsAny(normalized, const ['未配置联网搜索 key', '配置联网搜索 key'])) {
    return '请先在设置中填写联网搜索 Key';
  }
  if (_containsAny(normalized, const ['请先填写 api key', '添加 api key'])) {
    return '请先填写 API Key';
  }
  if (_containsAny(normalized, const ['ai 未启用', 'ai 已关闭'])) {
    return '请先在设置中启用 AI';
  }
  if (_containsAny(normalized, const [
    '请填写接口地址',
    '接口地址必须',
    '远程接口地址必须',
    '本地 ollama',
  ])) {
    return detail;
  }
  if (_containsAny(normalized, const ['请填写模型名称', '请先选择或填写模型', '未获取到可用模型'])) {
    return detail;
  }

  if (_containsAny(normalized, const [
    '无法读取本书正文',
    '没有可用于生成大纲的正文',
    '所选章节都被排除',
    '所选著作没有可用正文',
    '当前无法可靠判断',
    '翻到某部作品',
    '这是一本合订书',
    '请输入问题',
    '没有可查询的文字',
  ])) {
    return detail;
  }

  if (_containsAny(normalized, const [
    'json',
    'schema',
    'sse',
    'fenced',
    '格式无法识别',
    '格式无效',
    '工具调用格式',
    '未给出正文',
    '接口未返回内容',
    '返回了空内容',
    '没有生成内容',
    '摘要格式',
  ])) {
    return 'AI 返回的内容无法处理，请重试；如果仍然失败，请更换模型';
  }

  return switch (operation) {
    AiUserOperation.connect => '无法连接，请检查网络与接口设置',
    AiUserOperation.loadModels => '无法获取模型，请检查网络与接口设置',
    AiUserOperation.search => '无法完成联网搜索，请检查网络后重试',
    AiUserOperation.chat => '暂时无法生成回答，请稍后重试',
    AiUserOperation.outline => '暂时无法生成大纲，请稍后重试',
    AiUserOperation.mindMap => '暂时无法生成思维导图，请稍后重试',
    AiUserOperation.graph => '暂时无法生成知识图谱，请稍后重试',
    AiUserOperation.language => '暂时无法生成内容，请稍后重试',
    AiUserOperation.history => '无法读取 AI 记录，请重试',
  };
}

/// Maps an HTTP failure without exposing status codes or provider response
/// bodies. [providerMessage] is inspected for category only and never returned.
String aiProviderHttpErrorMessage(int statusCode, {String? providerMessage}) {
  final normalized = (providerMessage ?? '').toLowerCase();
  if (_containsAny(normalized, const [
    'quota',
    'billing',
    'credit',
    'insufficient_balance',
    'insufficient funds',
  ])) {
    return '可用额度不足，请检查服务商账户后重试';
  }
  if (_containsAny(normalized, const [
    'model_not_found',
    'model not found',
    'unknown model',
  ])) {
    return '没有找到所选模型，请重新选择模型';
  }
  if (_containsAny(normalized, const [
    'context length',
    'maximum context',
    'too many tokens',
  ])) {
    return '内容较长，当前模型无法完整处理。请更换支持更长内容的模型后重试';
  }
  return switch (statusCode) {
    400 => '请求内容未被服务接受，请检查模型设置后重试',
    401 || 403 => 'API Key 无效或没有访问权限，请检查设置',
    404 => '没有找到对应服务，请检查接口地址和模型名称',
    408 => '等待响应超时，请检查网络后重试',
    409 => '服务正在处理其他请求，请稍后重试',
    413 => '发送的内容过长，请缩小范围后重试',
    422 => '当前模型无法处理这项请求，请更换模型后重试',
    429 => '请求较多或可用额度不足，请稍后重试',
    >= 500 => 'AI 服务暂时不可用，请稍后重试',
    _ => '请求未完成，请检查网络和服务设置后重试',
  };
}

bool _containsAny(String value, List<String> patterns) =>
    patterns.any(value.contains);
