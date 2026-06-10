import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingSignupService {
  static const _storage = FlutterSecureStorage();

  static const String _keyEmail = 'pending_signup_email';
  static const String _keyPassword = 'pending_signup_password';
  static const String _keyUsername = 'pending_signup_username';

  // Save pending signup data
  static Future<void> savePendingSignup({
    required String email,
    required String password,
    required String username,
  }) async {
    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyUsername, value: username);
  }

  // Get pending signup data
  static Future<Map<String, String?>?> getPendingSignup() async {
    final email = await _storage.read(key: _keyEmail);
    final password = await _storage.read(key: _keyPassword);
    final username = await _storage.read(key: _keyUsername);

    if (email == null || password == null || username == null) {
      return null;
    }

    return {
      'email': email,
      'password': password,
      'username': username,
    };
  }

  // Clear pending signup data
  static Future<void> clearPendingSignup() async {
    await _storage.delete(key: _keyEmail);
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keyUsername);
  }

  // Check if user's email is verified in Firebase
  static Future<bool> isEmailVerified(String email) async {
    // We need to check Firebase - but since Firebase doesn't have a direct API
    // to check verification without signing in, we'll use a different approach
    // This will be handled in the verification screen
    return false;
  }
}