// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_workflow_schemas.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

base class AiOutlineBatchOutput {
  /// Creates a [AiOutlineBatchOutput] from a JSON map.
  factory AiOutlineBatchOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiOutlineBatchOutput._(this._json);

  AiOutlineBatchOutput({
    required String batchId,
    required List<int> coveredSections,
    required String summary,
    required List<String> points,
  }) {
    _json = {
      'batchId': batchId,
      'coveredSections': coveredSections,
      'summary': summary,
      'points': points,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiOutlineBatchOutput].
  static const SchemanticType<AiOutlineBatchOutput> $schema =
      _AiOutlineBatchOutputTypeFactory();

  String get batchId {
    return _json['batchId'] as String;
  }

  set batchId(String value) {
    _json['batchId'] = value;
  }

  List<int> get coveredSections {
    return (_json['coveredSections'] as List).cast<int>();
  }

  set coveredSections(List<int> value) {
    _json['coveredSections'] = value;
  }

  String get summary {
    return _json['summary'] as String;
  }

  set summary(String value) {
    _json['summary'] = value;
  }

  List<String> get points {
    return (_json['points'] as List).cast<String>();
  }

  set points(List<String> value) {
    _json['points'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiOutlineBatchOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiOutlineBatchOutputTypeFactory
    extends SchemanticType<AiOutlineBatchOutput> {
  const _AiOutlineBatchOutputTypeFactory();

  @override
  AiOutlineBatchOutput parse(Object? json) {
    return AiOutlineBatchOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiOutlineBatchOutput',
    definition: $Schema
        .object(
          properties: {
            'batchId': $Schema.string(),
            'coveredSections': $Schema.list(items: $Schema.integer()),
            'summary': $Schema.string(),
            'points': $Schema.list(items: $Schema.string()),
          },
          required: ['batchId', 'coveredSections', 'summary', 'points'],
        )
        .value,
    dependencies: [],
  );
}

base class AiOutlineUnitOutput {
  /// Creates a [AiOutlineUnitOutput] from a JSON map.
  factory AiOutlineUnitOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiOutlineUnitOutput._(this._json);

  AiOutlineUnitOutput({
    required String title,
    required String blurb,
    required List<String> sourceBatches,
  }) {
    _json = {'title': title, 'blurb': blurb, 'sourceBatches': sourceBatches};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiOutlineUnitOutput].
  static const SchemanticType<AiOutlineUnitOutput> $schema =
      _AiOutlineUnitOutputTypeFactory();

  String get title {
    return _json['title'] as String;
  }

  set title(String value) {
    _json['title'] = value;
  }

  String get blurb {
    return _json['blurb'] as String;
  }

  set blurb(String value) {
    _json['blurb'] = value;
  }

  List<String> get sourceBatches {
    return (_json['sourceBatches'] as List).cast<String>();
  }

  set sourceBatches(List<String> value) {
    _json['sourceBatches'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiOutlineUnitOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiOutlineUnitOutputTypeFactory
    extends SchemanticType<AiOutlineUnitOutput> {
  const _AiOutlineUnitOutputTypeFactory();

  @override
  AiOutlineUnitOutput parse(Object? json) {
    return AiOutlineUnitOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiOutlineUnitOutput',
    definition: $Schema
        .object(
          properties: {
            'title': $Schema.string(),
            'blurb': $Schema.string(),
            'sourceBatches': $Schema.list(items: $Schema.string()),
          },
          required: ['title', 'blurb', 'sourceBatches'],
        )
        .value,
    dependencies: [],
  );
}

base class AiOutlineOutput {
  /// Creates a [AiOutlineOutput] from a JSON map.
  factory AiOutlineOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiOutlineOutput._(this._json);

  AiOutlineOutput({
    required String overview,
    required List<AiOutlineUnitOutput> units,
  }) {
    _json = {
      'overview': overview,
      'units': units.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiOutlineOutput].
  static const SchemanticType<AiOutlineOutput> $schema =
      _AiOutlineOutputTypeFactory();

  String get overview {
    return _json['overview'] as String;
  }

  set overview(String value) {
    _json['overview'] = value;
  }

  List<AiOutlineUnitOutput> get units {
    return (_json['units'] as List)
        .map((e) => AiOutlineUnitOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set units(List<AiOutlineUnitOutput> value) {
    _json['units'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiOutlineOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiOutlineOutputTypeFactory extends SchemanticType<AiOutlineOutput> {
  const _AiOutlineOutputTypeFactory();

  @override
  AiOutlineOutput parse(Object? json) {
    return AiOutlineOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiOutlineOutput',
    definition: $Schema
        .object(
          properties: {
            'overview': $Schema.string(),
            'units': $Schema.list(
              items: $Schema.fromMap({'\$ref': r'#/$defs/AiOutlineUnitOutput'}),
            ),
          },
          required: ['overview', 'units'],
        )
        .value,
    dependencies: [AiOutlineUnitOutput.$schema],
  );
}

base class AiMindMapEvidenceOutput {
  /// Creates a [AiMindMapEvidenceOutput] from a JSON map.
  factory AiMindMapEvidenceOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiMindMapEvidenceOutput._(this._json);

  AiMindMapEvidenceOutput({required int sectionId, required String quote}) {
    _json = {'sectionId': sectionId, 'quote': quote};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiMindMapEvidenceOutput].
  static const SchemanticType<AiMindMapEvidenceOutput> $schema =
      _AiMindMapEvidenceOutputTypeFactory();

  int get sectionId {
    return _json['sectionId'] as int;
  }

  set sectionId(int value) {
    _json['sectionId'] = value;
  }

  String get quote {
    return _json['quote'] as String;
  }

  set quote(String value) {
    _json['quote'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiMindMapEvidenceOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiMindMapEvidenceOutputTypeFactory
    extends SchemanticType<AiMindMapEvidenceOutput> {
  const _AiMindMapEvidenceOutputTypeFactory();

  @override
  AiMindMapEvidenceOutput parse(Object? json) {
    return AiMindMapEvidenceOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiMindMapEvidenceOutput',
    definition: $Schema
        .object(
          properties: {
            'sectionId': $Schema.integer(),
            'quote': $Schema.string(),
          },
          required: ['sectionId', 'quote'],
        )
        .value,
    dependencies: [],
  );
}

base class AiMindMapBranchOutput {
  /// Creates a [AiMindMapBranchOutput] from a JSON map.
  factory AiMindMapBranchOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiMindMapBranchOutput._(this._json);

  AiMindMapBranchOutput({
    required String title,
    required String summary,
    required List<AiMindMapEvidenceOutput> evidence,
  }) {
    _json = {
      'title': title,
      'summary': summary,
      'evidence': evidence.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiMindMapBranchOutput].
  static const SchemanticType<AiMindMapBranchOutput> $schema =
      _AiMindMapBranchOutputTypeFactory();

  String get title {
    return _json['title'] as String;
  }

  set title(String value) {
    _json['title'] = value;
  }

  String get summary {
    return _json['summary'] as String;
  }

  set summary(String value) {
    _json['summary'] = value;
  }

  List<AiMindMapEvidenceOutput> get evidence {
    return (_json['evidence'] as List)
        .map((e) => AiMindMapEvidenceOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set evidence(List<AiMindMapEvidenceOutput> value) {
    _json['evidence'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiMindMapBranchOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiMindMapBranchOutputTypeFactory
    extends SchemanticType<AiMindMapBranchOutput> {
  const _AiMindMapBranchOutputTypeFactory();

  @override
  AiMindMapBranchOutput parse(Object? json) {
    return AiMindMapBranchOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiMindMapBranchOutput',
    definition: $Schema
        .object(
          properties: {
            'title': $Schema.string(),
            'summary': $Schema.string(),
            'evidence': $Schema.list(
              items: $Schema.fromMap({
                '\$ref': r'#/$defs/AiMindMapEvidenceOutput',
              }),
            ),
          },
          required: ['title', 'summary', 'evidence'],
        )
        .value,
    dependencies: [AiMindMapEvidenceOutput.$schema],
  );
}

base class AiMindMapBatchOutput {
  /// Creates a [AiMindMapBatchOutput] from a JSON map.
  factory AiMindMapBatchOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiMindMapBatchOutput._(this._json);

  AiMindMapBatchOutput({
    required String batchId,
    required List<int> coveredSections,
    required List<AiMindMapBranchOutput> branches,
  }) {
    _json = {
      'batchId': batchId,
      'coveredSections': coveredSections,
      'branches': branches.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiMindMapBatchOutput].
  static const SchemanticType<AiMindMapBatchOutput> $schema =
      _AiMindMapBatchOutputTypeFactory();

  String get batchId {
    return _json['batchId'] as String;
  }

  set batchId(String value) {
    _json['batchId'] = value;
  }

  List<int> get coveredSections {
    return (_json['coveredSections'] as List).cast<int>();
  }

  set coveredSections(List<int> value) {
    _json['coveredSections'] = value;
  }

  List<AiMindMapBranchOutput> get branches {
    return (_json['branches'] as List)
        .map((e) => AiMindMapBranchOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set branches(List<AiMindMapBranchOutput> value) {
    _json['branches'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiMindMapBatchOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiMindMapBatchOutputTypeFactory
    extends SchemanticType<AiMindMapBatchOutput> {
  const _AiMindMapBatchOutputTypeFactory();

  @override
  AiMindMapBatchOutput parse(Object? json) {
    return AiMindMapBatchOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiMindMapBatchOutput',
    definition: $Schema
        .object(
          properties: {
            'batchId': $Schema.string(),
            'coveredSections': $Schema.list(items: $Schema.integer()),
            'branches': $Schema.list(
              items: $Schema.fromMap({
                '\$ref': r'#/$defs/AiMindMapBranchOutput',
              }),
            ),
          },
          required: ['batchId', 'coveredSections', 'branches'],
        )
        .value,
    dependencies: [AiMindMapBranchOutput.$schema],
  );
}

base class AiMindMapNodeOutput {
  /// Creates a [AiMindMapNodeOutput] from a JSON map.
  factory AiMindMapNodeOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiMindMapNodeOutput._(this._json);

  AiMindMapNodeOutput({
    required String tempId,
    String? parentTempId,
    required int order,
    required String title,
    required String summary,
    required List<AiMindMapEvidenceOutput> evidence,
  }) {
    _json = {
      'tempId': tempId,
      'parentTempId': ?parentTempId,
      'order': order,
      'title': title,
      'summary': summary,
      'evidence': evidence.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiMindMapNodeOutput].
  static const SchemanticType<AiMindMapNodeOutput> $schema =
      _AiMindMapNodeOutputTypeFactory();

  String get tempId {
    return _json['tempId'] as String;
  }

  set tempId(String value) {
    _json['tempId'] = value;
  }

  String? get parentTempId {
    return _json['parentTempId'] as String?;
  }

  set parentTempId(String? value) {
    if (value == null) {
      _json.remove('parentTempId');
    } else {
      _json['parentTempId'] = value;
    }
  }

  int get order {
    return _json['order'] as int;
  }

  set order(int value) {
    _json['order'] = value;
  }

  String get title {
    return _json['title'] as String;
  }

  set title(String value) {
    _json['title'] = value;
  }

  String get summary {
    return _json['summary'] as String;
  }

  set summary(String value) {
    _json['summary'] = value;
  }

  List<AiMindMapEvidenceOutput> get evidence {
    return (_json['evidence'] as List)
        .map((e) => AiMindMapEvidenceOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set evidence(List<AiMindMapEvidenceOutput> value) {
    _json['evidence'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiMindMapNodeOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiMindMapNodeOutputTypeFactory
    extends SchemanticType<AiMindMapNodeOutput> {
  const _AiMindMapNodeOutputTypeFactory();

  @override
  AiMindMapNodeOutput parse(Object? json) {
    return AiMindMapNodeOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiMindMapNodeOutput',
    definition: $Schema
        .object(
          properties: {
            'tempId': $Schema.string(),
            'parentTempId': $Schema.string(),
            'order': $Schema.integer(),
            'title': $Schema.string(),
            'summary': $Schema.string(),
            'evidence': $Schema.list(
              items: $Schema.fromMap({
                '\$ref': r'#/$defs/AiMindMapEvidenceOutput',
              }),
            ),
          },
          required: ['tempId', 'order', 'title', 'summary', 'evidence'],
        )
        .value,
    dependencies: [AiMindMapEvidenceOutput.$schema],
  );
}

base class AiMindMapOutput {
  /// Creates a [AiMindMapOutput] from a JSON map.
  factory AiMindMapOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiMindMapOutput._(this._json);

  AiMindMapOutput({
    required String contentKind,
    required List<int> coveredSections,
    required List<AiMindMapNodeOutput> nodes,
  }) {
    _json = {
      'contentKind': contentKind,
      'coveredSections': coveredSections,
      'nodes': nodes.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiMindMapOutput].
  static const SchemanticType<AiMindMapOutput> $schema =
      _AiMindMapOutputTypeFactory();

  String get contentKind {
    return _json['contentKind'] as String;
  }

  set contentKind(String value) {
    _json['contentKind'] = value;
  }

  List<int> get coveredSections {
    return (_json['coveredSections'] as List).cast<int>();
  }

  set coveredSections(List<int> value) {
    _json['coveredSections'] = value;
  }

  List<AiMindMapNodeOutput> get nodes {
    return (_json['nodes'] as List)
        .map((e) => AiMindMapNodeOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set nodes(List<AiMindMapNodeOutput> value) {
    _json['nodes'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiMindMapOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiMindMapOutputTypeFactory extends SchemanticType<AiMindMapOutput> {
  const _AiMindMapOutputTypeFactory();

  @override
  AiMindMapOutput parse(Object? json) {
    return AiMindMapOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiMindMapOutput',
    definition: $Schema
        .object(
          properties: {
            'contentKind': $Schema.string(),
            'coveredSections': $Schema.list(items: $Schema.integer()),
            'nodes': $Schema.list(
              items: $Schema.fromMap({'\$ref': r'#/$defs/AiMindMapNodeOutput'}),
            ),
          },
          required: ['contentKind', 'coveredSections', 'nodes'],
        )
        .value,
    dependencies: [AiMindMapNodeOutput.$schema],
  );
}

base class AiNarrationFeaturesOutput {
  /// Creates a [AiNarrationFeaturesOutput] from a JSON map.
  factory AiNarrationFeaturesOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiNarrationFeaturesOutput._(this._json);

  AiNarrationFeaturesOutput({
    required double eventDriven,
    required double characterEnsemble,
    required double organization,
    required double geography,
    required double essay,
  }) {
    _json = {
      'eventDriven': eventDriven,
      'characterEnsemble': characterEnsemble,
      'organization': organization,
      'geography': geography,
      'essay': essay,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiNarrationFeaturesOutput].
  static const SchemanticType<AiNarrationFeaturesOutput> $schema =
      _AiNarrationFeaturesOutputTypeFactory();

  double get eventDriven {
    return (_json['eventDriven'] as num).toDouble();
  }

  set eventDriven(double value) {
    _json['eventDriven'] = value;
  }

  double get characterEnsemble {
    return (_json['characterEnsemble'] as num).toDouble();
  }

  set characterEnsemble(double value) {
    _json['characterEnsemble'] = value;
  }

  double get organization {
    return (_json['organization'] as num).toDouble();
  }

  set organization(double value) {
    _json['organization'] = value;
  }

  double get geography {
    return (_json['geography'] as num).toDouble();
  }

  set geography(double value) {
    _json['geography'] = value;
  }

  double get essay {
    return (_json['essay'] as num).toDouble();
  }

  set essay(double value) {
    _json['essay'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiNarrationFeaturesOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiNarrationFeaturesOutputTypeFactory
    extends SchemanticType<AiNarrationFeaturesOutput> {
  const _AiNarrationFeaturesOutputTypeFactory();

  @override
  AiNarrationFeaturesOutput parse(Object? json) {
    return AiNarrationFeaturesOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiNarrationFeaturesOutput',
    definition: $Schema
        .object(
          properties: {
            'eventDriven': $Schema.number(),
            'characterEnsemble': $Schema.number(),
            'organization': $Schema.number(),
            'geography': $Schema.number(),
            'essay': $Schema.number(),
          },
          required: [
            'eventDriven',
            'characterEnsemble',
            'organization',
            'geography',
            'essay',
          ],
        )
        .value,
    dependencies: [],
  );
}

base class AiNarrationPlanOutput {
  /// Creates a [AiNarrationPlanOutput] from a JSON map.
  factory AiNarrationPlanOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiNarrationPlanOutput._(this._json);

  AiNarrationPlanOutput({
    required AiNarrationFeaturesOutput features,
    required String defaultView,
    required List<String> viewOrder,
    required bool wantMap,
  }) {
    _json = {
      'features': features.toJson(),
      'defaultView': defaultView,
      'viewOrder': viewOrder,
      'wantMap': wantMap,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiNarrationPlanOutput].
  static const SchemanticType<AiNarrationPlanOutput> $schema =
      _AiNarrationPlanOutputTypeFactory();

  AiNarrationFeaturesOutput get features {
    return AiNarrationFeaturesOutput.fromJson(
      _json['features'] as Map<String, dynamic>,
    );
  }

  set features(AiNarrationFeaturesOutput value) {
    _json['features'] = value.toJson();
  }

  String get defaultView {
    return _json['defaultView'] as String;
  }

  set defaultView(String value) {
    _json['defaultView'] = value;
  }

  List<String> get viewOrder {
    return (_json['viewOrder'] as List).cast<String>();
  }

  set viewOrder(List<String> value) {
    _json['viewOrder'] = value;
  }

  bool get wantMap {
    return _json['wantMap'] as bool;
  }

  set wantMap(bool value) {
    _json['wantMap'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiNarrationPlanOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiNarrationPlanOutputTypeFactory
    extends SchemanticType<AiNarrationPlanOutput> {
  const _AiNarrationPlanOutputTypeFactory();

  @override
  AiNarrationPlanOutput parse(Object? json) {
    return AiNarrationPlanOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiNarrationPlanOutput',
    definition: $Schema
        .object(
          properties: {
            'features': $Schema.fromMap({
              '\$ref': r'#/$defs/AiNarrationFeaturesOutput',
            }),
            'defaultView': $Schema.string(),
            'viewOrder': $Schema.list(items: $Schema.string()),
            'wantMap': $Schema.boolean(),
          },
          required: ['features', 'defaultView', 'viewOrder', 'wantMap'],
        )
        .value,
    dependencies: [AiNarrationFeaturesOutput.$schema],
  );
}

base class AiGraphEvidenceOutput {
  /// Creates a [AiGraphEvidenceOutput] from a JSON map.
  factory AiGraphEvidenceOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphEvidenceOutput._(this._json);

  AiGraphEvidenceOutput({required int section, required String quote}) {
    _json = {'section': section, 'quote': quote};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphEvidenceOutput].
  static const SchemanticType<AiGraphEvidenceOutput> $schema =
      _AiGraphEvidenceOutputTypeFactory();

  int get section {
    return _json['section'] as int;
  }

  set section(int value) {
    _json['section'] = value;
  }

  String get quote {
    return _json['quote'] as String;
  }

  set quote(String value) {
    _json['quote'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphEvidenceOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphEvidenceOutputTypeFactory
    extends SchemanticType<AiGraphEvidenceOutput> {
  const _AiGraphEvidenceOutputTypeFactory();

  @override
  AiGraphEvidenceOutput parse(Object? json) {
    return AiGraphEvidenceOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphEvidenceOutput',
    definition: $Schema
        .object(
          properties: {'section': $Schema.integer(), 'quote': $Schema.string()},
          required: ['section', 'quote'],
        )
        .value,
    dependencies: [],
  );
}

base class AiGraphEntityOutput {
  /// Creates a [AiGraphEntityOutput] from a JSON map.
  factory AiGraphEntityOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphEntityOutput._(this._json);

  AiGraphEntityOutput({
    required String name,
    required String type,
    required String scope,
    String? identityHint,
    List<String>? aliases,
    String? description,
    String? eventType,
    int? importance,
    required List<AiGraphEvidenceOutput> evidence,
  }) {
    _json = {
      'name': name,
      'type': type,
      'scope': scope,
      'identityHint': ?identityHint,
      'aliases': ?aliases,
      'description': ?description,
      'eventType': ?eventType,
      'importance': ?importance,
      'evidence': evidence.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphEntityOutput].
  static const SchemanticType<AiGraphEntityOutput> $schema =
      _AiGraphEntityOutputTypeFactory();

  String get name {
    return _json['name'] as String;
  }

  set name(String value) {
    _json['name'] = value;
  }

  String get type {
    return _json['type'] as String;
  }

  set type(String value) {
    _json['type'] = value;
  }

  String get scope {
    return _json['scope'] as String;
  }

  set scope(String value) {
    _json['scope'] = value;
  }

  String? get identityHint {
    return _json['identityHint'] as String?;
  }

  set identityHint(String? value) {
    if (value == null) {
      _json.remove('identityHint');
    } else {
      _json['identityHint'] = value;
    }
  }

  List<String>? get aliases {
    return (_json['aliases'] as List?)?.cast<String>();
  }

  set aliases(List<String>? value) {
    if (value == null) {
      _json.remove('aliases');
    } else {
      _json['aliases'] = value;
    }
  }

  String? get description {
    return _json['description'] as String?;
  }

  set description(String? value) {
    if (value == null) {
      _json.remove('description');
    } else {
      _json['description'] = value;
    }
  }

  String? get eventType {
    return _json['eventType'] as String?;
  }

  set eventType(String? value) {
    if (value == null) {
      _json.remove('eventType');
    } else {
      _json['eventType'] = value;
    }
  }

  int? get importance {
    return _json['importance'] as int?;
  }

  set importance(int? value) {
    if (value == null) {
      _json.remove('importance');
    } else {
      _json['importance'] = value;
    }
  }

  List<AiGraphEvidenceOutput> get evidence {
    return (_json['evidence'] as List)
        .map((e) => AiGraphEvidenceOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set evidence(List<AiGraphEvidenceOutput> value) {
    _json['evidence'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphEntityOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphEntityOutputTypeFactory
    extends SchemanticType<AiGraphEntityOutput> {
  const _AiGraphEntityOutputTypeFactory();

  @override
  AiGraphEntityOutput parse(Object? json) {
    return AiGraphEntityOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphEntityOutput',
    definition: $Schema
        .object(
          properties: {
            'name': $Schema.string(),
            'type': $Schema.string(),
            'scope': $Schema.string(),
            'identityHint': $Schema.string(),
            'aliases': $Schema.list(items: $Schema.string()),
            'description': $Schema.string(),
            'eventType': $Schema.string(),
            'importance': $Schema.integer(),
            'evidence': $Schema.list(
              items: $Schema.fromMap({
                '\$ref': r'#/$defs/AiGraphEvidenceOutput',
              }),
            ),
          },
          required: ['name', 'type', 'scope', 'evidence'],
        )
        .value,
    dependencies: [AiGraphEvidenceOutput.$schema],
  );
}

base class AiGraphRelationOutput {
  /// Creates a [AiGraphRelationOutput] from a JSON map.
  factory AiGraphRelationOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphRelationOutput._(this._json);

  AiGraphRelationOutput({
    required String source,
    required String target,
    String? sourceIdentityHint,
    String? targetIdentityHint,
    required String type,
    String? description,
    String? kin,
    required List<AiGraphEvidenceOutput> evidence,
  }) {
    _json = {
      'source': source,
      'target': target,
      'sourceIdentityHint': ?sourceIdentityHint,
      'targetIdentityHint': ?targetIdentityHint,
      'type': type,
      'description': ?description,
      'kin': ?kin,
      'evidence': evidence.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphRelationOutput].
  static const SchemanticType<AiGraphRelationOutput> $schema =
      _AiGraphRelationOutputTypeFactory();

  String get source {
    return _json['source'] as String;
  }

  set source(String value) {
    _json['source'] = value;
  }

  String get target {
    return _json['target'] as String;
  }

  set target(String value) {
    _json['target'] = value;
  }

  String? get sourceIdentityHint {
    return _json['sourceIdentityHint'] as String?;
  }

  set sourceIdentityHint(String? value) {
    if (value == null) {
      _json.remove('sourceIdentityHint');
    } else {
      _json['sourceIdentityHint'] = value;
    }
  }

  String? get targetIdentityHint {
    return _json['targetIdentityHint'] as String?;
  }

  set targetIdentityHint(String? value) {
    if (value == null) {
      _json.remove('targetIdentityHint');
    } else {
      _json['targetIdentityHint'] = value;
    }
  }

  String get type {
    return _json['type'] as String;
  }

  set type(String value) {
    _json['type'] = value;
  }

  String? get description {
    return _json['description'] as String?;
  }

  set description(String? value) {
    if (value == null) {
      _json.remove('description');
    } else {
      _json['description'] = value;
    }
  }

  String? get kin {
    return _json['kin'] as String?;
  }

  set kin(String? value) {
    if (value == null) {
      _json.remove('kin');
    } else {
      _json['kin'] = value;
    }
  }

  List<AiGraphEvidenceOutput> get evidence {
    return (_json['evidence'] as List)
        .map((e) => AiGraphEvidenceOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set evidence(List<AiGraphEvidenceOutput> value) {
    _json['evidence'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphRelationOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphRelationOutputTypeFactory
    extends SchemanticType<AiGraphRelationOutput> {
  const _AiGraphRelationOutputTypeFactory();

  @override
  AiGraphRelationOutput parse(Object? json) {
    return AiGraphRelationOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphRelationOutput',
    definition: $Schema
        .object(
          properties: {
            'source': $Schema.string(),
            'target': $Schema.string(),
            'sourceIdentityHint': $Schema.string(),
            'targetIdentityHint': $Schema.string(),
            'type': $Schema.string(),
            'description': $Schema.string(),
            'kin': $Schema.string(),
            'evidence': $Schema.list(
              items: $Schema.fromMap({
                '\$ref': r'#/$defs/AiGraphEvidenceOutput',
              }),
            ),
          },
          required: ['source', 'target', 'type', 'evidence'],
        )
        .value,
    dependencies: [AiGraphEvidenceOutput.$schema],
  );
}

base class AiGraphExtractionOutput {
  /// Creates a [AiGraphExtractionOutput] from a JSON map.
  factory AiGraphExtractionOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphExtractionOutput._(this._json);

  AiGraphExtractionOutput({
    required List<AiGraphEntityOutput> entities,
    required List<AiGraphRelationOutput> relations,
  }) {
    _json = {
      'entities': entities.map((e) => e.toJson()).toList(),
      'relations': relations.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphExtractionOutput].
  static const SchemanticType<AiGraphExtractionOutput> $schema =
      _AiGraphExtractionOutputTypeFactory();

  List<AiGraphEntityOutput> get entities {
    return (_json['entities'] as List)
        .map((e) => AiGraphEntityOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set entities(List<AiGraphEntityOutput> value) {
    _json['entities'] = value.map((e) => e.toJson()).toList();
  }

  List<AiGraphRelationOutput> get relations {
    return (_json['relations'] as List)
        .map((e) => AiGraphRelationOutput.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  set relations(List<AiGraphRelationOutput> value) {
    _json['relations'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphExtractionOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphExtractionOutputTypeFactory
    extends SchemanticType<AiGraphExtractionOutput> {
  const _AiGraphExtractionOutputTypeFactory();

  @override
  AiGraphExtractionOutput parse(Object? json) {
    return AiGraphExtractionOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphExtractionOutput',
    definition: $Schema
        .object(
          properties: {
            'entities': $Schema.list(
              items: $Schema.fromMap({'\$ref': r'#/$defs/AiGraphEntityOutput'}),
            ),
            'relations': $Schema.list(
              items: $Schema.fromMap({
                '\$ref': r'#/$defs/AiGraphRelationOutput',
              }),
            ),
          },
          required: ['entities', 'relations'],
        )
        .value,
    dependencies: [AiGraphEntityOutput.$schema, AiGraphRelationOutput.$schema],
  );
}

base class AiGraphEntityRefreshItemOutput {
  /// Creates a [AiGraphEntityRefreshItemOutput] from a JSON map.
  factory AiGraphEntityRefreshItemOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphEntityRefreshItemOutput._(this._json);

  AiGraphEntityRefreshItemOutput({
    required String name,
    required String description,
    required List<String> dropAliases,
  }) {
    _json = {
      'name': name,
      'description': description,
      'dropAliases': dropAliases,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphEntityRefreshItemOutput].
  static const SchemanticType<AiGraphEntityRefreshItemOutput> $schema =
      _AiGraphEntityRefreshItemOutputTypeFactory();

  String get name {
    return _json['name'] as String;
  }

  set name(String value) {
    _json['name'] = value;
  }

  String get description {
    return _json['description'] as String;
  }

  set description(String value) {
    _json['description'] = value;
  }

  List<String> get dropAliases {
    return (_json['dropAliases'] as List).cast<String>();
  }

  set dropAliases(List<String> value) {
    _json['dropAliases'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphEntityRefreshItemOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphEntityRefreshItemOutputTypeFactory
    extends SchemanticType<AiGraphEntityRefreshItemOutput> {
  const _AiGraphEntityRefreshItemOutputTypeFactory();

  @override
  AiGraphEntityRefreshItemOutput parse(Object? json) {
    return AiGraphEntityRefreshItemOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphEntityRefreshItemOutput',
    definition: $Schema
        .object(
          properties: {
            'name': $Schema.string(),
            'description': $Schema.string(),
            'dropAliases': $Schema.list(items: $Schema.string()),
          },
          required: ['name', 'description', 'dropAliases'],
        )
        .value,
    dependencies: [],
  );
}

base class AiGraphEntityRefreshOutput {
  /// Creates a [AiGraphEntityRefreshOutput] from a JSON map.
  factory AiGraphEntityRefreshOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphEntityRefreshOutput._(this._json);

  AiGraphEntityRefreshOutput({
    required List<AiGraphEntityRefreshItemOutput> entities,
  }) {
    _json = {'entities': entities.map((e) => e.toJson()).toList()};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphEntityRefreshOutput].
  static const SchemanticType<AiGraphEntityRefreshOutput> $schema =
      _AiGraphEntityRefreshOutputTypeFactory();

  List<AiGraphEntityRefreshItemOutput> get entities {
    return (_json['entities'] as List)
        .map(
          (e) => AiGraphEntityRefreshItemOutput.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  set entities(List<AiGraphEntityRefreshItemOutput> value) {
    _json['entities'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphEntityRefreshOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphEntityRefreshOutputTypeFactory
    extends SchemanticType<AiGraphEntityRefreshOutput> {
  const _AiGraphEntityRefreshOutputTypeFactory();

  @override
  AiGraphEntityRefreshOutput parse(Object? json) {
    return AiGraphEntityRefreshOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphEntityRefreshOutput',
    definition: $Schema
        .object(
          properties: {
            'entities': $Schema.list(
              items: $Schema.fromMap({
                '\$ref': r'#/$defs/AiGraphEntityRefreshItemOutput',
              }),
            ),
          },
          required: ['entities'],
        )
        .value,
    dependencies: [AiGraphEntityRefreshItemOutput.$schema],
  );
}

base class AiGraphLineageVerdictOutput {
  /// Creates a [AiGraphLineageVerdictOutput] from a JSON map.
  factory AiGraphLineageVerdictOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphLineageVerdictOutput._(this._json);

  AiGraphLineageVerdictOutput({
    required int index,
    required String action,
    required String kin,
  }) {
    _json = {'index': index, 'action': action, 'kin': kin};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphLineageVerdictOutput].
  static const SchemanticType<AiGraphLineageVerdictOutput> $schema =
      _AiGraphLineageVerdictOutputTypeFactory();

  int get index {
    return _json['index'] as int;
  }

  set index(int value) {
    _json['index'] = value;
  }

  String get action {
    return _json['action'] as String;
  }

  set action(String value) {
    _json['action'] = value;
  }

  String get kin {
    return _json['kin'] as String;
  }

  set kin(String value) {
    _json['kin'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphLineageVerdictOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphLineageVerdictOutputTypeFactory
    extends SchemanticType<AiGraphLineageVerdictOutput> {
  const _AiGraphLineageVerdictOutputTypeFactory();

  @override
  AiGraphLineageVerdictOutput parse(Object? json) {
    return AiGraphLineageVerdictOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphLineageVerdictOutput',
    definition: $Schema
        .object(
          properties: {
            'index': $Schema.integer(),
            'action': $Schema.string(),
            'kin': $Schema.string(),
          },
          required: ['index', 'action', 'kin'],
        )
        .value,
    dependencies: [],
  );
}

base class AiGraphLineageReviewOutput {
  /// Creates a [AiGraphLineageReviewOutput] from a JSON map.
  factory AiGraphLineageReviewOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphLineageReviewOutput._(this._json);

  AiGraphLineageReviewOutput({
    required List<AiGraphLineageVerdictOutput> relations,
  }) {
    _json = {'relations': relations.map((e) => e.toJson()).toList()};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphLineageReviewOutput].
  static const SchemanticType<AiGraphLineageReviewOutput> $schema =
      _AiGraphLineageReviewOutputTypeFactory();

  List<AiGraphLineageVerdictOutput> get relations {
    return (_json['relations'] as List)
        .map(
          (e) =>
              AiGraphLineageVerdictOutput.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  set relations(List<AiGraphLineageVerdictOutput> value) {
    _json['relations'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphLineageReviewOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphLineageReviewOutputTypeFactory
    extends SchemanticType<AiGraphLineageReviewOutput> {
  const _AiGraphLineageReviewOutputTypeFactory();

  @override
  AiGraphLineageReviewOutput parse(Object? json) {
    return AiGraphLineageReviewOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphLineageReviewOutput',
    definition: $Schema
        .object(
          properties: {
            'relations': $Schema.list(
              items: $Schema.fromMap({
                '\$ref': r'#/$defs/AiGraphLineageVerdictOutput',
              }),
            ),
          },
          required: ['relations'],
        )
        .value,
    dependencies: [AiGraphLineageVerdictOutput.$schema],
  );
}

base class AiGraphMergeReviewOutput {
  /// Creates a [AiGraphMergeReviewOutput] from a JSON map.
  factory AiGraphMergeReviewOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AiGraphMergeReviewOutput._(this._json);

  AiGraphMergeReviewOutput({required List<String> verdicts}) {
    _json = {'verdicts': verdicts};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AiGraphMergeReviewOutput].
  static const SchemanticType<AiGraphMergeReviewOutput> $schema =
      _AiGraphMergeReviewOutputTypeFactory();

  List<String> get verdicts {
    return (_json['verdicts'] as List).cast<String>();
  }

  set verdicts(List<String> value) {
    _json['verdicts'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AiGraphMergeReviewOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AiGraphMergeReviewOutputTypeFactory
    extends SchemanticType<AiGraphMergeReviewOutput> {
  const _AiGraphMergeReviewOutputTypeFactory();

  @override
  AiGraphMergeReviewOutput parse(Object? json) {
    return AiGraphMergeReviewOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AiGraphMergeReviewOutput',
    definition: $Schema
        .object(
          properties: {'verdicts': $Schema.list(items: $Schema.string())},
          required: ['verdicts'],
        )
        .value,
    dependencies: [],
  );
}
