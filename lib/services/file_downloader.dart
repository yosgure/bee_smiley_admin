// プラットフォーム別ダウンロードヘルパ。
// Web では `<a download>` を使って強制ダウンロード、それ以外は url_launcher。
import 'file_downloader_stub.dart'
    if (dart.library.js_interop) 'file_downloader_web.dart'
    if (dart.library.io) 'file_downloader_io.dart';

/// プラットフォーム差を吸収してファイルをダウンロードする。
/// Web: anchor タグの download 属性で強制ダウンロード。
/// Mobile/Desktop: 外部アプリで URL を開く（OS 任せ）。
Future<void> downloadFile(String url, {String? suggestedName}) =>
    platformDownload(url, suggestedName);
