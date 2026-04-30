import 'package:flutter/material.dart';
import '../app_theme.dart';

/// 確認ダイアログ・スナックバーのファサード。
///
/// 既存の showDialog / SnackBar の生呼び出しを段階的にこちらへ寄せていく。
/// すべての通知系 UI を AlertPalette / AppText / AppSpacing 経由に統一することで、
/// 色とテキストサイズの一貫性、ダーク/ライト両対応を保証する。
class AppFeedback {
  AppFeedback._();

  // ============================================================
  // SnackBar 系
  // ============================================================

  /// 成功通知。緑系背景・短時間表示。
  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    _showSnack(
      context,
      message: message,
      style: context.alerts.success,
      icon: Icons.check_circle_outline,
      duration: duration,
      action: action,
    );
  }

  /// エラー通知。赤/オレンジ系背景・やや長め表示。
  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    _showSnack(
      context,
      message: message,
      style: context.alerts.urgent,
      icon: Icons.error_outline,
      duration: duration,
      action: action,
    );
  }

  /// 警告通知。黄色系背景。
  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _showSnack(
      context,
      message: message,
      style: context.alerts.warning,
      icon: Icons.warning_amber_outlined,
      duration: duration,
      action: action,
    );
  }

  /// 情報通知。青系背景。
  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _showSnack(
      context,
      message: message,
      style: context.alerts.info,
      icon: Icons.info_outline,
      duration: duration,
      action: action,
    );
  }

  static void _showSnack(
    BuildContext context, {
    required String message,
    required AlertStyle style,
    required IconData icon,
    required Duration duration,
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: style.background,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: style.border),
        ),
        content: Row(
          children: [
            Icon(icon, color: style.icon, size: 20),
            AppSpacing.gapSm,
            Expanded(
              child: Text(
                message,
                style: AppText.body.copyWith(color: style.text),
              ),
            ),
          ],
        ),
        action: action,
      ),
    );
  }

  // ============================================================
  // 確認ダイアログ
  // ============================================================

  /// Yes/No 確認ダイアログ。true = 確定、false/null = キャンセル。
  ///
  /// [destructive] が true の場合、確定ボタンが urgent カラーになる（削除など）。
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'OK',
    String cancelLabel = 'キャンセル',
    bool destructive = false,
    IconData? icon,
  }) async {
    final urgent = context.alerts.urgent;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          icon: icon == null
              ? null
              : Icon(
                  icon,
                  color: destructive ? urgent.icon : AppColors.primary,
                  size: 32,
                ),
          title: Text(title, style: AppText.title),
          content: message == null ? null : Text(message, style: AppText.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(cancelLabel),
            ),
            destructive
                ? TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: TextButton.styleFrom(foregroundColor: urgent.icon),
                    child: Text(confirmLabel),
                  )
                : ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(confirmLabel),
                  ),
          ],
        );
      },
    );
    return result ?? false;
  }

  /// 単純な情報ダイアログ。閉じるボタンのみ。
  static Future<void> alert(
    BuildContext context, {
    required String title,
    String? message,
    String closeLabel = 'OK',
    IconData? icon,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          icon: icon == null
              ? null
              : Icon(icon, color: AppColors.primary, size: 32),
          title: Text(title, style: AppText.title),
          content: message == null ? null : Text(message, style: AppText.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(closeLabel),
            ),
          ],
        );
      },
    );
  }

  /// 削除確認のショートカット。destructive=true 固定。
  static Future<bool> confirmDelete(
    BuildContext context, {
    required String target,
    String? extra,
  }) {
    return confirm(
      context,
      icon: Icons.delete_outline,
      title: '$targetを削除しますか？',
      message: extra ?? 'この操作は取り消せません。',
      confirmLabel: '削除',
      destructive: true,
    );
  }
}
