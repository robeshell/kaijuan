import 'package:schemantic/schemantic.dart';

part 'ai_workflow_schemas.g.dart';

@Schema()
abstract class $AiOutlineBatchOutput {
  String get batchId;
  List<int> get coveredSections;
  String get summary;
  List<String> get points;
}

@Schema()
abstract class $AiOutlineUnitOutput {
  String get title;
  String get blurb;
  List<String> get sourceBatches;
}

@Schema()
abstract class $AiOutlineOutput {
  String get overview;
  List<$AiOutlineUnitOutput> get units;
}

@Schema()
abstract class $AiMindMapEvidenceOutput {
  int get sectionId;
  String get quote;
}

@Schema()
abstract class $AiMindMapBranchOutput {
  String get title;
  String get summary;
  List<$AiMindMapEvidenceOutput> get evidence;
}

@Schema()
abstract class $AiMindMapBatchOutput {
  String get batchId;
  List<int> get coveredSections;
  List<$AiMindMapBranchOutput> get branches;
}

@Schema()
abstract class $AiMindMapNodeOutput {
  String get tempId;
  String? get parentTempId;
  int get order;
  String get title;
  String get summary;
  List<$AiMindMapEvidenceOutput> get evidence;
}

@Schema()
abstract class $AiMindMapOutput {
  String get contentKind;
  List<$AiMindMapNodeOutput> get nodes;
}

@Schema()
abstract class $AiNarrationFeaturesOutput {
  double get eventDriven;
  double get characterEnsemble;
  double get organization;
  double get geography;
  double get essay;
}

@Schema()
abstract class $AiNarrationPlanOutput {
  $AiNarrationFeaturesOutput get features;
  String get defaultView;
  List<String> get viewOrder;
  bool get wantMap;
}

@Schema()
abstract class $AiGraphEvidenceOutput {
  int get section;
  String get quote;
}

@Schema()
abstract class $AiGraphEntityOutput {
  String get name;
  String get type;
  String get scope;
  String? get identityHint;
  List<String>? get aliases;
  String? get description;
  String? get eventType;
  int? get importance;
  List<$AiGraphEvidenceOutput> get evidence;
}

@Schema()
abstract class $AiGraphRelationOutput {
  String get source;
  String get target;
  String? get sourceIdentityHint;
  String? get targetIdentityHint;
  String get type;
  String? get description;
  String? get kin;
  List<$AiGraphEvidenceOutput> get evidence;
}

@Schema()
abstract class $AiGraphExtractionOutput {
  List<$AiGraphEntityOutput> get entities;
  List<$AiGraphRelationOutput> get relations;
}

@Schema()
abstract class $AiGraphEntityRefreshItemOutput {
  String get name;
  String get description;
  List<String> get dropAliases;
}

@Schema()
abstract class $AiGraphEntityRefreshOutput {
  List<$AiGraphEntityRefreshItemOutput> get entities;
}

@Schema()
abstract class $AiGraphLineageVerdictOutput {
  int get index;
  String get action;
  String get kin;
}

@Schema()
abstract class $AiGraphLineageReviewOutput {
  List<$AiGraphLineageVerdictOutput> get relations;
}

@Schema()
abstract class $AiGraphMergeReviewOutput {
  List<String> get verdicts;
}

/// Raw schemas exposed to App-owned adapter contracts. Generated Schemantic
/// types remain isolated in this infrastructure file.
abstract final class AiWorkflowSchemas {
  static final Map<String, Object?> outlineBatch = Map<String, Object?>.from(
    AiOutlineBatchOutput.$schema.jsonSchema(),
  );

  static final Map<String, Object?> outline = Map<String, Object?>.from(
    AiOutlineOutput.$schema.jsonSchema(useRefs: true),
  );

  static final Map<String, Object?> mindMapBatch = Map<String, Object?>.from(
    AiMindMapBatchOutput.$schema.jsonSchema(useRefs: true),
  );

  static final Map<String, Object?> mindMap = Map<String, Object?>.from(
    AiMindMapOutput.$schema.jsonSchema(useRefs: true),
  );

  static final Map<String, Object?> narrationPlan = Map<String, Object?>.from(
    AiNarrationPlanOutput.$schema.jsonSchema(useRefs: true),
  );

  static final Map<String, Object?> graphExtraction = Map<String, Object?>.from(
    AiGraphExtractionOutput.$schema.jsonSchema(useRefs: true),
  );

  static final Map<String, Object?> graphEntityRefresh =
      Map<String, Object?>.from(
        AiGraphEntityRefreshOutput.$schema.jsonSchema(useRefs: true),
      );

  static final Map<String, Object?> graphLineageReview =
      Map<String, Object?>.from(
        AiGraphLineageReviewOutput.$schema.jsonSchema(useRefs: true),
      );

  static final Map<String, Object?> graphMergeReview =
      Map<String, Object?>.from(
        AiGraphMergeReviewOutput.$schema.jsonSchema(useRefs: true),
      );
}
