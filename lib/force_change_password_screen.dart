import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // AdminShellに戻るため

class ForceChangePasswordScreen extends StatefulWidget {
  const ForceChangePasswordScreen({super.key});

  @override
  State<ForceChangePasswordScreen> createState() => _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState extends State<ForceChangePasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _changePassword() async {
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    if (newPass.length < 6) {
      setState(() => _errorMessage = 'パスワードは6文字以上で設定してください');
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _errorMessage = 'パスワードが一致しません');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが見つかりません');

      // 1. Authのパスワード更新
      await user.updatePassword(newPass);

      // 2. Firestoreのフラグ更新 (staffsコレクションを検索)
      final snapshot = await FirebaseFirestore.instance
          .collection('staffs')
          .where('uid', isEqualTo: user.uid)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // 見つかったドキュメントの isInitialPassword を false に
        await snapshot.docs.first.reference.update({
          'isInitialPassword': false,
        });
      } else {
        // 保護者の場合など (念のため families もチェックするか、要件次第)
        final famSnapshot = await FirebaseFirestore.instance
            .collection('families')
            .where('uid', isEqualTo: user.uid)
            .get();
        if (famSnapshot.docs.isNotEmpty) {
          await famSnapshot.docs.first.reference.update({
            'isInitialPassword': false,
          });
        }
      }

      // 完了したらメイン画面へ (再ログイン不要な場合)
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthCheckWrapper()),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'requires-recent-login') {
          _errorMessage = 'セキュリティのため、一度ログアウトして再ログインしてから試してください。';
        } else {
          _errorMessage = 'エラーが発生しました: ${e.message}';
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('パスワード変更')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_reset, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  '初回ログインのため\n新しいパスワードを設定してください',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新しいパスワード (6文字以上)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新しいパスワード (確認)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _changePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('変更して開始'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}