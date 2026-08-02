import 'package:http/http.dart' as http;

http.Client createDefaultRemoteClient() => http.Client();

http.Client createLenientRemoteClient() => http.Client();

DateTime? parseRemoteHttpDate(String? value) => null;

String? remoteTlsError(Object error) => null;
