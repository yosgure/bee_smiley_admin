import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 破壊的一括操作に「元に戻す」SnackBar を付けるための共通サービス。
///
/// 使い方:
/// ```
/// await UndoService.run<_Snap>(
///   context: context,
///   label: '前週のシフトをコピー',
///   captureSnapshot: () async => await _capture(),
///   execute: () async => await _doCopy(),
///   undo: (snap) async => await _restore(snap),
/// );
/// ```
///
/// スナップショットはメモリ保持のみ（ページ離脱/リロードで失効）。
/// 書き込みコストを抑えるため、Firestore への一時書き出しは行わない。
class UndoService {
  /// [captureSnapshot] を呼んでから [execute] を実行し、
  /// 指定 [window] の間 "元に戻す" ボタン付き SnackBar を表示する。
  /// ボタンが押されたら [undo] にスナップショットを渡して復元する。
  static Future<void> run<S>({
    required BuildContext context,
    required String label,
    required Future<S> Function() captureSnapshot,
    required Future<void> Function() execute,
    required Future<void> Function(S snapshot) undo,
    Duration window = const Duration(seconds: 30),
    String? doneMessage,
  }) async {
    final S snapshot;
    try {
      snapshot = await captureSnapshot();
    } catch (e) {
      // スナップショット失敗時は操作自体を中止（安全側）
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('事前スナップショット失敗: $e')),
        );
      }
      rethrow;
    }

    await execute();

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(doneMessage ?? '$label を実行しました'),
        duration: window,
        action: SnackBarAction(
          label: '元に戻す',
          onPressed: () async {
            try {
              await undo(snapshot);
              if (context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('元に戻しました'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('復元に失敗しました: $e')),
                );
              }
            }
          },
        ),
      ),
    );
  }

  /// 単一ドキュメント削除 + Undo のショートカット。
  /// [docRef] を削除し、"元に戻す" で同じ ID に元データを書き戻す。
  /// [postDelete] / [postRestore] は UI 再読み込み等の後処理に使う。
  static Future<void> deleteDoc({
    required BuildContext context,
    required DocumentReference docRef,
    required String label,
    Duration window = const Duration(seconds: 30),
    Future<void> Function()? postDelete,
    Future<void> Function()? postRestore,
    String? doneMessage,
  }) async {
    await run<Map<String, dynamic>?>(
      context: context,
      label: label,
      doneMessage: doneMessage,
      window: window,
      captureSnapshot: () async {
        final snap = await docRef.get();
        return snap.data() as Map<String, dynamic>?;
      },
      execute: () async {
        await docRef.delete();
        await postDelete?.call();
      },
      undo: (data) async {
        if (data != null) {
          await docRef.set(data);
          await postRestore?.call();
        }
      },
    );
  }
}
