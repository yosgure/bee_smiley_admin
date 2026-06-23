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

/// 組み込みアセットスタンプの画像パス解決。
String? _assetForStamp(String value) =>
    value == 'bee' ? 'assets/logo_beesmileymark.png' : null;

/// ギャラリーから画像を選んでスタンプを登録する。成功で true。
/// ユーザーがキャンセルした場合は false（UI 側で uploading 表示を畳むため）。
Future<bool> pickAndAddStamp() async {
  final picker = ImagePicker();
  final file =
      await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
  if (file == null) return false;
  final bytes = await file.readAsBytes();
  final name = file.name;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'png';
  await CustomStampsService.instance.addStamp(bytes, ext);
  return true;
}

/// スタンプ削除の確認ダイアログ → 削除実行。削除できたら true。
Future<bool> confirmDeleteStamp(BuildContext context, String stampId) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.colors.cardBg,
      title: const Text('スタンプを削除'),
      content: const Text('このオリジナルスタンプを削除しますか？'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('削除'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await CustomStampsService.instance.deleteStamp(stampId);
    messenger
        ?.showSnackBar(const SnackBar(content: Text('スタンプを削除しました')));
    return true;
  } catch (e) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('削除できませんでした（権限がない可能性があります）')));
    return false;
  }
}

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
  /// 0 = 絵文字, 1 = スタンプ
  int _tab = 0;
  bool _uploading = false;
  bool _editing = false;

  // ---- 上部タブ -------------------------------------------------------------

  Widget _segment(BuildContext context, String label, int index) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() {
        _tab = index;
        if (index == 0) _editing = false; // 絵文字タブでは整理モードを解除
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTextSize.bodyMd,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _tabBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: context.colors.chipBg,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segment(context, '絵文字', 0),
                _segment(context, 'オリジナル', 1),
              ],
            ),
          ),
          const Spacer(),
          // スタンプタブのときだけ「整理」トグルを出す
          if (_tab == 1)
            TextButton(
              onPressed: () => setState(() => _editing = !_editing),
              child: Text(
                _editing ? '完了' : '整理',
                style: TextStyle(
                  color: _editing ? AppColors.error : AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- スタンプタブ（グリッド） ---------------------------------------------

  void _selectStamp(String value) => widget.onSelected(value);

  Future<void> _addStamp() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      setState(() => _uploading = true);
      final added = await pickAndAddStamp();
      if (added) {
        messenger
            ?.showSnackBar(const SnackBar(content: Text('スタンプを追加しました')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('追加に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _cellFrame(BuildContext context, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.scaffoldBgAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _addCell(BuildContext context) {
    return InkWell(
      onTap: _uploading ? null : _addStamp,
      borderRadius: BorderRadius.circular(12),
      child: _cellFrame(
        context,
        child: _uploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add,
                      size: 24, color: context.colors.textSecondary),
                  const SizedBox(height: 2),
                  Text('追加',
                      style: TextStyle(
                          fontSize: AppTextSize.caption,
                          color: context.colors.textSecondary)),
                ],
              ),
      ),
    );
  }

  Widget _assetCell(BuildContext context, String value, String asset) {
    return InkWell(
      onTap: _editing ? null : () => _selectStamp(value),
      borderRadius: BorderRadius.circular(12),
      child:
          _cellFrame(context, child: Image.asset(asset, width: 40, height: 40)),
    );
  }

  Widget _customCell(BuildContext context, CustomStamp cs) {
    final value = 'stamp:${cs.id}';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: _editing ? null : () => _selectStamp(value),
          onLongPress: () => confirmDeleteStamp(context, cs.id),
          borderRadius: BorderRadius.circular(12),
          child: _cellFrame(
            context,
            child: CachedNetworkImage(
              imageUrl: cs.url,
              width: 44,
              height: 44,
              fit: BoxFit.contain,
              placeholder: (c, u) => const SizedBox(width: 44, height: 44),
              errorWidget: (c, u, e) => const Icon(Icons.broken_image, size: 22),
            ),
          ),
        ),
        if (_editing)
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => confirmDeleteStamp(context, cs.id),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.cardBg, width: 2),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stampGrid(BuildContext context) {
    return ValueListenableBuilder<List<CustomStamp>>(
      valueListenable: CustomStampsService.instance.stamps,
      builder: (ctx, customStamps, _) {
        return GridView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 76,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          children: [
            if (!_editing) _addCell(ctx),
            for (final s in kOriginalStamps)
              _assetCell(ctx, s, _assetForStamp(s)!),
            for (final cs in customStamps) _customCell(ctx, cs),
          ],
        );
      },
    );
  }

  // ---- 絵文字タブ -----------------------------------------------------------

  Widget _emojiGrid(BuildContext context) {
    final cardBg = context.colors.cardBg;
    final textPrimary = context.colors.textPrimary;
    final textSecondary = context.colors.textSecondary;
    return EmojiPicker(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 2),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.borderMedium,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        _tabBar(context),
        Divider(height: 1, color: context.colors.borderLight),
        Expanded(
          child: IndexedStack(
            index: _tab,
            sizing: StackFit.expand,
            children: [
              _emojiGrid(context),
              _stampGrid(context),
            ],
          ),
        ),
      ],
    );
  }
}
