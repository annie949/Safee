import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/encryption_service.dart';
import '../../services/activity_logger.dart';
import '../../services/error_helper.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/database_service.dart';
import 'forgot_password_screen.dart';
import 'create_pin_screen.dart';
import 'pin_lock_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _storage = const FlutterSecureStorage(); // FIX: moved to field

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final email = _email.text.trim().toLowerCase();
    final password = _password.text;

    try {
      // STEP 1: Sign in with Firebase
      await FirebaseAuthService.signInWithEmail(email, password);
      if (!mounted) return;

      // STEP 2: Check email verified
      // FIX: sign out first so user isn't left in signed-in Firebase state
      if (!FirebaseAuthService.isEmailVerified) {
        await FirebaseAuthService.signOut();
        if (!mounted) return;
        ErrorHelper.showError(
            context, 'Please verify your email before logging in.');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(
              email: email,
              password: password,
              fromLogin: true,
            ),
          ),
        );
        setState(() => _loading = false);
        return;
      }

      // STEP 3: Load master key
      final keyLoaded = await EncryptionService.loadMasterKeyWithPassword(
        password: password,
        email: email,
      );
      if (!mounted) return;

      if (!keyLoaded) {
        await ActivityLogger.logLoginFailed(email, 'Encryption key not found');
        await FirebaseAuthService.signOut();
        if (!mounted) return;
        ErrorHelper.showError(
          context,
          'Encryption setup not found. Please reset your password using your recovery key.',
        );
        setState(() => _loading = false);
        return;
      }

      // STEP 4: Get user from Supabase by email
      final userRes = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      if (!mounted) return;

      if (userRes == null) {
        await ActivityLogger.logLoginFailed(email, 'User not found in database');
        await FirebaseAuthService.signOut();
        if (!mounted) return;
        ErrorHelper.showError(
          context,
          'Account not found. Please sign up again.',
        );
        setState(() => _loading = false);
        return;
      }

      final userId = userRes['id'] as String;

      // STEP 5: Save to secure storage
      // FIX: removed storing raw password — encryption key is already
      // loaded in memory by EncryptionService. Storing password is a
      // security risk. Prompt user again if re-derivation is needed later.
      await _storage.write(key: 'last_logged_in_user_id', value: userId);

      // STEP 6: Log activity
      await ActivityLogger.logLogin(email);
      await ActivityLogger.logEncryptionKeyLoaded();
      await DatabaseService.logActivity(
        userId: userId,
        action: 'login',
        description: 'Logged in from $email',
      );
      if (!mounted) return;

      // STEP 7: Navigate to PIN screen
      final pin = await _storage.read(key: 'user_pin_$userId');
      if (!mounted) return;

      if (pin == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CreatePinScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PinLockScreen()),
        );
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      await ActivityLogger.logLoginFailed(email, e.code);
      if (mounted) {
        ErrorHelper.showError(context, _friendlyFirebaseError(e));
        setState(() => _loading = false);
      }
    } catch (e) {
      await ActivityLogger.logLoginFailed(email, e.toString());
      if (mounted) {
        ErrorHelper.showError(
          context,
          'Connection failed. Please check your internet and try again.',
        );
        setState(() => _loading = false);
      }
    }
  }

  String _friendlyFirebaseError(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential': // FIX: Firebase v10+ uses this instead of wrong-password/user-not-found
        return 'Incorrect email or password. Please try again.';
      case 'user-not-found':
        return 'No account found with this email. Please sign up first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      default:
        return 'Login failed. Please try again.'; // FIX: removed e.message to avoid leaking internal errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;

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
                  const SizedBox(height: 20),
                  const Center(
                    child: Icon(Icons.lock_open_rounded,
                        color: AppColors.primary, size: 52),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Welcome Back',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Sign in to access your encrypted vault',
                      style: TextStyle(color: mutedColor, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 32),

                  _label('Email Address'),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: _inputDeco('yourname@gmail.com', Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Email is required.';
                      }
                      if (!v.trim().contains('@')) {
                        return 'Enter a valid email.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  _label('Password'),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: _inputDeco(
                      'Your password',
                      Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: mutedColor,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Password is required.';
                      }
                      if (v.length < 8) {
                        return 'Password must be at least 8 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen()),
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.verified_user_rounded,
                            color: AppColors.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your password unlocks your encryption key on-device. '
                                'It is never sent to any server in plain text.',
                            style: TextStyle(
                                color: mutedColor, fontSize: 12, height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                          : const Text(
                        'Unlock Vault',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: RichText(
                        text: TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: mutedColor, fontSize: 13),
                          children: const [
                            TextSpan(
                              text: 'Create Account',
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
          fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
    ),
  );

  InputDecoration _inputDeco(String hint, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.muted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.card.withOpacity(0.6),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.error.withOpacity(0.7))),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
        hintStyle:
        TextStyle(color: AppColors.muted.withOpacity(0.45), fontSize: 14),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
}