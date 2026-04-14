import 'package:flutter/material.dart';

// ================================================
// ブランドカラー（テーマ非依存の固定色）
// ================================================
class AppColors {
  static const Color primary = Colors.blue;
  static const Color onPrimary = Colors.white;
  static const Color secondary = Colors.indigo;
  static const MaterialColor accent = Colors.orange;
  static const Color warning = Color(0xFFFFA726);
  static const Color error = Colors.red;
  static const Color success = Colors.green;

  // 後方互換（移行完了後に削除予定）
  static const Color background = Colors.white;
  static const Color surface = Colors.white;
  static const Color textMain = Colors.black87;
  static const Color textSub = Colors.grey;
  static const Color inputFill = Color(0xFFF3F4F6);
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
        chatMyBubble: const Color(0xFFD6EEFF),
        chatMyBubbleText: Colors.black87,
        chatOtherBubble: Colors.grey.shade100,
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
        chatMyBubble: const Color(0xFF1565C0),
        chatMyBubbleText: Colors.white,
        chatOtherBubble: const Color(0xFF383838),
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
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
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
// ダークテーマ
// ================================================
ThemeData getDarkTheme() {
  final c = AppColorScheme.dark();
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansJP',
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
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
