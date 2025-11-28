import 'package:flutter/material.dart';

class AppColors {
  // ブランドカラー
  static const Color primary = Colors.blue; 
  static const Color onPrimary = Colors.white;

  static const Color secondary = Colors.indigo;
  
  // 背景色
  static const Color background = Colors.white; 
  static const Color surface = Colors.white;

  static const Color textMain = Colors.black87;
  static const Color textSub = Colors.grey;
  
  static const Color error = Colors.red;
  static const Color success = Colors.green;

  // 入力欄の背景色（薄いグレー）
  static const Color inputFill = Color(0xFFF3F4F6); 
}

class AppStyles {
  static final BorderRadius radius = BorderRadius.circular(12);
  static final BorderRadius radiusSmall = BorderRadius.circular(8);
  
  static final Border borderLight = Border.all(color: Colors.grey.shade200);
}

ThemeData getAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      background: AppColors.background,
      error: AppColors.error,
    ),
    
    scaffoldBackgroundColor: AppColors.background,
    
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.textMain,
      iconTheme: IconThemeData(color: AppColors.textMain),
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
      fillColor: AppColors.inputFill,
      isDense: true,
      hintStyle: const TextStyle(color: Colors.grey),
    ),
    
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppStyles.radius,
        side: BorderSide(color: Colors.grey.shade300),
      ),
      margin: const EdgeInsets.only(bottom: 12),
    ),

    // ★修正: fontFamilyを指定しない（システムデフォルトを使用）
    // これにより各OSの標準日本語フォントが自動的に使われ、文字化けしなくなります
    // - macOS/iOS: San Francisco + ヒラギノ
    // - Windows: Segoe UI + メイリオ/游ゴシック
    // - Android: Roboto + Noto Sans CJK
    // - Web: ブラウザのデフォルト
  );
}