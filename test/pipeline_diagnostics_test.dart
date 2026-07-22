import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/core/pipeline_diagnostics.dart';
import 'package:kaika/library/import/import_models.dart';
import 'package:kaika/readers/book/foliate_js_bridge.dart';

void main() {
  setUp(() {
    PipelineDiagnostics.instance.clear();
  });

  test('ImportPipelineTrace records exportable diagnostics', () {
    final trace = ImportPipelineTrace(
      pipeline: 'book',
      sourcePath: '/tmp/sample.epub',
    );
    trace.mark('validated');
    trace.mark('content-staged');

    final text = PipelineDiagnostics.instance.exportText();
    expect(text, contains('[book][sample.epub] step=validated'));
    expect(text, contains('step=content-staged'));
    expect(PipelineDiagnostics.instance.length, 2);
  });

  test('FoliateExternalLink accepts only http(s)/mailto', () {
    final https = FoliateExternalLink.fromHandlerArguments([
      {'href': 'https://example.com/path'},
    ]);
    expect(https?.uri?.host, 'example.com');

    final mail = FoliateExternalLink.fromHandlerArguments([
      {'href': 'mailto:a@b.com'},
    ]);
    expect(mail?.uri?.scheme, 'mailto');

    final file = FoliateExternalLink.fromHandlerArguments([
      {'href': 'file:///tmp/x'},
    ]);
    expect(file?.uri, isNull);

    final empty = FoliateExternalLink.fromHandlerArguments([
      {'href': ''},
    ]);
    expect(empty, isNull);
  });
}
