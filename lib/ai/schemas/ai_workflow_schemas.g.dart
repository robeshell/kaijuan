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
