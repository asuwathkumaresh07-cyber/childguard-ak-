import 'package:flutter/material.dart';

const userFacingError = 'Error. Please try again.';

void reportAppError(String action, Object error, [StackTrace? stackTrace]) {
  debugPrint('Family Guard $action failed: $error');
  if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
}

void showAppError(BuildContext context, String action, Object error) {
  reportAppError(action, error);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text(userFacingError)));
}
