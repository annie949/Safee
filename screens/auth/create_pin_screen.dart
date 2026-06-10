import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/pin_service.dart';
import '../../services/activity_logger.dart';
import '../../services/error_helper.dart';
import '../main_screen.dart';
import 'login_screen.dart';

class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({super.key});

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen>
    with SingleTickerProviderStateMixin {
  int _step = 1;
  String _firstPin = '';
  String _entered = '';

  late AnimationController _shakeCtrl;
  late Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shake = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onKey(String digit) {
    if (_entered.length >= 8) return;
    setState(() {
      _entered += digit;
    });
    if (_entered.length == 8) {
      Future.delayed(const Duration(milliseconds: 200), _handlePin);
    }
  }

  void _onDelete() {
    if (_entered.isNotEmpty) {
      setState(() => _entered = _entered.substring(0, _entered.length - 1));
    }
  }

  Future<void> _handlePin() async {
    if (_step == 1) {
      setState(() {
        _firstPin = _entered;
        _entered = '';
        _step = 2;
      });
    } else {
      if (_entered == _firstPin) {
        // ✅ FIX: Get userId from secure storage (works offline)
        const storage = FlutterSecureStorage();
        String? userId = await storage.read(key: 'last_logged_in_user_id');

        // Fallback to Supabase only if online
        if (userId == null) {
          try {
            final user = Supabase.instance.client.auth.currentUser;
            userId = user?.id;
          } catch (e) {
            print('Error getting user from Supabase: $e');
          }
        }

        // If still no userId, show error and go to login
        if (userId == null) {
          if (mounted) {
            ErrorHelper.showError(context, 'Session expired. Please login again.');
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
            );
          }
          return;
        }

        await PinService.savePin(userId, _entered);

        // Log PIN creation
        await ActivityLogger.logPinCreate();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
              (_) => false,
        );
      } else {
        _shakeCtrl.forward(from: 0);
        ErrorHelper.showError(context, 'PINs do not match. Please try again.');
        setState(() {
          _entered = '';
          _step = 1;
          _firstPin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;

    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              isDark ? const Color(0xFF0C2E4A) : AppColors.primary.withOpacity(0.1),
              bgColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 60),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20)],
                  ),
                  child: Icon(Icons.pin_rounded, color: isDark ? AppColors.dark : Colors.white, size: 36),
                ),
                const SizedBox(height: 24),
                Text(
                  _step == 1 ? 'Create PIN' : 'Confirm PIN',
                  style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _step == 1 ? 'Choose an 8-digit PIN to protect your vault' : 'Enter your PIN again to confirm',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedColor, fontSize: 14),
                ),
                const SizedBox(height: 40),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(_shakeCtrl.isAnimating ? 10 * (0.5 - _shake.value).abs() * (_shake.value > 0.5 ? 1 : -1) * 4 : 0, 0),
                    child: child,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(8, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _entered.length ? AppColors.primary : Colors.transparent,
                        border: Border.all(
                          color: i < _entered.length ? AppColors.primary : borderColor,
                          width: 2,
                        ),
                      ),
                    )),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StepDot(active: _step == 1, done: _step > 1),
                    const SizedBox(width: 8),
                    _StepDot(active: _step == 2, done: false),
                  ],
                ),
                const Spacer(),
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
                      Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your 8-digit PIN is required every time you open the app. After 7 failed attempts, you will need to login again.',
                          style: TextStyle(color: mutedColor, fontSize: 12, height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildNumpad(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
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
        for (var row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '⌫']])
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((k) => _key(k, cardColor, borderColor, textColor)).toList(),
          ),
      ],
    );
  }

  Widget _key(String k, Color cardColor, Color borderColor, Color textColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (k.isEmpty) return const SizedBox(width: 80, height: 72);
    return GestureDetector(
      onTap: () => k == '⌫' ? _onDelete() : _onKey(k),
      child: Container(
        width: 80,
        height: 72,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: k == '⌫' ? AppColors.error.withOpacity(0.12) : (isDark ? cardColor.withOpacity(0.6) : cardColor),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: k == '⌫' ? AppColors.error.withOpacity(0.3) : borderColor),
        ),
        child: Center(
          child: Text(
            k,
            style: TextStyle(color: k == '⌫' ? AppColors.error : textColor, fontSize: k == '⌫' ? 20 : 24, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  const _StepDot({required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: done || active ? AppColors.primary : borderColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}