import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMessage;

  static const String _fixedDomain = '@bee-smiley.com';

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _loginIdController.text.trim() + _fixedDomain;

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );

      // ★ログイン成功後、ユーザー種別を判定して振り分け
      if (credential.user != null && mounted) {
        await _navigateBasedOnUserType(credential.user!.uid);
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'IDまたはパスワードが正しくありません。';
      } else if (e.code == 'too-many-requests') {
        message = '何度も間違えたため、一時的にロックされました。時間をおいて再度お試しください。';
      } else {
        message = 'エラーが発生しました: ${e.message}';
      }
      
      if (mounted) {
        setState(() {
          _errorMessage = message;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// ユーザー種別を判定して適切な画面に遷移
  Future<void> _navigateBasedOnUserType(String uid) async {
    try {
      // staffsコレクションをチェック
      final staffQuery = await FirebaseFirestore.instance
          .collection('staffs')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (staffQuery.docs.isNotEmpty) {
        // スタッフ/管理者 → 管理者画面へ
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/admin');
        }
        return;
      }

      // familiesコレクションをチェック
      final familyQuery = await FirebaseFirestore.instance
          .collection('families')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (familyQuery.docs.isNotEmpty) {
        // 保護者 → 保護者画面へ
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/parent');
        }
        return;
      }

      // どちらにも存在しない場合
      if (mounted) {
        setState(() {
          _errorMessage = 'アカウント情報が見つかりません。管理者にお問い合わせください。';
        });
        // ログアウト
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'ユーザー情報の取得に失敗しました。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ロゴ画像
                Image.asset(
                  'assets/logo_beesmiley.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 48),
                
                // 入力フォーム
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ログインID入力欄
                    TextField(
                      controller: _loginIdController,
                      decoration: InputDecoration(
                        labelText: 'ログインID',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // パスワード入力欄
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'パスワード',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // ログインボタン
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'ログイン',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}