import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../services/otp_service.dart';
import '../../../services/error_helper.dart';
import 'recovery_key_screen.dart';

class VerifyOtpScreen extends StatefulWidget {
  final String email;
  final String password;

  const VerifyOtpScreen({
    super.key,
    required this.email,
    required this.password,
  });

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() => _resendCooldown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && _resendCooldown > 0) {
        setState(() => _resendCooldown--);
        return true;
      }
      return false;
    });
  }

  Future<void> _verifyOtp() async {
    final otpCode = _otpControllers.map((c) => c.text).join();

    if (otpCode.length != 6) {
      ErrorHelper.showError(context, 'Please enter the 6-digit verification code');
      return;
    }

    setState(() => _isLoading = true);

    final verified = await OtpService.verifyOtp(widget.email, otpCode);

    if (verified && mounted) {
      // Move to recovery key screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RecoveryKeyScreen(
            isNew: true,
            password: widget.password,
          ),
        ),
      );
    } else if (mounted) {
      ErrorHelper.showError(context, 'Invalid verification code. Please try again.');
      _clearOtpFields();
    }

    setState(() => _isLoading = false);
  }

  void _clearOtpFields() {
    for (var controller in _otpControllers) {
      controller.clear();
    }
    _focusNodes[0].requestFocus();
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0) return;

    setState(() => _isLoading = true);
    final success = await OtpService.resendOtp(widget.email);

    if (success && mounted) {
      ErrorHelper.showSuccess(context, 'Verification code resent!');
      _startResendCooldown();
      _clearOtpFields();
    } else if (mounted) {
      ErrorHelper.showError(context, 'Failed to resend code. Please try again.');
    }

    setState(() => _isLoading = false);
  }

  void _onOtpChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    // Auto-submit when all fields filled
    if (_otpControllers.every((c) => c.text.length == 1)) {
      _verifyOtp();
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back_ios_rounded, color: mutedColor),
                  padding: EdgeInsets.zero,
                ),
              ),

              const SizedBox(height: 20),

              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.email_rounded, color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Verify Your Email',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the 6-digit code sent to',
                style: TextStyle(color: mutedColor, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                widget.email,
                style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 32),

              // OTP Input Fields
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 50,
                    height: 60,
                    child: TextField(
                      controller: _otpControllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: textColor),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                      ),
                      onChanged: (value) => _onOtpChanged(index, value),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),

              // Verify button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Verify', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),

              // Resend code
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Didn't receive code? ", style: TextStyle(color: mutedColor)),
                  GestureDetector(
                    onTap: _resendCooldown > 0 ? null : _resendCode,
                    child: Text(
                      _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend Code',
                      style: TextStyle(
                        color: _resendCooldown > 0 ? mutedColor : AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}