// Web 用ダウンロード実装。
// 重要: `<a download>` はクロスオリジン URL では無視される（ブラウザの仕様）。
// Firebase Storage (firebasestorage.googleapis.com) は別オリジンのため、
// 単純な anchor では効かない。fetch でファイル本体を取得して Blob URL を作り、
// 同一オリジン化してから download 属性を効かせる必要がある。
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

Future<void> platformDownload(String url, String? suggestedName) async {
  // 1. ファイル本体を取得
  final res = await http.get(Uri.parse(url));
  if (res.statusCode != 200) {
    throw Exception('download failed: ${res.statusCode}');
  }
  // 2. Blob を作って Blob URL に変換（同一オリジン扱いになる）
  final bytes = Uint8List.fromList(res.bodyBytes);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(
      type: res.headers['content-type'] ?? 'application/octet-stream',
    ),
  );
  final blobUrl = web.URL.createObjectURL(blob);
  // 3. anchor で download 属性を効かせる
  final fileName = (suggestedName != null && suggestedName.isNotEmpty)
      ? suggestedName
      : _guessFileName(url);
  final anchor = web.HTMLAnchorElement()
    ..href = blobUrl
    ..download = fileName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // 4. メモリ解放
  web.URL.revokeObjectURL(blobUrl);
}

String _guessFileName(String url) {
  try {
    // Firebase Storage URL: /o/chat_uploads%2F{room}%2F{filename}?alt=media&...
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    final last = segments.isEmpty ? '' : segments.last;
    final decoded = Uri.decodeComponent(last);
    return decoded.split('/').last;
  } catch (_) {
    return 'download';
  }
}
