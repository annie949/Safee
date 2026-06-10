import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../theme/app_theme.dart';
import '../../services/encryption_service.dart';
import '../../services/pending_signup_service.dart';
import '../../services/error_helper.dart';
import './onboarding_screen.dart';
import './auth/pin_lock_screen.dart';
import './auth/welcome_screen.dart';
import './auth/create_pin_screen.dart';
import './auth/recovery_key_screen.dart';
import './auth/verify_email_screen.dart';
import 'package:app_links/app_links.dart';
import 'dart:io';
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;
  late Animation<double> _slideUp;

  @override
  void initState() {
    final appLinks = AppLinks();
    appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri?.host == 'verification') {
        final email = uri?.queryParameters['email'];
        final password = uri?.queryParameters['password'];
        if (email != null && password != null) {
          // Navigate directly to recovery key screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RecoveryKeyScreen(
                isNew: true,
                password: password,
              ),
            ),
          );
        }
      }
    });
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));

    _scale = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));

    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5)));

    _slideUp = Tween<double>(begin: 50, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 0.8)));

    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    const storage = FlutterSecureStorage();

    // Step 1: Check onboarding
    final onboardingDone = await storage.read(key: 'onboarding_done');
    if (onboardingDone == null) {
      _go(const OnboardingScreen());
      return;
    }

    // Step 2: Check if we have a saved user ID
    final userId = await storage.read(key: 'last_logged_in_user_id');

    if (userId == null) {
      _go(const WelcomeScreen());
      return;
    }

    // ✅ Step 3: Check if PIN exists for this user
    final pin = await storage.read(key: 'user_pin_$userId');

    if (pin == null || pin.isEmpty) {
      // No PIN - user needs to login again
      _go(const WelcomeScreen());
      return;
    }

    // ✅ Step 4: Check for pending email verification
    final pendingSignup = await PendingSignupService.getPendingSignup();
    if (pendingSignup != null) {
      final email = pendingSignup['email']!;
      final password = pendingSignup['password']!;
      final username = pendingSignup['username']!;

      _go(VerifyEmailScreen(
        email: email,
        password: password,
        username: username,
      ));
      return;
    }

    // Step 5: Go to PIN lock screen
    _go(const PinLockScreen());
  }

// Add this helper method to check internet connectivity
  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<void> _clearAndSignOut(FlutterSecureStorage storage) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    EncryptionService.clearKey();
    await storage.delete(key: 'onboarding_done');
    await storage.write(key: 'onboarding_done', value: 'true');
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _goWithMessage(Widget screen, String message) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ErrorHelper.showError(context, message);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;

    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 1.5,
            colors: [
              isDark ? const Color(0xFF0C3358) : AppColors.primary.withOpacity(0.12),
              bgColor,
              bgColor,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo
              FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.5),
                          blurRadius: 40,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Animated Text Lines
              FadeTransition(
                opacity: _fade,
                child: Column(
                  children: [
                    _buildAnimatedTextLine('SECURE', _slideUp, 0),
                    const SizedBox(height: 16),
                    _buildAnimatedTextLine('PROTECTED', _slideUp, 1),
                    const SizedBox(height: 16),
                    _buildAnimatedTextLine('PRIVATE', _slideUp, 2),
                  ],
                ),
              ),

              const SizedBox(height: 60),

              // Loading indicator
              FadeTransition(
                opacity: _fade,
                child: Column(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                        backgroundColor: isDark
                            ? AppColors.muted.withOpacity(0.2)
                            : AppColors.lightMuted.withOpacity(0.2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.muted.withOpacity(0.5)
                            : AppColors.lightMuted.withOpacity(0.5),
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedTextLine(String text, Animation<double> animation, int index) {
    // Staggered animation for each word
    final staggeredDelay = Duration(milliseconds: 200 * index);
    final staggeredAnimation = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(0.3 + (index * 0.1), 0.7 + (index * 0.1), curve: Curves.easeOut),
    );

    return FadeTransition(
      opacity: staggeredAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5),
          end: Offset.zero,
        ).animate(staggeredAnimation),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.03)
                : Colors.black.withOpacity(0.02),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.soft
                  : AppColors.lightText,
            ),
          ),
        ),
      ),
    );
  }
}