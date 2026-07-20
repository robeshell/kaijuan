import 'bootstrap.dart';

/// Back-compatible redirect to the unified [bootstrap].
///
/// Old `--flavor comic -t lib/main_comic.dart` invocations still compile and
/// run the same single App.
Future<void> main() => bootstrap();
