import 'dart:async';

void setupHtmlDropListeners({
  required void Function(bool) onDragStateChanged,
  required void Function(String name, List<int> bytes, int size) onFileDropped,
  required List<StreamSubscription?> subscriptions,
}) {
  // No-op on non-web platforms
}
