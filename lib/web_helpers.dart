// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';

void setupHtmlDropListeners({
  required void Function(bool) onDragStateChanged,
  required void Function(String name, List<int> bytes, int size) onFileDropped,
  required List<StreamSubscription?> subscriptions,
}) {
  final body = html.document.body;
  if (body == null) return;

  subscriptions.add(body.onDragOver.listen((event) {
    event.preventDefault();
    event.stopPropagation();
    onDragStateChanged(true);
  }));

  subscriptions.add(body.onDragLeave.listen((event) {
    event.preventDefault();
    event.stopPropagation();
    if (event.relatedTarget == null) {
      onDragStateChanged(false);
    }
  }));

  subscriptions.add(body.onDrop.listen((event) {
    event.preventDefault();
    event.stopPropagation();
    onDragStateChanged(false);

    final files = event.dataTransfer.files;
    if (files == null || files.isEmpty) return;

    for (final file in files) {
      final reader = html.FileReader();
      final fileName = file.name;
      reader.onLoadEnd.listen((_) {
        if (reader.result == null) return;
        final bytes = Uint8List.fromList(
          (reader.result as List<int>),
        );
        onFileDropped(fileName, bytes, file.size);
      });
      reader.readAsArrayBuffer(file);
    }
  }));
}
