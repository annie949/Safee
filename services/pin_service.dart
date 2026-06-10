import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinService {
  static const _storage = FlutterSecureStorage();

  // Max failed attempts before requiring full login
  static const int maxAttempts = 7;

  // Get key for failed attempts count
  static String _attemptsKey(String userId) => 'pin_attempts_$userId';

  // Get key for last attempt time
  static String _lastAttemptKey(String userId) => 'last_pin_attempt_$userId';

  // Get key for PIN
  static String _pinKey(String userId) => 'user_pin_$userId';

  // Save PIN for user
  static Future<void> savePin(String userId, String pin) async {
    await _storage.write(key: _pinKey(userId), value: pin);
    // Reset attempts when new PIN is set
    await resetAttempts(userId);
  }

  // Get stored PIN
  static Future<String?> getPin(String userId) async {
    return await _storage.read(key: _pinKey(userId));
  }

  // Check if PIN exists
  static Future<bool> hasPin(String userId) async {
    final pin = await getPin(userId);
    return pin != null && pin.length == 8;
  }

  // Record failed attempt
  static Future<int> recordFailedAttempt(String userId) async {
    final attempts = await getFailedAttempts(userId);
    final newAttempts = attempts + 1;

    await _storage.write(key: _attemptsKey(userId), value: newAttempts.toString());
    await _storage.write(key: _lastAttemptKey(userId), value: DateTime.now().toIso8601String());

    return newAttempts;
  }

  // Get current failed attempts count
  static Future<int> getFailedAttempts(String userId) async {
    final attemptsStr = await _storage.read(key: _attemptsKey(userId));
    if (attemptsStr == null) return 0;
    return int.tryParse(attemptsStr) ?? 0;
  }

  // Reset attempts on successful PIN entry
  static Future<void> resetAttempts(String userId) async {
    await _storage.delete(key: _attemptsKey(userId));
    await _storage.delete(key: _lastAttemptKey(userId));
  }

  // Check if user is locked out (exceeded max attempts)
  static Future<bool> isLockedOut(String userId) async {
    final attempts = await getFailedAttempts(userId);
    return attempts >= maxAttempts;
  }

  // Get remaining attempts
  static Future<int> getRemainingAttempts(String userId) async {
    final attempts = await getFailedAttempts(userId);
    return maxAttempts - attempts;
  }

  // Delete PIN and attempts for user (on logout)
  static Future<void> deletePin(String userId) async {
    await _storage.delete(key: _pinKey(userId));
    await resetAttempts(userId);
  }
}