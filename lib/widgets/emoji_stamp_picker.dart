import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../app_theme.dart';
import '../services/custom_stamps.dart';
import '../utils/recent_emojis.dart';

/// 組み込みのオリジナルアイコン（アセット）。カスタムスタンプは Firestore から動的取得。
const List<String> kOriginalStamps = ['bee'];

/// スタンプ／絵文字ピッカーを表示する。
///
/// [onSelected] には絵文字の場合はその文字、オリジナルスタンプの場合は
/// `bee` や `stamp:{docId}` のような識別子が渡る。
Future<void> showEmojiStampPicker({
  required BuildContext context,
  required void Function(String emoji) onSelected,
}) {
  CustomStampsService.instance.start();
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

class _EmojiStampPickerBody extends StatefulWidget {
  final void Function(String emoji) onSelected;
  const _EmojiStampPickerBody({required this.onSelected});

  @override
  State<_EmojiStampPickerBody> createState() => _EmojiStampPickerBodyState();
}

class _EmojiStampPickerBodyState extends State<_EmojiStampPickerBody> {
  bool _uploading = false;

  Widget _stampTile(BuildContext context, {String? asset, String? url, required String value}) {
    return InkWell(
      onTap: () => widget.onSelected(value),
      onLongPress: url == null
          ? null
          : () => _confirmDelete(context, value.substring('stamp:'.length)),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: asset != null
            ? Image.asset(asset, width: 32, height: 32)
            : (url != null
                ? CachedNetworkImage(
                    imageUrl: url,
                    width: 36,
                    height: 36,
                    fit: BoxFit.contain,
                    placeholder: (c, u) => const SizedBox(width: 36, height: 36),
                    errorWidget: (c, u, e) => const Icon(Icons.broken_image, size: 20),
                  )
                : Text(value, style: const TextStyle(fontSize: AppTextSize.emoji))),
      ),
    );
  }

  Widget _addTile(BuildContext context) {
    return InkWell(
      onTap: _uploading ? null : _addStamp,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: context.colors.chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.borderMedium),
        ),
        alignment: Alignment.center,
        child: _uploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.add, size: 22, color: context.colors.textSecondary),
      ),
    );
  }

  Future<void> _addStamp() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (file == null) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      final name = file.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'png';
      await CustomStampsService.instance.addStamp(bytes, ext);
      messenger?.showSnackBar(const SnackBar(content: Text('スタンプを追加しました')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('追加に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context, String stampId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.cardBg,
        title: const Text('スタンプを削除'),
        content: const Text('このオリジナルスタンプを削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await CustomStampsService.instance.deleteStamp(stampId);
      messenger?.showSnackBar(const SnackBar(content: Text('スタンプを削除しました')));
    } catch (e) {
      messenger?.showSnackBar(const SnackBar(content: Text('削除できませんでした（権限がない可能性があります）')));
    }
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
          child: ValueListenableBuilder<List<CustomStamp>>(
            valueListenable: CustomStampsService.instance.stamps,
            builder: (ctx, customStamps, _) {
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                scrollDirection: Axis.horizontal,
                children: [
                  _addTile(ctx),
                  // 組み込みアセットスタンプ（bee 等）
                  for (final s in kOriginalStamps)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _stampTile(ctx,
                          asset: s == 'bee' ? 'assets/logo_beesmileymark.png' : null, value: s),
                    ),
                  // Firestore のカスタムスタンプ
                  for (final cs in customStamps)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _stampTile(ctx, url: cs.url, value: 'stamp:${cs.id}'),
                    ),
                ],
              );
            },
          ),
        ),
        Divider(height: 1, color: context.colors.borderLight),
        Expanded(
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) => widget.onSelected(emoji.emoji),
            config: Config(
              height: double.infinity,
              checkPlatformCompatibility: true,
              emojiTextStyle: TextStyle(
                fontSize: AppTextSize.headline,
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
