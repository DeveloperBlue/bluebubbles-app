import 'dart:convert';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:universal_io/io.dart';

/// Temporary debug-session logger (session 92b7d1). Remove after verification.
class AgentDebugLog {
  static const sessionId = '92b7d1';
  // Android device cannot reach the host via 127.0.0.1 — use LAN ingest.
  static const _ingest = 'http://192.168.1.50:7766/ingest/76285e53-6cc2-4e95-ad04-7767cce89ee4';

  static Future<void> log({
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?> data = const {},
    String runId = 'pre-fix',
  }) async {
    final payload = <String, Object?>{
      'sessionId': sessionId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'runId': runId,
    };
    Logger.info('[agent-debug] $message ${jsonEncode(data)}', tag: 'AgentDebug');
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse(_ingest));
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('X-Debug-Session-Id', sessionId);
      req.add(utf8.encode(jsonEncode(payload)));
      await req.close().timeout(const Duration(seconds: 2));
      client.close(force: true);
    } catch (_) {
      // Best-effort only.
    }
  }
}
