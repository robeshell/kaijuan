import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_agent_runtime_gate.dart';

void main() {
  test('compatible runtime remains the deterministic default', () {
    final decision = AiAgentRuntimeGate.decide(
      requested: AiAgentRuntimeKind.compatible,
      genkitCapabilities: AiAgentRuntimeCapabilities.genkitDart0151,
      hasGenkitRuntimeFactory: false,
    );

    expect(decision.effective, AiAgentRuntimeKind.compatible);
    expect(decision.fellBack, isFalse);
    expect(decision.blockers, isEmpty);
  });

  test('locked Genkit 0.15.1 cannot become the effective runtime', () {
    final decision = AiAgentRuntimeGate.decide(
      requested: AiAgentRuntimeKind.genkitAgent,
      genkitCapabilities: AiAgentRuntimeCapabilities.genkitDart0151,
      hasGenkitRuntimeFactory: true,
    );

    expect(decision.effective, AiAgentRuntimeKind.compatible);
    expect(decision.fellBack, isTrue);
    expect(decision.blockers, contains('attached 模型请求不支持真实取消'));
    expect(decision.canPromoteGenkit, isFalse);
  });

  test('promotion requires both a runtime factory and every capability', () {
    final missingFactory = AiAgentRuntimeGate.decide(
      requested: AiAgentRuntimeKind.genkitAgent,
      genkitCapabilities: AiAgentRuntimeCapabilities.productionReady,
      hasGenkitRuntimeFactory: false,
    );
    final ready = AiAgentRuntimeGate.decide(
      requested: AiAgentRuntimeKind.genkitAgent,
      genkitCapabilities: AiAgentRuntimeCapabilities.productionReady,
      hasGenkitRuntimeFactory: true,
    );

    expect(missingFactory.effective, AiAgentRuntimeKind.compatible);
    expect(missingFactory.blockers, ['Genkit Agent runtime 尚未安装']);
    expect(ready.effective, AiAgentRuntimeKind.genkitAgent);
    expect(ready.blockers, isEmpty);
    expect(ready.canPromoteGenkit, isTrue);
  });
}
