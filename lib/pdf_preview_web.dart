import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';

Widget buildWebPdfViewer(String url) {
  return _WebPdfViewer(url: url);
}

class _WebPdfViewer extends StatefulWidget {
  final String url;
  const _WebPdfViewer({required this.url});

  @override
  State<_WebPdfViewer> createState() => _WebPdfViewerState();
}

class _WebPdfViewerState extends State<_WebPdfViewer> {
  late final String _viewType;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'pdf-iframe-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    final viewerUrl =
        'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(widget.url)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe = web.HTMLIFrameElement()
        ..src = viewerUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      iframe.onLoad.listen((_) {
        if (mounted) setState(() => _loaded = true);
      });
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HtmlElementView(viewType: _viewType),
        if (!_loaded)
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
      ],
    );
  }
}
