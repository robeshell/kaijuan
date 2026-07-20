import 'bootstrap.dart';

/// Back-compatible redirect to the unified [bootstrap].
///
/// Old `--flavor book -t lib/main_book.dart` invocations still compile and run
/// the same single App.
Future<void> main() => bootstrap();
