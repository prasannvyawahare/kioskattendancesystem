import 'package:flutter/foundation.dart';

import 'local_database.dart';

/// Single choke point for "something went wrong and nobody's watching a
/// console" -- an unattended kiosk has no attached adb/logcat in the field,
/// so every previously-silent catch block and the global error handlers in
/// main.dart funnel here instead of a bare debugPrint. Writes through to a
/// small persistent table (LocalDatabase.error_logs) that
/// screens/error_log_screen.dart displays, and always also debugPrints so a
/// dev-mode run with a console attached still sees it immediately.
class ErrorLogger {
  ErrorLogger._();

  static Future<void> log(Object error, {StackTrace? stackTrace, String? context}) async {
    final message = error.toString();
    debugPrint(context == null ? 'ErrorLogger: $message' : 'ErrorLogger [$context]: $message');
    if (stackTrace != null) debugPrint(stackTrace.toString());

    try {
      await LocalDatabase.instance.insertErrorLog(
        loggedAt: DateTime.now().toIso8601String(),
        message: message,
        stackTrace: stackTrace?.toString(),
        context: context,
      );
    } catch (e) {
      // The logger itself must never throw (e.g. LocalDatabase not open yet
      // during very early startup) -- a broken logger crashing the app it's
      // meant to keep visible into would defeat the point.
      debugPrint('ErrorLogger: failed to persist log entry: $e');
    }
  }
}
