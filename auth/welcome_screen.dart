import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFF0C2E4A),
                  AppColors.darkBg,
                  Color(0xFF0A2540)
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.mint, AppColors.teal]),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.mint.withOpacity(0.3),
                              blurRadius: 10)
                        ],
                      ),
                      child: const Icon(Icons.lock_rounded,
                          color: AppColors.dark, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Safe Locker',
                            style: TextStyle(
                                color: AppColors.soft,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        Text('AES-256 ENCRYPTED',
                            style: TextStyle(
                                color: AppColors.mint,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2)),
                      ],
                    ),
                  ]),
                  const Spacer(),
                  const Text('👋', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 16),
                  const Text('Welcome Back',
                      style: TextStyle(
                          color: AppColors.soft,
                          fontSize: 30,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                      'Your encrypted vault is waiting.\nSign in to access your secure files.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.muted.withOpacity(0.8),
                          fontSize: 14,
                          height: 1.6)),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen())),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_open_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Login to My Vault'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignupScreen())),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.soft,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Create New Account',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen())),
                    child: RichText(
                      text: TextSpan(
                        text: 'Need help? ',
                        style: TextStyle(
                            color: AppColors.muted.withOpacity(0.6),
                            fontSize: 13),
                        children: const [
                          TextSpan(
                              text: 'Forgot Password',
                              style: TextStyle(
                                  color: AppColors.mint,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('Safe Locker v1.0 • Military-Grade AES-256',
                      style: TextStyle(
                          color: AppColors.muted.withOpacity(0.3),
                          fontSize: 11)),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
