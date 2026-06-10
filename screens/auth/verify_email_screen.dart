import 'package:flutter/material.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/error_helper.dart';
import '../../services/pending_signup_service.dart';
import 'recovery_key_screen.dart';
import 'login_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String password;
  final String username;
  final bool fromLogin;

  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.password,
    this.username = '',
    this.fromLogin = false,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _resending = false;
  bool _isVerified = false;
  bool _isCreatingAccount = false;
  bool _isChecking = false;

  // ─────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Immediate check + polling
    _checkVerificationStatus();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // Re-check every time user returns from Gmail
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVerificationStatus();
    }
  }

  // ─────────────────────────────────────────────
  // Back Navigation Guard
  // ─────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkCard
            : AppColors.lightCard,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave Verification?'),
        content: const Text(
          'If you leave now, you will need to start the signup process again.\n\n'
              'Make sure you have verified your email before leaving.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () {
              PendingSignupService.clearPendingSignup();
              Navigator.pop(_, true);
            },
            style:
            ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (shouldLeave == true) {
      _navigateToLogin();
    }

    return false;
  }

  // ─────────────────────────────────────────────
  // Polling
  // ─────────────────────────────────────────────

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkVerificationStatus();
    });
  }

  // ─────────────────────────────────────────────
  // Core: Check Firebase Verification
  // ─────────────────────────────────────────────

  Future<void> _checkVerificationStatus() async {
    if (_isChecking || _isVerified || _isCreatingAccount) return;

    setState(() => _isChecking = true);

    try {
      // Always reload from Firebase server — never trust cached state
      await FirebaseAuthService.reloadUser();

      if (FirebaseAuthService.isEmailVerified && mounted && !_isVerified) {
        _timer?.cancel();
        setState(() => _isVerified = true);
        await _createSupabaseAccount();
      }
    } catch (e) {
      debugPrint('Verification check error: $e');
    } finally {
      // Always reset — no condition
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  // ─────────────────────────────────────────────
  // Core: Create Supabase Records After Verification
  // Uses email to link Firebase and Supabase.
  // Generates a proper UUID for Supabase id column.
  // ─────────────────────────────────────────────

  Future<void> _createSupabaseAccount() async {
    if (!mounted) return;
    setState(() => _isCreatingAccount = true);

    try {
      // Get the verified Firebase user
      final firebaseUser = FirebaseAuthService.currentUser;

      if (firebaseUser == null) {
        ErrorHelper.showError(
            context, 'Session expired. Please sign up again.');
        setState(() => _isCreatingAccount = false);
        return;
      }

      final email = firebaseUser.email ?? widget.email;
      final now = DateTime.now().toIso8601String();

      // ───────────────────────────────────────
      // STEP 1: Check if user already exists
      // using email as the link between
      // Firebase and Supabase
      // ───────────────────────────────────────
      final existing = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (existing != null) {
        // User already set up — go to RecoveryKeyScreen
        debugPrint('User already exists in Supabase, skipping insert.');
        await PendingSignupService.clearPendingSignup();
        _navigateToRecoveryKey();
        return;
      }

      // ───────────────────────────────────────
      // STEP 2: Generate a proper UUID for
      // Supabase — since Firebase UIDs are not
      // UUID format
      // ───────────────────────────────────────
      const uuidGenerator = Uuid();
      final supabaseUUID = uuidGenerator.v4();

      // ───────────────────────────────────────
      // STEP 3: Insert into users table
      // ───────────────────────────────────────
      await Supabase.instance.client.from('users').insert({
        'id': supabaseUUID,
        'email': email,
        'created_at': now,
      });

      // ───────────────────────────────────────
      // STEP 4: Insert default settings
      // ───────────────────────────────────────
      await Supabase.instance.client.from('settings').insert({
        'user_id': supabaseUUID,
        'theme': 'system',
        'cloud_backup_enabled': false,
        'updated_at': now,
      });

      if (!mounted) return;

      await PendingSignupService.clearPendingSignup();
      _navigateToRecoveryKey();

    } catch (e) {
      debugPrint('Supabase account creation error: $e');
      if (!mounted) return;
      ErrorHelper.showError(
          context, 'Account setup failed: ${e.toString()}');
      setState(() => _isCreatingAccount = false);
    }
  }

  // ─────────────────────────────────────────────
  // Resend Verification Email
  // ─────────────────────────────────────────────

  Future<void> _resendVerification() async {
    setState(() => _resending = true);
    try {
      await FirebaseAuthService.sendVerificationEmail();
      if (mounted) {
        ErrorHelper.showSuccess(context, 'Verification email resent!');
      }
    } catch (e) {
      if (mounted) {
        ErrorHelper.showError(
            context, 'Failed to resend. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  // ─────────────────────────────────────────────
  // Navigation Helpers
  // ─────────────────────────────────────────────

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
    );
  }

  void _navigateToRecoveryKey() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RecoveryKeyScreen(
          isNew: true,
          password: widget.password,
        ),
      ),
    );
  }

  void _goToLogin() {
    PendingSignupService.clearPendingSignup();
    _navigateToLogin();
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 12),

                // Back button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: _goToLogin,
                    icon: Icon(Icons.arrow_back_ios_rounded,
                        color: mutedColor),
                    padding: EdgeInsets.zero,
                  ),
                ),

                const Spacer(),

                // Icon / Spinner
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: _isCreatingAccount
                      ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 3),
                  )
                      : const Icon(Icons.mark_email_unread_outlined,
                      color: AppColors.primary, size: 44),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  _isCreatingAccount
                      ? 'Creating Account...'
                      : 'Verify Your Email',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),

                if (!_isCreatingAccount) ...[
                  Text(
                    'We sent a verification link to',
                    style: TextStyle(color: mutedColor, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your email and click the verification link',
                    style: TextStyle(color: mutedColor, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '✅ You can safely leave the app to check Gmail '
                                '— this screen will detect verification '
                                'automatically when you return.',
                            style: TextStyle(
                                color: AppColors.warning, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Text(
                    'Setting up your secure vault...',
                    style: TextStyle(color: mutedColor, fontSize: 14),
                  ),
                ],

                const SizedBox(height: 20),

                // Animated waiting dots
                if (!_isCreatingAccount && !_isVerified) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Dot(delay: 0),
                      _Dot(delay: 300),
                      _Dot(delay: 600),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for verification…',
                    style: TextStyle(
                        color: mutedColor.withOpacity(0.5), fontSize: 13),
                  ),
                ],

                // Creating account spinner
                if (_isCreatingAccount) ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Please wait...',
                    style: TextStyle(color: mutedColor, fontSize: 13),
                  ),
                ],

                const SizedBox(height: 24),

                // Info box
                if (!_isCreatingAccount)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.card : AppColors.lightCard,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: AppColors.muted, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Can't find the email? Check your spam folder "
                                "or tap 'Resend'.\n\nYou can safely switch to "
                                "Gmail and come back — verification will be "
                                "detected automatically.",
                            style:
                            TextStyle(color: mutedColor, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                const Spacer(),

                // Resend button
                if (!_isCreatingAccount)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _resending ? null : _resendVerification,
                      child: _resending
                          ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                          : const Text('Resend Verification Email'),
                    ),
                  ),

                const SizedBox(height: 12),

                // Back to login (fromLogin flow only)
                if (widget.fromLogin && !_isCreatingAccount)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _goToLogin,
                      child: const Text('Back to Login'),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Animated Dot Widget
// ─────────────────────────────────────────────

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _a = Tween<double>(begin: 0.3, end: 1.0).animate(_c);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
          color: AppColors.primary, shape: BoxShape.circle),
    ),
  );
}