import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../theme/app_theme.dart';
import '../../services/encryption_service.dart';
import '../../services/pin_service.dart';
import '../../services/activity_logger.dart';
import '../../services/error_helper.dart';
import '../../services/firebase_auth_service.dart';
import '../main_screen.dart';
import 'welcome_screen.dart';

class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  String _entered = '';
  int _attemptsLeft = PinService.maxAttempts;
  bool _loadingKey = false;
  bool _isLockedOut = false;
  late AnimationController _shakeCtrl;
  late Animation<double> _shake;
  String? _userId;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shake = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _loadUserId();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Load User ID and Email
  // FIX: Removed Supabase auth.currentUser —
  // use secure storage and Firebase instead
  // ─────────────────────────────────────────────

  Future<void> _loadUserId() async {
    const storage = FlutterSecureStorage();

    // Get userId from secure storage — saved during login
    final userId = await storage.read(key: 'last_logged_in_user_id');

    if (userId == null) {
      debugPrint('No userId found, redirecting to WelcomeScreen');
      if (mounted) _redirectToWelcome();
      return;
    }

    // Check if PIN exists
    final pin = await storage.read(key: 'user_pin_$userId');
    if (pin == null || pin.isEmpty) {
      debugPrint('No PIN found for user, redirecting to WelcomeScreen');
      if (mounted) _redirectToWelcome();
      return;
    }

    // Get email from Firebase current user
    final firebaseUser = FirebaseAuthService.currentUser;
    final email = firebaseUser?.email;

    if (email == null) {
      debugPrint('No Firebase user found, redirecting to WelcomeScreen');
      if (mounted) _redirectToWelcome();
      return;
    }

    setState(() {
      _userId = userId;
      _userEmail = email;
    });

    _checkLockoutStatus();
  }

  Future<void> _checkLockoutStatus() async {
    if (_userId == null) return;
    final lockedOut = await PinService.isLockedOut(_userId!);
    if (mounted) {
      setState(() {
        _isLockedOut = lockedOut;
        if (!lockedOut) _loadRemainingAttempts();
      });
    }
  }

  Future<void> _loadRemainingAttempts() async {
    if (_userId == null) return;
    final remaining = await PinService.getRemainingAttempts(_userId!);
    if (mounted) {
      setState(() => _attemptsLeft = remaining);
    }
  }

  // ─────────────────────────────────────────────
  // PIN Input
  // ─────────────────────────────────────────────

  void _onKey(String digit) {
    if (_entered.length >= 8 ||
        _loadingKey ||
        _isLockedOut ||
        _userId == null) return;
    setState(() => _entered += digit);
    if (_entered.length == 8) {
      Future.delayed(const Duration(milliseconds: 200), _check);
    }
  }

  void _onDelete() {
    if (_entered.isNotEmpty && !_loadingKey) {
      setState(
              () => _entered = _entered.substring(0, _entered.length - 1));
    }
  }

  // ─────────────────────────────────────────────
  // Core: Check PIN
  // FIX: loadMasterKeyWithPassword now takes
  // email parameter — Firebase is auth system
  // ─────────────────────────────────────────────

  Future<void> _check() async {
    if (_userId == null || _userEmail == null) {
      _redirectToWelcome();
      return;
    }

    if (await PinService.isLockedOut(_userId!)) {
      setState(() {
        _isLockedOut = true;
        _entered = '';
      });
      ErrorHelper.showError(
          context, 'Too many failed attempts. Please login again.');
      await ActivityLogger.logPinLockout();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _redirectToWelcome();
      });
      return;
    }

    final storedPin = await PinService.getPin(_userId!);

    if (_entered != storedPin) {
      final attempts =
      await PinService.recordFailedAttempt(_userId!);
      final remaining = PinService.maxAttempts - attempts;

      await ActivityLogger.logPinFailed(remaining);
      _shakeCtrl.forward(from: 0);

      if (remaining <= 0) {
        setState(() {
          _isLockedOut = true;
          _entered = '';
        });
        ErrorHelper.showError(
            context, 'Too many failed attempts. Please login again.');
        await ActivityLogger.logPinLockout();
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _redirectToWelcome();
        });
      } else {
        ErrorHelper.showError(
          context,
          'Incorrect PIN. $remaining attempt${remaining != 1 ? 's' : ''} remaining.',
        );
        setState(() {
          _entered = '';
          _attemptsLeft = remaining;
        });
      }
      return;
    }

    // PIN correct
    await PinService.resetAttempts(_userId!);
    await ActivityLogger.logPinSuccess();

    setState(() => _loadingKey = true);

    const storage = FlutterSecureStorage();
    final password =
    await storage.read(key: 'user_password_$_userId');

    if (password == null) {
      debugPrint('No password found in secure storage');
      if (!mounted) return;
      _redirectToWelcome();
      return;
    }

    // FIX: Pass both password and email
    final keyLoaded = await EncryptionService.loadMasterKeyWithPassword(
      password: password,
      email: _userEmail!,
    );

    if (!mounted) return;

    if (!keyLoaded) {
      debugPrint('Master key load failed');
      await storage.delete(key: 'user_password_$_userId');
      EncryptionService.clearKey();
      _redirectToWelcome();
      return;
    }

    debugPrint('PIN correct — navigating to MainScreen');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
          (_) => false,
    );
  }

  // ─────────────────────────────────────────────
  // Redirect to Welcome
  // FIX: Removed Supabase auth.signOut —
  // only sign out Firebase
  // ─────────────────────────────────────────────

  void _redirectToWelcome() async {
    EncryptionService.clearKey();

    const storage = FlutterSecureStorage();
    if (_userId != null) {
      await storage.delete(key: 'user_password_$_userId');
      await storage.delete(key: 'user_pin_$_userId');
    }
    await storage.delete(key: 'last_logged_in_user_id');

    // Sign out Firebase — not Supabase auth
    try {
      await FirebaseAuthService.signOut();
    } catch (_) {}

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (_) => false,
      );
    }
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;

    if (_userId == null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isDark
                      ? const Color(0xFF0C2E4A)
                      : AppColors.primary.withOpacity(0.1),
                  bgColor,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primaryLight
                          ]),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 20)
                      ],
                    ),
                    child: Icon(Icons.lock_rounded,
                        color: isDark ? AppColors.dark : Colors.white,
                        size: 36),
                  ),
                  const SizedBox(height: 24),
                  Text('Enter PIN',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 24,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('Enter your 8-digit vault PIN',
                      style:
                      TextStyle(color: mutedColor, fontSize: 14)),
                  const SizedBox(height: 40),

                  // PIN dots
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(
                        _shakeCtrl.isAnimating
                            ? 10 *
                            (0.5 - _shake.value).abs() *
                            (_shake.value > 0.5 ? 1 : -1) *
                            4
                            : 0,
                        0,
                      ),
                      child: child,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        8,
                            (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin:
                          const EdgeInsets.symmetric(horizontal: 6),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _entered.length
                                ? AppColors.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: i < _entered.length
                                  ? AppColors.primary
                                  : borderColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (_loadingKey) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(
                        color: AppColors.primary),
                  ],

                  const Spacer(),
                  _buildNumpad(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumpad() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;

    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '⌫']
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row
                .map((k) => _key(k, cardColor, borderColor, textColor))
                .toList(),
          ),
      ],
    );
  }

  Widget _key(String k, Color cardColor, Color borderColor,
      Color textColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (k.isEmpty) return const SizedBox(width: 80, height: 72);
    return GestureDetector(
      onTap: () => k == '⌫' ? _onDelete() : _onKey(k),
      child: Container(
        width: 80,
        height: 72,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: k == '⌫'
              ? AppColors.error.withOpacity(0.12)
              : (isDark ? cardColor.withOpacity(0.6) : cardColor),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: k == '⌫'
                ? AppColors.error.withOpacity(0.3)
                : borderColor,
          ),
        ),
        child: Center(
          child: Text(
            k,
            style: TextStyle(
              color: k == '⌫' ? AppColors.error : textColor,
              fontSize: k == '⌫' ? 20 : 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}