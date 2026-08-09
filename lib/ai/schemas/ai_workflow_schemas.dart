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

/// Raw schemas exposed to App-owned adapter contracts. Generated Schemantic
/// types remain isolated in this infrastructure file.
abstract final class AiWorkflowSchemas {
  static final Map<String, Object?> outlineBatch = Map<String, Object?>.from(
    AiOutlineBatchOutput.$schema.jsonSchema(),
  );

  static final Map<String, Object?> outline = Map<String, Object?>.from(
    AiOutlineOutput.$schema.jsonSchema(useRefs: true),
  );
}
