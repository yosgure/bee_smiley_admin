import 'dart:math' as math;
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../utils/recent_emojis.dart';

/// オリジナルアイコン一覧（今後増やす場合はここに追加）
const List<String> kOriginalStamps = ['bee'];

Future<void> showEmojiStampPicker({
  required BuildContext context,
  required void Function(String emoji) onSelected,
}) {
  final mq = MediaQuery.of(context);
  final h = math.min(mq.size.height * 0.7, 560.0);
  final cardBg = context.colors.cardBg;
  return showModalBottomSheet(
    context: context,
    backgroundColor: cardBg,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: h, minHeight: h, maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        top: false,
        child: Material(
          color: cardBg,
          elevation: 0,
          child: _EmojiStampPickerBody(
            onSelected: (emoji) async {
              await RecentEmojis.add(emoji);
              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              onSelected(emoji);
            },
          ),
        ),
      );
    },
  );
}

class _EmojiStampPickerBody extends StatelessWidget {
  final void Function(String emoji) onSelected;
  const _EmojiStampPickerBody({required this.onSelected});

  Widget _stampTile(BuildContext context, String s) {
    return InkWell(
      onTap: () => onSelected(s),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: s == 'bee'
            ? Image.asset('assets/logo_beesmileymark.png', width: 32, height: 32)
            : Text(s, style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = context.colors.cardBg;
    final textPrimary = context.colors.textPrimary;
    final textSecondary = context.colors.textSecondary;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.borderMedium,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(
          height: 50,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            scrollDirection: Axis.horizontal,
            itemCount: kOriginalStamps.length,
            itemBuilder: (ctx, i) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _stampTile(ctx, kOriginalStamps[i]),
            ),
          ),
        ),
        Divider(height: 1, color: context.colors.borderLight),
        Expanded(
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) => onSelected(emoji.emoji),
            config: Config(
              height: double.infinity,
              checkPlatformCompatibility: true,
              emojiTextStyle: TextStyle(
                fontSize: 24,
                color: textPrimary,
              ),
              emojiViewConfig: EmojiViewConfig(
                columns: 8,
                emojiSizeMax: 28,
                backgroundColor: cardBg,
                gridPadding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              categoryViewConfig: CategoryViewConfig(
                backgroundColor: cardBg,
                indicatorColor: AppColors.primary,
                iconColor: textSecondary,
                iconColorSelected: AppColors.primary,
                dividerColor: Colors.transparent,
                recentTabBehavior: RecentTabBehavior.NONE,
              ),
              bottomActionBarConfig: const BottomActionBarConfig(
                enabled: false,
              ),
              searchViewConfig: SearchViewConfig(
                backgroundColor: cardBg,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
