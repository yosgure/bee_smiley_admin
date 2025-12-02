// iOS/Android用のスタブファイル
// このファイルはiOS/Androidでビルドされる時に使用される
// 実際のダウンロード処理はcsv_export_screen.dartで行われる

void downloadCsvWeb(List<int> bytes, String fileName) {
  // iOS/Androidでは呼ばれない
  // 実際の処理はcsv_export_screen.dartのdownloadCsv内で
  // Share.shareXFilesを使用して行う
}