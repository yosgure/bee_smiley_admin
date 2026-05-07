// 条件付きインポートのフォールバック（実際には使われない想定）。
Future<void> platformDownload(String url, String? suggestedName) async {
  throw UnsupportedError('downloadFile is not supported on this platform');
}
