// Web 用ダウンロード実装。
// HTMLAnchorElement の download 属性を使ってブラウザに保存ダイアログを出させる。
import 'package:web/web.dart' as web;

Future<void> platformDownload(String url, String? suggestedName) async {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..target = '_blank';
  if (suggestedName != null && suggestedName.isNotEmpty) {
    anchor.download = suggestedName;
  } else {
    // 同一オリジンでない場合 download 属性は無視されるが、
    // Firebase Storage 側で Content-Disposition が指定されていればダウンロードされる。
    anchor.download = '';
  }
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
