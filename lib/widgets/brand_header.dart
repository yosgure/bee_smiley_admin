import 'package:flutter/material.dart';

/// 公開フォーム共通のブランドヘッダー（ビースマイリーのロゴ）。
/// intake / 体験予約 / 入会前アンケート など保護者向け画面の先頭に置く。
///
/// Flutter Web(CanvasKit) では、非同期デコードした画像が初回表示で描画されず
/// 操作するまで出ないことがある。対策として
///  1) precacheImage で先にデコードしてキャッシュ
///  2) マウント時にフェードイン（TweenAnimationBuilder）で数十フレームを発生させ、
///     その間に確実に描画させる
class BrandHeader extends StatefulWidget {
  final double height;
  const BrandHeader({super.key, this.height = 56});

  @override
  State<BrandHeader> createState() => _BrandHeaderState();
}

class _BrandHeaderState extends State<BrandHeader> {
  static const _logo = AssetImage('assets/logo_beesmiley.png');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(_logo, context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          builder: (context, value, child) =>
              Opacity(opacity: value, child: child),
          child: Image(
            image: _logo,
            height: widget.height,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
