// Mobile / Desktop 用ダウンロード実装（url_launcher）。
import 'package:url_launcher/url_launcher.dart';

Future<void> platformDownload(String url, String? suggestedName) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
