import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_theme.dart';
import '../../services/encryption_service.dart';
import '../../services/error_helper.dart';
import '../../services/firebase_auth_service.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final bool fromRecoveryLink;
  const ForgotPasswordScreen({super.key, this.fromRecoveryLink = false});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 1;

  final _emailCtrl = TextEditingController();
  final _recoveryKeyCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String _newRecoveryKey = '';

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _copied = false;
  bool _saved = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _recoveryKeyCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Core: Reset Password
  // ─────────────────────────────────────────────

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final recoveryKey = _recoveryKeyCtrl.text.trim().toUpperCase();
    final newPass = _newPassCtrl.text;
    final confirm = _confirmCtrl.text;

    // Validation
    if (email.isEmpty || !email.contains('@')) {
      ErrorHelper.showError(context, 'Please enter a valid email address.');
      return;
    }
    if (recoveryKey.isEmpty) {
      ErrorHelper.showError(context, 'Please enter your recovery key.');
      return;
    }
    final dashCount = recoveryKey.split('-').length - 1;
    if (dashCount < 10) {
      ErrorHelper.showError(
        context,
        'Invalid recovery key format.\n\n'
            'Key must look like: XXXX-XXXX-XXXX-XXXX-...\n\n'
            'Paste the key exactly as shown when you created your account.',
      );
      return;
    }
    if (newPass.isEmpty || newPass.length < 8) {
      ErrorHelper.showError(context, 'Password must be at least 8 characters.');
      return;
    }
    if (!newPass.contains(RegExp(r'[A-Z]'))) {
      ErrorHelper.showError(
          context, 'Password must contain at least one uppercase letter (A-Z).');
      return;
    }
    if (!newPass.contains(RegExp(r'[0-9]'))) {
      ErrorHelper.showError(
          context, 'Password must contain at least one number (0-9).');
      return;
    }
    if (newPass != confirm) {
      ErrorHelper.showError(context, 'Passwords do not match. Please re-enter.');
      return;
    }

    setState(() => _loading = true);

    try {
      debugPrint('=== PASSWORD RESET ATTEMPT ===');
      debugPrint('Email: $email');

      // ───────────────────────────────────────
      // STEP 1: Verify recovery key
      // ───────────────────────────────────────
      final keyLoaded =
      await EncryptionService.loadMasterKeyWithRecoveryKeyByEmail(
        email: email,
        recoveryKey: recoveryKey,
      );

      if (!keyLoaded) {
        debugPrint('Recovery key verification failed');
        if (mounted) {
          ErrorHelper.showError(
            context,
            'Recovery key verification failed.\n\n'
                '• Make sure you entered the key exactly as shown\n'
                '• Check for any missing or extra characters\n'
                '• Ensure your email matches your Safe Locker account',
          );
          setState(() => _loading = false);
        }
        return;
      }

      debugPrint('Recovery key verified');

      // ───────────────────────────────────────
      // STEP 2: Generate new recovery key
      // ───────────────────────────────────────
      _newRecoveryKey = EncryptionService.generateRecoveryKey();
      debugPrint('New recovery key generated');

      // ───────────────────────────────────────
      // STEP 3: Re-encrypt master key with
      // new password and new recovery key
      // ───────────────────────────────────────
      await EncryptionService.reEncryptAfterPasswordReset(
        newPassword: newPass,
        newRecoveryKey: _newRecoveryKey,
        email: email,
      );

      debugPrint('Re-encryption completed');

      // ───────────────────────────────────────
      // STEP 4: Send Firebase password reset
      // email so user can update Firebase auth
      // ───────────────────────────────────────
      try {
        await FirebaseAuthService.sendPasswordResetEmail(email);
        debugPrint('Firebase password reset email sent');
      } catch (e) {
        debugPrint('Firebase reset email error (non-blocking): $e');
      }

      if (mounted) {
        setState(() {
          _step = 2;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Password reset error: $e');
      if (mounted) {
        ErrorHelper.showError(
            context, 'Password reset failed: ${e.toString()}');
        setState(() => _loading = false);
      }
    }
  }

  // ─────────────────────────────────────────────
  // Copy and Save Helpers
  // ─────────────────────────────────────────────

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _newRecoveryKey));
    setState(() => _copied = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Text('Recovery key copied!'),
          ]),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _saveToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'safe_locker_recovery_key_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('${directory.path}/$fileName');

      await file.writeAsString(
        'Safe Locker Recovery Key\n'
            '========================\n\n'
            'Key: $_newRecoveryKey\n\n'
            'Keep this key safe! Without it, you cannot reset your password.\n'
            'Generated: ${DateTime.now()}\n',
      );

      setState(() => _saved = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Key saved to app folder'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _finishReset() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
    );
  }
// ─────────────────────────────────────────────
  // UI Build
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;

    return _step == 2
        ? _buildStep2(bgColor, cardColor, textColor, mutedColor, borderColor)
        : _buildStep1(bgColor, textColor, mutedColor);
  }

  // ─────────────────────────────────────────────
  // Step 2: Show New Recovery Key
  // ─────────────────────────────────────────────

  Widget _buildStep2(Color bgColor, Color cardColor, Color textColor,
      Color mutedColor, Color borderColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              isDark
                  ? const Color(0xFF0C2E4A)
                  : AppColors.primary.withOpacity(0.1),
              bgColor,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.key_rounded,
                      color: AppColors.primary, size: 36),
                ),
                const SizedBox(height: 20),
                Text(
                  'New Recovery Key',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'SAVE THIS NOW',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: AppColors.primary, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'A password reset email has been sent to your inbox. '
                              'Check your email and follow the link to update your Firebase password.',
                          style: TextStyle(
                              color: AppColors.primary, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: SelectableText(
                    _newRecoveryKey,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _copyToClipboard,
                        icon: Icon(
                            _copied ? Icons.check : Icons.copy, size: 18),
                        label: Text(_copied ? 'Copied!' : 'Copy'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding:
                          const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saveToFile,
                        icon: Icon(
                            _saved ? Icons.check : Icons.save_alt,
                            size: 18),
                        label: Text(_saved ? 'Saved' : 'Save'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          padding:
                          const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.warning.withOpacity(0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: AppColors.warning, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Lose this key = lose access to your files forever',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _finishReset,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Step 1: Enter Email + Recovery Key + Password
  // ─────────────────────────────────────────────

  Widget _buildStep1(Color bgColor, Color textColor, Color mutedColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              isDark
                  ? const Color(0xFF0C2E4A)
                  : AppColors.primary.withOpacity(0.1),
              bgColor,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios_rounded,
                            color: mutedColor, size: 18),
                        const SizedBox(width: 4),
                        Text('Back', style: TextStyle(color: mutedColor)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: AppColors.primary, size: 36),
                ),
                const SizedBox(height: 24),
                Text(
                  'Reset Password',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your recovery key to reset your password',
                  style: TextStyle(color: mutedColor, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Email field
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_loading,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Email address',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Recovery key field
                TextField(
                  controller: _recoveryKeyCtrl,
                  enabled: !_loading,
                  maxLines: 3,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    hintText:
                    'Paste your recovery key\n\nExample:\nFEDD-FC66-2609-722C-...',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(top: 12.0),
                      child: Icon(Icons.vpn_key_outlined),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // New password field
                TextField(
                  controller: _newPassCtrl,
                  obscureText: _obscureNew,
                  enabled: !_loading,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText:
                    'New password (8+ chars, 1 uppercase, 1 number)',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Confirm password field
                TextField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  enabled: !_loading,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Confirm new password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Reset button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                        : const Text(
                      'Reset Password',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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