import 'ai_book_mind_map_product_actions.dart';
import 'ai_book_mind_map_workflow.dart';
import 'ai_model_adapter.dart';
import 'ai_product_action.dart';
import 'ai_product_action_protocol.dart';
import 'ai_test_book_export_workflow.dart';
import 'ai_workflow_contract.dart';

/// Domain-owned parsing, confirmation, adapter and projection hooks for one
/// registered action.
///
/// Generic chat code looks up handlers by tool name / actionKind and never
/// switches on concrete product types. Strong types stay inside the domain.
abstract interface class AiProductActionDomain {
  String get actionKind;

  /// Tool names this domain accepts. Empty means explicit-UI only.
  Set<String> get toolNames;

  /// When false the domain must never appear in production tool catalogs.
  bool get productionExposed;

  AiProductActionDefinition get definition;

  /// Parse a model tool call into a domain request object.
  AiProductActionRequest parseToolCall(
    AiModelToolCall call,
    AiChatProductContext context,
  );

  /// Confirmation card copy for free-input proposals.
  AiProductActionConfirmationView confirmationView(
    AiProductActionRequest request, {
    required Map<String, Object?> contextHints,
  });

  /// Optional Workflow adapter for this domain. Null means another registry
  /// (e.g. mind-map create/revise) already owns the adapter instances.
  AiWorkflowAdapter? createAdapter(AiArtifactRepository artifacts);

  /// Formats a durable success projection string for conversation.
  String projectionMessage({
    required AiProductActionRequest? request,
    required List<String> artifactRefs,
  });
}

class AiProductActionConfirmationView {
  const AiProductActionConfirmationView({
    required this.title,
    required this.summary,
    this.scopeLabel,
    this.targetLabel,
    this.revisionLabel,
    this.externalWrite = false,
  });

  final String title;
  final String summary;
  final String? scopeLabel;
  final String? targetLabel;
  final String? revisionLabel;
  final bool externalWrite;
}

/// Registry of domain handlers. Used by tool parsing and chat dispatch.
class AiProductActionDomainRegistry {
  AiProductActionDomainRegistry(Iterable<AiProductActionDomain> domains)
    : _byActionKind = {for (final domain in domains) domain.actionKind: domain},
      _byToolName = {
        for (final domain in domains)
          for (final tool in domain.toolNames) tool: domain,
      } {
    final kinds = <String>{};
    final tools = <String>{};
    for (final domain in domains) {
      if (!kinds.add(domain.actionKind)) {
        throw ArgumentError('Duplicate domain action: ${domain.actionKind}');
      }
      for (final tool in domain.toolNames) {
        if (!tools.add(tool)) {
          throw ArgumentError('Duplicate domain tool: $tool');
        }
      }
    }
  }

  final Map<String, AiProductActionDomain> _byActionKind;
  final Map<String, AiProductActionDomain> _byToolName;

  Iterable<AiProductActionDomain> get domains => _byActionKind.values;

  AiProductActionDomain? byActionKind(String actionKind) =>
      _byActionKind[actionKind];

  AiProductActionDomain? byToolName(String toolName) => _byToolName[toolName];

  AiProductActionRegistry asActionRegistry({bool productionOnly = true}) =>
      AiProductActionRegistry([
        for (final domain in domains)
          if (!productionOnly || domain.productionExposed) domain.definition,
      ]);

  List<AiWorkflowAdapter> buildAdapters(AiArtifactRepository artifacts) => [
    for (final domain in domains) ?domain.createAdapter(artifacts),
  ];

  AiProductActionRequest parseToolCall(
    AiModelToolCall call,
    AiChatProductContext context,
  ) {
    final domain = byToolName(call.name);
    if (domain == null) {
      throw const FormatException('Unknown product tool');
    }
    return domain.parseToolCall(call, context);
  }
}

/// Registered book mind-map create/revise domains.
class AiBookMindMapCreateDomain implements AiProductActionDomain {
  const AiBookMindMapCreateDomain();

  @override
  String get actionKind => 'create_book_mind_map';

  @override
  Set<String> get toolNames => const {'create_book_mind_map'};

  @override
  bool get productionExposed => true;

  @override
  AiProductActionDefinition get definition => AiBookMindMapProductActions.create;

  @override
  AiProductActionRequest parseToolCall(
    AiModelToolCall call,
    AiChatProductContext context,
  ) {
    final instruction = '${call.arguments['instruction'] ?? ''}'.trim();
    if (instruction.isEmpty || instruction.length > 2000) {
      throw const FormatException('Invalid product instruction');
    }
    final rawScope = '${call.arguments['scope'] ?? 'unspecified'}';
    final scope = AiBookMindMapActionScope.values.where(
      (value) => value.name == rawScope,
    );
    if (scope.isEmpty) throw const FormatException('Invalid mind-map scope');
    final rawWorkAlias = '${call.arguments['workRef'] ?? ''}'.trim();
    AiProductWorkAlias? work;
    if (scope.single == AiBookMindMapActionScope.specificWork) {
      final matches = context.works.where(
        (candidate) => candidate.alias == rawWorkAlias,
      );
      if (matches.length != 1) {
        throw const FormatException('Unknown book-work alias');
      }
      work = matches.single;
    } else if (rawWorkAlias.isNotEmpty) {
      throw const FormatException(
        'workRef is only valid with specificWork scope',
      );
    }
    return AiCreateBookMindMapAction(
      instruction: instruction,
      scope: scope.single,
      workAlias: work?.alias,
      workId: work?.workId,
    );
  }

  @override
  AiProductActionConfirmationView confirmationView(
    AiProductActionRequest request, {
    required Map<String, Object?> contextHints,
  }) {
    final create = request as AiCreateBookMindMapAction;
    return AiProductActionConfirmationView(
      title: '确认生成思维导图',
      summary: '将根据已冻结的阅读范围生成原生思维导图。',
      scopeLabel: switch (create.scope) {
        AiBookMindMapActionScope.currentChapter => '当前章节',
        AiBookMindMapActionScope.currentWork => '当前作品',
        AiBookMindMapActionScope.specificWork => '指定作品',
        AiBookMindMapActionScope.wholePublication => '整本合集',
        AiBookMindMapActionScope.unspecified => '待确定',
      },
    );
  }

  @override
  AiWorkflowAdapter? createAdapter(AiArtifactRepository artifacts) =>
      AiBookMindMapWorkflowAdapter(
        actionKind: actionKind,
        artifacts: artifacts,
      );

  @override
  String projectionMessage({
    required AiProductActionRequest? request,
    required List<String> artifactRefs,
  }) => '已生成思维导图。';
}

class AiBookMindMapReviseDomain implements AiProductActionDomain {
  const AiBookMindMapReviseDomain();

  @override
  String get actionKind => 'revise_book_mind_map';

  @override
  Set<String> get toolNames => const {'revise_book_mind_map'};

  @override
  bool get productionExposed => true;

  @override
  AiProductActionDefinition get definition => AiBookMindMapProductActions.revise;

  @override
  AiProductActionRequest parseToolCall(
    AiModelToolCall call,
    AiChatProductContext context,
  ) {
    final instruction = '${call.arguments['instruction'] ?? ''}'.trim();
    if (instruction.isEmpty || instruction.length > 2000) {
      throw const FormatException('Invalid product instruction');
    }
    final alias = '${call.arguments['artifactRef'] ?? ''}'.trim();
    final matches = alias.isEmpty
        ? const <AiProductArtifactAlias>[]
        : context.artifacts.where((a) => a.alias == alias).toList();
    // Light path: empty or unknown alias → preferred, else latest artifact.
    final artifact = matches.length == 1
        ? matches.single
        : context.artifacts.where((a) => a.isPreferred).firstOrNull ??
              (context.artifacts.isEmpty ? null : context.artifacts.last);
    if (artifact == null) {
      throw const FormatException('No mind-map artifact available to revise');
    }
    return AiReviseBookMindMapAction(
      instruction: instruction,
      artifactAlias: artifact.alias,
      artifactId: artifact.artifactId,
    );
  }

  @override
  AiProductActionConfirmationView confirmationView(
    AiProductActionRequest request, {
    required Map<String, Object?> contextHints,
  }) {
    final revise = request as AiReviseBookMindMapAction;
    final revision = contextHints['revision'];
    return AiProductActionConfirmationView(
      title: '确认修改思维导图',
      summary: revision == null
          ? '将基于当前导图生成新版本。'
          : '将基于当前导图的第 $revision 版生成新版本。',
      targetLabel: revise.artifactAlias,
      revisionLabel: revision == null ? null : '基于第 $revision 版',
    );
  }

  @override
  AiWorkflowAdapter? createAdapter(AiArtifactRepository artifacts) =>
      AiBookMindMapWorkflowAdapter(
        actionKind: actionKind,
        artifacts: artifacts,
      );

  @override
  String projectionMessage({
    required AiProductActionRequest? request,
    required List<String> artifactRefs,
  }) => '已修改思维导图。';
}

/// Non-production test export domain used to prove registry-driven extension.
class AiTestBookExportDomain implements AiProductActionDomain {
  const AiTestBookExportDomain();

  static const actionKindValue = 'test_book_export';
  static const toolNameValue = 'test_book_export';

  @override
  String get actionKind => actionKindValue;

  @override
  Set<String> get toolNames => const {toolNameValue};

  @override
  bool get productionExposed => false;

  @override
  AiProductActionDefinition get definition => const AiProductActionDefinition(
    actionKind: actionKindValue,
    definitionVersion: 1,
    proposalSchemaVersion: 1,
    commandSchemaVersion: 1,
    workflowVersion: 1,
    riskClass: AiActionRiskClass.reversible,
    supportedSources: {
      AiActionProposalSource.modelTool,
      AiActionProposalSource.explicitUi,
    },
    requiredCapabilities: {'book.read'},
    toolName: toolNameValue,
    toolDescription:
        'Test-only export workflow. Never expose in production catalogs.',
    argumentSchema: {
      'type': 'object',
      'properties': {
        'format': {
          'type': 'string',
          'enum': ['markdown', 'plain'],
        },
        'instruction': {'type': 'string', 'minLength': 1, 'maxLength': 200},
      },
      'required': ['format', 'instruction'],
    },
    artifactKind: 'test_book_export',
    artifactSchemaVersion: 1,
    displayNameKey: 'ai.action.testBookExport',
  );

  @override
  AiProductActionRequest parseToolCall(
    AiModelToolCall call,
    AiChatProductContext context,
  ) {
    final instruction = '${call.arguments['instruction'] ?? ''}'.trim();
    final format = '${call.arguments['format'] ?? ''}'.trim();
    if (instruction.isEmpty || instruction.length > 200) {
      throw const FormatException('Invalid export instruction');
    }
    if (format != 'markdown' && format != 'plain') {
      throw const FormatException('Invalid export format');
    }
    return AiRegisteredProductAction(
      actionKind: actionKind,
      instruction: instruction,
      arguments: {'format': format, 'instruction': instruction},
    );
  }

  @override
  AiProductActionConfirmationView confirmationView(
    AiProductActionRequest request, {
    required Map<String, Object?> contextHints,
  }) => const AiProductActionConfirmationView(
    title: '确认测试导出',
    summary: '将生成一条测试导出 Artifact（非生产能力）。',
  );

  @override
  AiWorkflowAdapter? createAdapter(AiArtifactRepository artifacts) =>
      AiTestBookExportWorkflowAdapter(artifacts: artifacts);

  @override
  String projectionMessage({
    required AiProductActionRequest? request,
    required List<String> artifactRefs,
  }) =>
      '已完成测试导出（artifact: ${artifactRefs.isEmpty ? '—' : artifactRefs.join(', ')}）';
}

/// Production domain registry (mind maps only).
AiProductActionDomainRegistry kaijuanProductionActionDomains() =>
    AiProductActionDomainRegistry(const [
      AiBookMindMapCreateDomain(),
      AiBookMindMapReviseDomain(),
    ]);

/// Test registry that also includes the non-production export domain.
AiProductActionDomainRegistry kaijuanTestActionDomains() =>
    AiProductActionDomainRegistry(const [
      AiBookMindMapCreateDomain(),
      AiBookMindMapReviseDomain(),
      AiTestBookExportDomain(),
    ]);
