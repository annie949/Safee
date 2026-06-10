import 'package:supabase_flutter/supabase_flutter.dart';

class OtpService {
  static final supabase = Supabase.instance.client;

  // Verify OTP code entered by user
  static Future<bool> verifyOtp(String email, String otpCode) async {
    try {
      await supabase.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: otpCode,
      );
      return true;
    } catch (e) {
      print('OTP verification failed: $e');
      return false;
    }
  }

  // Resend OTP code
  static Future<bool> resendOtp(String email) async {
    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      return true;
    } catch (e) {
      print('Resend failed: $e');
      return false;
    }
  }

  // Check if user's email is verified
  static Future<bool> isEmailVerified() async {
    final user = supabase.auth.currentUser;
    return user?.emailConfirmedAt != null;
  }
}