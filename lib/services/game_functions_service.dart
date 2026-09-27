import 'package:cloud_functions/cloud_functions.dart';

/// All state changing game operations go through authenticated callable
/// Functions. The client never decides a balance, owner or rent amount.
class GameFunctionsService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'europe-west1',
  );

  static void useEmulator(String host, int port) {
    _functions.useFunctionsEmulator(host, port);
  }

  static Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) async {
    final result = await _functions.httpsCallable(name).call(data);
    final raw = result.data;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}
