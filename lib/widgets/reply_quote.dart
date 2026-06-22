import 'package:flutter/material.dart';
import '../app_theme.dart';

/// 返信の引用表示。長文は2行で省略し、「もっと見る」で全文展開できる。
/// preview には元メッセージの全文が入っている前提で、展開時に全文を表示する。
/// スタッフ/保護者チャットで共通利用する。
class ReplyQuote extends StatefulWidget {
  final String senderName;
  final String preview;
  final Color bgColor;
  final Color accentColor;

  /// 引用タップで元メッセージへジャンプする場合のコールバック。null ならタップ不可。
  final VoidCallback? onJump;

  const ReplyQuote({
    super.key,
    required this.senderName,
    required this.preview,
    required this.bgColor,
    required this.accentColor,
    this.onJump,
  });

  @override
  State<ReplyQuote> createState() => _ReplyQuoteState();
}

class _ReplyQuoteState extends State<ReplyQuote> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final previewStyle =
        TextStyle(fontSize: AppTextSize.small, color: context.colors.textSecondary);

    final inner = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
      decoration: BoxDecoration(
        color: widget.bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: widget.accentColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.senderName,
            style: TextStyle(
              fontSize: AppTextSize.caption,
              fontWeight: FontWeight.bold,
              color: widget.accentColor,
            ),
          ),
          const SizedBox(height: 1),
          LayoutBuilder(
            builder: (context, constraints) {
              // 2行を超えるか判定し、超える場合のみ「もっと見る」を表示
              final tp = TextPainter(
                text: TextSpan(text: widget.preview, style: previewStyle),
                maxLines: 2,
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: constraints.maxWidth);
              final overflowing = tp.didExceedMaxLines;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.preview,
                    maxLines: _expanded ? null : 2,
                    overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
                    style: previewStyle,
                  ),
                  if (overflowing)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _expanded ? '閉じる' : 'もっと見る',
                          style: TextStyle(
                            fontSize: AppTextSize.caption,
                            fontWeight: FontWeight.bold,
                            color: widget.accentColor,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );

    if (widget.onJump == null) return inner;
    return InkWell(
      onTap: widget.onJump,
      borderRadius: BorderRadius.circular(6),
      child: inner,
    );
  }
}
