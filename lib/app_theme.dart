import 'package:flutter/material.dart';

// ================================================
// ブランドカラー（テーマ非依存の固定色）
// 旧 Material Blue 基調。primaryDark / primaryLight / secondaryDark / onSecondary
// などのトーン違いはトークン整備の一環で残す（既存コードは継続して primary を使う）。
// ================================================
class AppColors {
  // Blue（プライマリ）
  static const Color primary = Color(0xFF1976D2); // blue 700
  static const Color primaryDark = Color(0xFF0D47A1); // blue 900（hover/pressed）
  static const Color primaryLight = Color(0xFF64B5F6); // blue 300（背景アクセント）
  static const Color onPrimary = Colors.white;

  // Indigo（セカンダリ）
  static const Color secondary = Color(0xFF3F51B5); // indigo 500
  static const Color secondaryDark = Color(0xFF283593); // indigo 800
  static const Color onSecondary = Colors.white;

  // 機能色
  static const MaterialColor accent = Colors.orange;
  static const Color warning = Color(0xFFFFA726);
  static const Color error = Color(0xFFE53935);
  static const Color success = Color(0xFF43A047);
  static const Color info = Color(0xFF1E88E5);

  // トーン違い（旧 Colors.red.shade100 / .shade800 等の置換先）
  // 100 系 = 淡い背景、400 系 = 罫線/アイコン、800 系 = 濃いテキスト/強調
  static const Color errorBg = Color(0xFFFDEBE9); // 旧 red.shade50/100
  static const Color errorBorder = Color(0xFFEF5350); // 旧 red.shade300/400
  static const Color errorDark = Color(0xFFB71C1C); // 旧 red.shade800/900
  static const Color successBg = Color(0xFFE8F5E9);
  static const Color successBorder = Color(0xFF66BB6A);
  static const Color successDark = Color(0xFF1B5E20);
  static const Color warningBg = Color(0xFFFFF8E1);
  static const Color warningBorder = Color(0xFFFFB300);
  static const Color warningDark = Color(0xFFE65100);
  static const Color infoBg = Color(0xFFE3F2FD);
  static const Color infoBorder = Color(0xFF42A5F5);
  static const Color infoDark = Color(0xFF0D47A1);
  // AI / 紫アクセント（context.colors.aiAccent と統一）
  static const Color aiAccent = Color(0xFF7C3AED);
  static const Color aiAccentBg = Color(0xFFEDE7F6);

  // 後方互換（旧 Colors.blue 互換が必要なレガシーコード用、移行完了後に削除予定）
  static const Color legacyBlue = Color(0xFF1E88E5);
  static const Color background = Colors.white;
  static const Color surface = Colors.white;
  static const Color textMain = Colors.black87;
  static const Color textSub = Colors.grey;
  static const Color inputFill = Color(0xFFF3F4F6);
}

// ================================================
// タイプスケール
// fontSize: 数値直書きを禁止し、AppTextSize.* または Theme.of(context).textTheme 経由に統一する。
// 主軸 5 段（caption/body/bodyLarge/title/display）に加え、既存実装での頻出値を補助スケール
// として定義しておく。新規コードは可能なかぎり主軸 5 段を使用する。
//
//   主軸:
//     caption    11
//     body       13
//     bodyLarge  15
//     title      17
//     display    22
//   補助（既存互換用、新規利用は最小限に）:
//     xxs  9 / xs 10 / small 12 / bodyMd 14 / titleSm 16 / titleLg 18 / xl 20 /
//     headline 24 / hero 28 / heroLg 32 / heroXl 38
// ================================================
class AppTextSize {
  // 主軸
  static const double caption = 11;
  static const double body = 13;
  static const double bodyLarge = 15;
  static const double title = 17;
  static const double display = 22;

  // 補助スケール（既存実装の互換維持）
  static const double xxs = 9;
  static const double xs = 10;
  static const double small = 12;
  static const double bodyMd = 14;
  static const double titleSm = 16;
  static const double titleLg = 18;
  static const double xl = 20;
  static const double headline = 24;
  static const double hero = 28;
  static const double heroLg = 32;
  static const double heroLg2 = 36;
  static const double heroXl = 38;
  static const double emoji = 26;
}

class AppText {
  static const TextStyle caption = TextStyle(
    fontSize: AppTextSize.caption,
    fontWeight: FontWeight.w400,
    fontFamily: 'NotoSansJP',
    height: 1.4,
  );
  static const TextStyle body = TextStyle(
    fontSize: AppTextSize.body,
    fontWeight: FontWeight.w400,
    fontFamily: 'NotoSansJP',
    height: 1.5,
  );
  static const TextStyle bodyLarge = TextStyle(
    fontSize: AppTextSize.bodyLarge,
    fontWeight: FontWeight.w400,
    fontFamily: 'NotoSansJP',
    height: 1.5,
  );
  static const TextStyle title = TextStyle(
    fontSize: AppTextSize.title,
    fontWeight: FontWeight.w600,
    fontFamily: 'NotoSansJP',
    height: 1.4,
  );
  static const TextStyle display = TextStyle(
    fontSize: AppTextSize.display,
    fontWeight: FontWeight.w700,
    fontFamily: 'NotoSansJP',
    height: 1.3,
  );

  static TextTheme buildTextTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      labelSmall: caption.copyWith(color: textSecondary),
      bodySmall: caption.copyWith(color: textSecondary),
      bodyMedium: body.copyWith(color: textPrimary),
      bodyLarge: bodyLarge.copyWith(color: textPrimary),
      titleSmall: bodyLarge.copyWith(color: textPrimary, fontWeight: FontWeight.w600),
      titleMedium: title.copyWith(color: textPrimary),
      titleLarge: title.copyWith(color: textPrimary, fontSize: 19),
      headlineSmall: display.copyWith(color: textPrimary, fontSize: 20),
      headlineMedium: display.copyWith(color: textPrimary),
      headlineLarge: display.copyWith(color: textPrimary, fontSize: 26),
      displaySmall: display.copyWith(color: textPrimary, fontSize: 26),
      displayMedium: display.copyWith(color: textPrimary, fontSize: 32),
      displayLarge: display.copyWith(color: textPrimary, fontSize: 38),
    );
  }
}

// ================================================
// スペーシングトークン（4 / 8 / 12 / 16 / 24 / 32）
// EdgeInsets.all(数値) 直書きの代わりに使う。
// ================================================
class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // 頻出 EdgeInsets のプリセット
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets pagePadding = EdgeInsets.all(lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets dialogPadding = EdgeInsets.fromLTRB(xl, xl, xl, lg);
  static const EdgeInsets listItemPadding =
      EdgeInsets.symmetric(horizontal: lg, vertical: md);

  // ギャップ用 SizedBox
  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
  static const SizedBox gapXl = SizedBox(width: xl, height: xl);
}

/// レスポンシブ対応のブレークポイント定数
class AppBreakpoints {
  static const double tablet = 600;
  static const double desktop = 800;
}

class AppStyles {
  static final BorderRadius radius = BorderRadius.circular(12);
  static final BorderRadius radiusSmall = BorderRadius.circular(8);
}

// ================================================
// セマンティックカラートークン（ライト/ダーク対応）
// ================================================
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  // 背景系
  final Color scaffoldBg;
  final Color scaffoldBgAlt;
  final Color cardBg;
  final Color dialogBg;
  final Color inputFill;
  final Color hoverBg;

  // 罫線・区切り線
  final Color borderLight;
  final Color borderMedium;
  final Color dividerColor;

  // テキスト
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textHint;
  final Color textOnPrimary;

  // アイコン
  final Color iconDefault;
  final Color iconMuted;

  // AI機能アクセント
  final Color aiAccent;
  final Color aiAccentBg;
  final Color aiGradientStart;
  final Color aiGradientEnd;

  // チャット
  final Color chatMyBubble;
  final Color chatMyBubbleText;
  final Color chatOtherBubble;
  final Color chatOtherBubbleText;

  // ナビゲーション
  final Color navRailBg;

  // その他
  final Color shadow;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color chipBg;
  final Color tagBg;

  const AppColorScheme({
    required this.scaffoldBg,
    required this.scaffoldBgAlt,
    required this.cardBg,
    required this.dialogBg,
    required this.inputFill,
    required this.hoverBg,
    required this.borderLight,
    required this.borderMedium,
    required this.dividerColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textHint,
    required this.textOnPrimary,
    required this.iconDefault,
    required this.iconMuted,
    required this.aiAccent,
    required this.aiAccentBg,
    required this.aiGradientStart,
    required this.aiGradientEnd,
    required this.chatMyBubble,
    required this.chatMyBubbleText,
    required this.chatOtherBubble,
    required this.chatOtherBubbleText,
    required this.navRailBg,
    required this.shadow,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.chipBg,
    required this.tagBg,
  });

  // ライトモード
  factory AppColorScheme.light() => AppColorScheme(
        scaffoldBg: Colors.white,
        scaffoldBgAlt: const Color(0xFFF2F2F7),
        cardBg: Colors.white,
        dialogBg: Colors.white,
        inputFill: const Color(0xFFF3F4F6),
        hoverBg: const Color(0xFFF9FAFB),
        borderLight: Colors.grey.shade200,
        borderMedium: Colors.grey.shade300,
        dividerColor: Colors.grey.shade200,
        textPrimary: Colors.black87,
        textSecondary: Colors.grey.shade600,
        textTertiary: Colors.grey.shade500,
        textHint: Colors.grey.shade400,
        textOnPrimary: Colors.white,
        iconDefault: Colors.grey.shade600,
        iconMuted: Colors.grey.shade400,
        aiAccent: const Color(0xFF7C3AED),
        aiAccentBg: const Color(0xFF7C3AED).withOpacity(0.08),
        aiGradientStart: const Color(0xFF7C3AED),
        aiGradientEnd: const Color(0xFFEC4899),
        // ライト: 旧パステル青を維持
        chatMyBubble: const Color(0xFFD6EEFF),
        chatMyBubbleText: Colors.black87,
        chatOtherBubble: const Color(0xFFF1F3F4),
        chatOtherBubbleText: Colors.black87,
        navRailBg: Colors.white,
        shadow: Colors.black.withOpacity(0.05),
        skeletonBase: Colors.grey.shade200,
        skeletonHighlight: Colors.grey.shade100,
        chipBg: Colors.grey.shade100,
        tagBg: Colors.grey.shade50,
      );

  // ダークモード
  factory AppColorScheme.dark() => AppColorScheme(
        scaffoldBg: const Color(0xFF121212),
        scaffoldBgAlt: const Color(0xFF1A1A1A),
        cardBg: const Color(0xFF1E1E1E),
        dialogBg: const Color(0xFF2C2C2C),
        inputFill: const Color(0xFF2A2A2A),
        hoverBg: const Color(0xFF252525),
        borderLight: const Color(0xFF3A3A3A),
        borderMedium: const Color(0xFF4A4A4A),
        dividerColor: const Color(0xFF3A3A3A),
        textPrimary: const Color(0xFFE0E0E0),
        textSecondary: Colors.grey.shade400,
        textTertiary: Colors.grey.shade500,
        textHint: Colors.grey.shade600,
        textOnPrimary: Colors.white,
        iconDefault: Colors.grey.shade400,
        iconMuted: Colors.grey.shade600,
        aiAccent: const Color(0xFF9B6BFF),
        aiAccentBg: const Color(0xFF7C3AED).withOpacity(0.15),
        aiGradientStart: const Color(0xFF9B6BFF),
        aiGradientEnd: const Color(0xFFF472B6),
        // ダーク: AI相談タブと同じ落ち着いたトーンに合わせる。
        // 旧 #1565C0 のベタ青は長文で目に痛いので、彩度を抑えた青系に。
        chatMyBubble: const Color(0xFF1F3A55), // 落ち着いたダークブルー
        chatMyBubbleText: const Color(0xFFE3F2FD),
        chatOtherBubble: const Color(0xFF2C2C2E), // AI相談カード相当
        chatOtherBubbleText: const Color(0xFFE0E0E0),
        navRailBg: const Color(0xFF1A1A1A),
        shadow: Colors.black.withOpacity(0.3),
        skeletonBase: const Color(0xFF2A2A2A),
        skeletonHighlight: const Color(0xFF3A3A3A),
        chipBg: const Color(0xFF2C2C2C),
        tagBg: const Color(0xFF252525),
      );

  @override
  AppColorScheme copyWith({
    Color? scaffoldBg,
    Color? scaffoldBgAlt,
    Color? cardBg,
    Color? dialogBg,
    Color? inputFill,
    Color? hoverBg,
    Color? borderLight,
    Color? borderMedium,
    Color? dividerColor,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textHint,
    Color? textOnPrimary,
    Color? iconDefault,
    Color? iconMuted,
    Color? aiAccent,
    Color? aiAccentBg,
    Color? aiGradientStart,
    Color? aiGradientEnd,
    Color? chatMyBubble,
    Color? chatMyBubbleText,
    Color? chatOtherBubble,
    Color? chatOtherBubbleText,
    Color? navRailBg,
    Color? shadow,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? chipBg,
    Color? tagBg,
  }) {
    return AppColorScheme(
      scaffoldBg: scaffoldBg ?? this.scaffoldBg,
      scaffoldBgAlt: scaffoldBgAlt ?? this.scaffoldBgAlt,
      cardBg: cardBg ?? this.cardBg,
      dialogBg: dialogBg ?? this.dialogBg,
      inputFill: inputFill ?? this.inputFill,
      hoverBg: hoverBg ?? this.hoverBg,
      borderLight: borderLight ?? this.borderLight,
      borderMedium: borderMedium ?? this.borderMedium,
      dividerColor: dividerColor ?? this.dividerColor,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textHint: textHint ?? this.textHint,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      iconDefault: iconDefault ?? this.iconDefault,
      iconMuted: iconMuted ?? this.iconMuted,
      aiAccent: aiAccent ?? this.aiAccent,
      aiAccentBg: aiAccentBg ?? this.aiAccentBg,
      aiGradientStart: aiGradientStart ?? this.aiGradientStart,
      aiGradientEnd: aiGradientEnd ?? this.aiGradientEnd,
      chatMyBubble: chatMyBubble ?? this.chatMyBubble,
      chatMyBubbleText: chatMyBubbleText ?? this.chatMyBubbleText,
      chatOtherBubble: chatOtherBubble ?? this.chatOtherBubble,
      chatOtherBubbleText: chatOtherBubbleText ?? this.chatOtherBubbleText,
      navRailBg: navRailBg ?? this.navRailBg,
      shadow: shadow ?? this.shadow,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      chipBg: chipBg ?? this.chipBg,
      tagBg: tagBg ?? this.tagBg,
    );
  }

  @override
  AppColorScheme lerp(ThemeExtension<AppColorScheme>? other, double t) {
    if (other is! AppColorScheme) return this;
    return AppColorScheme(
      scaffoldBg: Color.lerp(scaffoldBg, other.scaffoldBg, t)!,
      scaffoldBgAlt: Color.lerp(scaffoldBgAlt, other.scaffoldBgAlt, t)!,
      cardBg: Color.lerp(cardBg, other.cardBg, t)!,
      dialogBg: Color.lerp(dialogBg, other.dialogBg, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      hoverBg: Color.lerp(hoverBg, other.hoverBg, t)!,
      borderLight: Color.lerp(borderLight, other.borderLight, t)!,
      borderMedium: Color.lerp(borderMedium, other.borderMedium, t)!,
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t)!,
      iconDefault: Color.lerp(iconDefault, other.iconDefault, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      aiAccent: Color.lerp(aiAccent, other.aiAccent, t)!,
      aiAccentBg: Color.lerp(aiAccentBg, other.aiAccentBg, t)!,
      aiGradientStart: Color.lerp(aiGradientStart, other.aiGradientStart, t)!,
      aiGradientEnd: Color.lerp(aiGradientEnd, other.aiGradientEnd, t)!,
      chatMyBubble: Color.lerp(chatMyBubble, other.chatMyBubble, t)!,
      chatMyBubbleText: Color.lerp(chatMyBubbleText, other.chatMyBubbleText, t)!,
      chatOtherBubble: Color.lerp(chatOtherBubble, other.chatOtherBubble, t)!,
      chatOtherBubbleText: Color.lerp(chatOtherBubbleText, other.chatOtherBubbleText, t)!,
      navRailBg: Color.lerp(navRailBg, other.navRailBg, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      tagBg: Color.lerp(tagBg, other.tagBg, t)!,
    );
  }
}

// ================================================
// BuildContext extension
// ================================================
extension AppThemeX on BuildContext {
  AppColorScheme get colors => Theme.of(this).extension<AppColorScheme>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  AlertPalette get alerts => AlertPalette.of(this);
}

// ================================================
// アラート色トークン（WCAG AA 4.5:1 以上のコントラストを担保）
// 赤背景に赤文字といった低コントラスト表現を防ぐため、全アラートは
// context.alerts.{warning|urgent|info|success} を経由して取得する。
// ================================================
class AlertStyle {
  final Color background;
  final Color border;
  final Color text;
  final Color icon;
  const AlertStyle({
    required this.background,
    required this.border,
    required this.text,
    required this.icon,
  });
}

class AlertPalette {
  final AlertStyle warning;
  final AlertStyle urgent;
  final AlertStyle info;
  final AlertStyle success;
  const AlertPalette({
    required this.warning,
    required this.urgent,
    required this.info,
    required this.success,
  });

  static AlertPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  }

  // ダーク: 赤背景に赤文字の低コントラスト表現を避け、オレンジ寄りの縁取り + 温白文字
  static const AlertPalette _dark = AlertPalette(
    warning: AlertStyle(
      background: Color(0xFF3A1515),
      border: Color(0xFFFFB74D),
      text: Color(0xFFFFF3E0),
      icon: Color(0xFFFFB74D),
    ),
    urgent: AlertStyle(
      background: Color(0xFF4A2C1A),
      border: Color(0xFFFF7043),
      text: Color(0xFFFFFFFF),
      icon: Color(0xFFFF7043),
    ),
    info: AlertStyle(
      background: Color(0xFF1A2A3A),
      border: Color(0xFF64B5F6),
      text: Color(0xFFE3F2FD),
      icon: Color(0xFF64B5F6),
    ),
    success: AlertStyle(
      background: Color(0xFF1B2E1B),
      border: Color(0xFF81C784),
      text: Color(0xFFE8F5E9),
      icon: Color(0xFF81C784),
    ),
  );

  static const AlertPalette _light = AlertPalette(
    warning: AlertStyle(
      background: Color(0xFFFFF8E1),
      border: Color(0xFFFFB300),
      text: Color(0xFF4E3B00),
      icon: Color(0xFFE65100),
    ),
    urgent: AlertStyle(
      background: Color(0xFFFDEBE9),
      border: Color(0xFFE53935),
      text: Color(0xFF7F1D1D),
      icon: Color(0xFFC62828),
    ),
    info: AlertStyle(
      background: Color(0xFFE3F2FD),
      border: Color(0xFF1E88E5),
      text: Color(0xFF0D47A1),
      icon: Color(0xFF1976D2),
    ),
    success: AlertStyle(
      background: Color(0xFFE8F5E9),
      border: Color(0xFF2E7D32),
      text: Color(0xFF1B5E20),
      icon: Color(0xFF2E7D32),
    ),
  );
}

// ================================================
// ライトテーマ
// ================================================
ThemeData getAppTheme() {
  final c = AppColorScheme.light();
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansJP',
    brightness: Brightness.light,
    textTheme: AppText.buildTextTheme(c.textPrimary, c.textSecondary),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      surface: c.scaffoldBg,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: c.scaffoldBg,
    appBarTheme: AppBarTheme(
      toolbarHeight: 56,
      backgroundColor: c.cardBg,
      elevation: 0,
      centerTitle: false,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: c.textPrimary),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        fontFamily: 'NotoSansJP',
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: AppStyles.radius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: AppStyles.radiusSmall,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppStyles.radiusSmall,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppStyles.radiusSmall,
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: c.inputFill,
      isDense: true,
      hintStyle: TextStyle(color: c.textHint),
    ),
    cardTheme: CardThemeData(
      color: c.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppStyles.radius,
        side: BorderSide(color: c.borderMedium),
      ),
      margin: const EdgeInsets.only(bottom: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.dialogBg,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: c.dividerColor, thickness: 0.5),
    popupMenuTheme: PopupMenuThemeData(
      color: c.cardBg,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF333333),
      contentTextStyle: const TextStyle(color: Colors.white, fontFamily: 'NotoSansJP'),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.navRailBg,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.navRailBg,
      selectedItemColor: AppColors.primary,
      type: BottomNavigationBarType.fixed,
    ),
    extensions: [c],
  );
}

// ================================================
// 保護者向けテーマ
// 業務 UI（管理）と比べ、本文サイズを 13 → 15 に底上げし、行間も広げる。
// 保護者は業務スタッフよりタブレット端末で閲覧する想定が強く、密度を下げる。
// ParentMainScreen 配下のサブツリーのみ適用するため Theme widget で覆う運用。
// ================================================
TextTheme _buildParentTextTheme(Color textPrimary, Color textSecondary) {
  // ベース TextStyle を AppText から借用し、保護者向けに 1 段ずつアップサイズ。
  TextStyle ts(double size, FontWeight weight) => TextStyle(
        fontSize: size,
        fontWeight: weight,
        fontFamily: 'NotoSansJP',
        height: 1.55,
      );
  return TextTheme(
    labelSmall: ts(12, FontWeight.w400).copyWith(color: textSecondary),
    bodySmall: ts(13, FontWeight.w400).copyWith(color: textSecondary),
    bodyMedium: ts(15, FontWeight.w400).copyWith(color: textPrimary),
    bodyLarge: ts(16, FontWeight.w400).copyWith(color: textPrimary),
    titleSmall: ts(16, FontWeight.w600).copyWith(color: textPrimary),
    titleMedium: ts(18, FontWeight.w600).copyWith(color: textPrimary),
    titleLarge: ts(20, FontWeight.w600).copyWith(color: textPrimary),
    headlineSmall: ts(22, FontWeight.w700).copyWith(color: textPrimary),
    headlineMedium: ts(26, FontWeight.w700).copyWith(color: textPrimary),
    headlineLarge: ts(30, FontWeight.w700).copyWith(color: textPrimary),
  );
}

ThemeData getParentTheme() {
  final base = getAppTheme();
  final c = AppColorScheme.light();
  return base.copyWith(
    textTheme: _buildParentTextTheme(c.textPrimary, c.textSecondary),
  );
}

ThemeData getParentDarkTheme() {
  final base = getDarkTheme();
  final c = AppColorScheme.dark();
  return base.copyWith(
    textTheme: _buildParentTextTheme(c.textPrimary, c.textSecondary),
  );
}

// ================================================
// ダークテーマ
// ================================================
ThemeData getDarkTheme() {
  final c = AppColorScheme.dark();
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansJP',
    brightness: Brightness.dark,
    textTheme: AppText.buildTextTheme(c.textPrimary, c.textSecondary),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      surface: c.cardBg,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: c.scaffoldBg,
    appBarTheme: AppBarTheme(
      toolbarHeight: 56,
      backgroundColor: c.cardBg,
      elevation: 0,
      centerTitle: false,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: c.textPrimary),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        fontFamily: 'NotoSansJP',
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: AppStyles.radius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: AppStyles.radiusSmall,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppStyles.radiusSmall,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppStyles.radiusSmall,
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: c.inputFill,
      isDense: true,
      hintStyle: TextStyle(color: c.textHint),
    ),
    cardTheme: CardThemeData(
      color: c.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppStyles.radius,
        side: BorderSide(color: c.borderMedium),
      ),
      margin: const EdgeInsets.only(bottom: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.dialogBg,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: c.dividerColor, thickness: 0.5),
    popupMenuTheme: PopupMenuThemeData(
      color: c.cardBg,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF4A4A4A),
      contentTextStyle: TextStyle(color: Colors.white, fontFamily: 'NotoSansJP'),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.navRailBg,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.navRailBg,
      selectedItemColor: AppColors.primary,
      type: BottomNavigationBarType.fixed,
    ),
    extensions: [c],
  );
}
