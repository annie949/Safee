import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../../theme/app_theme.dart';
import '../../services/error_helper.dart';
import '../../services/firebase_auth_service.dart';
import 'verify_email_screen.dart';
import '../../services/pending_signup_service.dart';
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _agreeTerms = false;
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _showPrivacyPolicy() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.border : AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Privacy Policy & Terms',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Last updated: May 2026',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.muted : AppColors.lightMuted,
              ),
            ),
            Divider(
              height: 24,
              color: isDark ? AppColors.border : AppColors.lightBorder,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPolicySection(
                      title: '1. Data We Collect',
                      content: 'We collect your email address, username, and encrypted files. '
                          'All files are encrypted with AES-256 before being stored. '
                          'We never have access to your file contents as decryption happens only on your device.',
                    ),
                    const SizedBox(height: 16),
                    _buildPolicySection(
                      title: '2. How We Use Your Data',
                      content: 'Your data is used solely to provide Safe Locker services:\n'
                          '• Secure file storage and encryption\n'
                          '• Cloud backup (if you enable it)\n'
                          '• File sharing with other Safe Locker users\n'
                          '• Account management and security\n\n'
                          'We never sell or share your personal data with third parties.',
                    ),
                    const SizedBox(height: 16),
                    _buildPolicySection(
                      title: '3. Encryption & Security',
                      content: '• All files are encrypted using AES-256-CBC\n'
                          '• Your password is never stored in plain text\n'
                          '• Master keys are stored encrypted in our database\n'
                          '• Only you can decrypt your files\n'
                          '• We use SHA-256 for key derivation\n'
                          '• Each file uses a unique random IV',
                    ),
                    const SizedBox(height: 16),
                    _buildPolicySection(
                      title: '4. Cloud Storage',
                      content: 'Files you choose to back up are stored encrypted on Supabase servers. '
                          'You have 200MB of free cloud storage. '
                          'You can delete your cloud files at any time. '
                          'We do not access or view your encrypted files.',
                    ),
                    const SizedBox(height: 16),
                    _buildPolicySection(
                      title: '5. File Sharing',
                      content: 'When you share a file, it is re-encrypted with a share-specific key. '
                          'Recipients must have a Safe Locker account. '
                          'Shared files expire after your chosen duration (1-24 hours). '
                          'You can revoke access at any time.',
                    ),
                    const SizedBox(height: 16),
                    _buildPolicySection(
                      title: '6. Data Retention',
                      content: '• Files in trash are automatically deleted after 7 days\n'
                          '• You can permanently delete files anytime\n'
                          '• Account deletion removes all your data from our servers\n'
                          '• Activity logs are stored locally on your device',
                    ),
                    const SizedBox(height: 16),
                    _buildPolicySection(
                      title: '7. Your Rights',
                      content: 'You have the right to:\n'
                          '• Access all your data\n'
                          '• Delete your account and all associated data\n'
                          '• Export your files\n'
                          '• Opt out of cloud backup\n\n'
                          'Use the "Wipe All Data" option in Settings to permanently delete everything.',
                    ),
                    const SizedBox(height: 16),
                    _buildPolicySection(
                      title: '8. Contact Us',
                      content: 'If you have questions about this privacy policy, '
                          'please contact us at: support@safelocker.com',
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(_),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'I Understand',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicySection({required String title, required String content}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.soft : AppColors.lightText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          content,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: isDark ? AppColors.muted : AppColors.lightMuted,
          ),
        ),
      ],
    );
  }

  String? _strengthLabel() {
    final p = _password.text;
    if (p.isEmpty) return null;
    int score = 0;
    if (p.length >= 8) score++;
    if (p.contains(RegExp(r'[A-Z]'))) score++;
    if (p.contains(RegExp(r'[0-9]'))) score++;
    if (p.contains(RegExp(r'[!@#\$%^&*]'))) score++;
    if (score <= 1) return 'Weak';
    if (score == 2) return 'Fair';
    if (score == 3) return 'Good';
    return 'Strong';
  }

  Color _strengthColor() {
    switch (_strengthLabel()) {
      case 'Weak':
        return AppColors.error;
      case 'Fair':
        return AppColors.warning;
      case 'Good':
        return Colors.blue;
      case 'Strong':
        return AppColors.primary;
      default:
        return Colors.transparent;
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeTerms) {
      ErrorHelper.showError(context, 'Please agree to the Privacy Policy & Terms.');
      return;
    }

    setState(() => _loading = true);

    try {
      // Step 1: Create user in Firebase ONLY (for email verification)
      final firebaseUser = await FirebaseAuthService.signUpWithEmail(
        _email.text.trim(),
        _password.text,
        username: _username.text.trim(),
      );

      if (!mounted) return;

      if (firebaseUser != null) {
        // Send verification email from Firebase
        await firebaseUser.sendEmailVerification();

        // ✅ Save pending signup data (ADD THIS HERE)
        await PendingSignupService.savePendingSignup(
          email: _email.text.trim(),
          password: _password.text,
          username: _username.text.trim(),
        );

        ErrorHelper.showSuccess(context, 'Verification email sent! Check your inbox.');

        // Navigate to verification screen - Supabase user will be created AFTER email is verified
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(
              email: _email.text.trim(),
              password: _password.text,
              username: _username.text.trim(),
            ),
          ),
        );
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      ErrorHelper.showError(context, _friendlyFirebaseError(e));
      setState(() => _loading = false);
    } catch (e) {
      ErrorHelper.showError(context, 'Something went wrong. Please check your internet and try again.');
      setState(() => _loading = false);
    }
  }

  String _friendlyFirebaseError(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please login instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters with letters and numbers.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes before trying again.';
      default:
        return 'Signup failed: ${e.message}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;

    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              isDark ? const Color(0xFF0C2E4A) : AppColors.primary.withOpacity(0.1),
              bgColor,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_rounded, color: mutedColor),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fill in your details to get started.',
                    style: TextStyle(
                      fontSize: 14,
                      color: mutedColor,
                    ),
                  ),
                  const SizedBox(height: 28),

                  _label('Username'),
                  TextFormField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: _deco('Your name', Icons.person_outline_rounded),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Username is required.';
                      if (v.trim().length < 3) return 'Username must be at least 3 characters.';
                      if (v.trim().length > 30) return 'Username cannot exceed 30 characters.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  _label('Email Address'),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: _deco('yourname@gmail.com', Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required.';
                      final email = v.trim().toLowerCase();
                      if (!email.contains('@')) return 'Enter a valid email address.';
                      final parts = email.split('@');
                      if (parts.length != 2) return 'Enter a valid email address.';
                      if (parts[0].isEmpty) return 'Email username cannot be empty.';
                      if (!parts[1].contains('.')) return 'Enter a valid domain (e.g., gmail.com).';
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  _label('Password'),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscurePass,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: _deco(
                      'Min 8 characters',
                      Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: mutedColor,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required.';
                      if (v.length < 8) return 'Password must be at least 8 characters.';
                      if (!v.contains(RegExp(r'[A-Z]'))) return 'Add at least one uppercase letter (A-Z).';
                      if (!v.contains(RegExp(r'[0-9]'))) return 'Add at least one number (0-9).';
                      return null;
                    },
                  ),
                  if (_password.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: switch (_strengthLabel()) {
                              'Weak' => 0.25,
                              'Fair' => 0.5,
                              'Good' => 0.75,
                              'Strong' => 1.0,
                              _ => 0,
                            },
                            backgroundColor: borderColor,
                            valueColor: AlwaysStoppedAnimation(_strengthColor()),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _strengthLabel() ?? '',
                        style: TextStyle(
                          color: _strengthColor(),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 18),

                  _label('Confirm Password'),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: _deco(
                      'Re-enter your password',
                      Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: mutedColor,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Please confirm your password.';
                      if (v != _password.text) return 'Passwords do not match.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Info box
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'After signing up you will receive a Recovery Key. Save it carefully — it resets your password without affecting your encrypted files.',
                            style: TextStyle(
                              color: mutedColor,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Terms checkbox with clickable text
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Checkbox (tappable)
                      GestureDetector(
                        onTap: () => setState(() => _agreeTerms = !_agreeTerms),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _agreeTerms ? AppColors.primary : Colors.transparent,
                            border: Border.all(
                              color: _agreeTerms ? AppColors.primary : borderColor,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: _agreeTerms
                              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Text (separately tappable)
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            text: 'I have read and agree to the ',
                            style: TextStyle(color: mutedColor, fontSize: 13, height: 1.5),
                            children: [
                              TextSpan(
                                text: 'Privacy Policy & Terms',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: TapGestureRecognizer()..onTap = _showPrivacyPolicy,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Sign Up button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        'Create Account',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Login link
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: RichText(
                        text: TextSpan(
                          text: 'Already have an account? ',
                          style: TextStyle(color: mutedColor, fontSize: 13),
                          children: const [
                            TextSpan(
                              text: 'Login',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );

  InputDecoration _deco(String hint, IconData icon, {Widget? suffix}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;

    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.muted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.error.withOpacity(0.7)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      hintStyle: TextStyle(color: AppColors.muted.withOpacity(0.45), fontSize: 14),
      errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}