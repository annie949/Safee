import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EncryptionService {
  static Uint8List? _masterKey;

  static bool get hasKey => _masterKey != null;

  static Uint8List get masterKey {
    if (_masterKey == null) throw Exception('Master key not loaded');
    return _masterKey!;
  }

  static void clearKey() => _masterKey = null;

  // ─────────────────────────────────────────────
  // Key Generation
  // ─────────────────────────────────────────────

  static String generateRecoveryKey() {
    final random = Random.secure();
    final bytes = List.generate(32, (_) => random.nextInt(256));
    final hexString = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    final groups = <String>[];
    for (int i = 0; i < hexString.length; i += 4) {
      groups.add(hexString.substring(i, i + 4));
    }
    return groups.join('-');
  }

  static Uint8List _generateMasterKey() {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(32, (_) => random.nextInt(256)));
  }

  // ─────────────────────────────────────────────
  // AES Encryption Helpers
  // ─────────────────────────────────────────────

  static Uint8List _deriveKey(String secret) {
    final bytes = utf8.encode(secret);
    final hash = sha256.convert(bytes);
    return Uint8List.fromList(hash.bytes);
  }

  static String _encrypt(Uint8List data, String secret) {
    final keyBytes = _deriveKey(secret);
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter =
    enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    return '${base64.encode(iv.bytes)}:${encrypted.base64}';
  }

  static Uint8List? _decrypt(String stored, String secret) {
    try {
      final parts = stored.split(':');
      if (parts.length != 2) return null;

      final iv = enc.IV(base64.decode(parts[0]));
      final ciphertext = enc.Encrypted(base64.decode(parts[1]));
      final keyBytes = _deriveKey(secret);
      final key = enc.Key(keyBytes);
      final encrypter =
      enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return Uint8List.fromList(
          encrypter.decryptBytes(ciphertext, iv: iv));
    } catch (e) {
      debugPrint('Decryption error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // SIGNUP: Generate and Store Keys
  // Uses email to find user — Firebase is auth
  // ─────────────────────────────────────────────

  static Future<void> generateAndStoreKeys({
    required String password,
    required String recoveryKey,
    required String email,
  }) async {
    final supabase = Supabase.instance.client;

    // Find user by email in your users table
    final userRes = await supabase
        .from('users')
        .select('id')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();

    if (userRes == null) {
      throw Exception('User not found. Please sign up again.');
    }

    final userId = userRes['id'] as String;
    debugPrint('Generating master key for user: $userId');

    final masterKey = _generateMasterKey();
    final passwordEncrypted = _encrypt(masterKey, password);
    final recoveryEncrypted = _encrypt(masterKey, recoveryKey);

    await supabase.from('user_keys').upsert({
      'user_id': userId,
      'email': email.trim().toLowerCase(),
      'password_encrypted_key': passwordEncrypted,
      'recovery_encrypted_key': recoveryEncrypted,
    }, onConflict: 'user_id');

    _masterKey = masterKey;
    debugPrint('Master key stored successfully for: $email');
  }

  // ─────────────────────────────────────────────
  // LOGIN: Load Master Key With Password
  // Uses email to find user — Firebase is auth
  // ─────────────────────────────────────────────

  static Future<bool> loadMasterKeyWithPassword({
    required String password,
    required String email,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      final res = await supabase
          .from('user_keys')
          .select('password_encrypted_key')
          .eq('email', email.trim().toLowerCase())
          .maybeSingle();

      if (res == null) {
        debugPrint('No user_keys found for email: $email');
        return false;
      }

      final stored = res['password_encrypted_key'] as String;
      final masterKey = _decrypt(stored, password);
      if (masterKey == null) return false;

      _masterKey = masterKey;
      return true;
    } catch (e) {
      debugPrint('Load master key error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // FORGOT PASSWORD: Load by Email + Recovery Key
  // ─────────────────────────────────────────────

  static Future<bool> loadMasterKeyWithRecoveryKeyByEmail({
    required String email,
    required String recoveryKey,
  }) async {
    try {
      debugPrint('Loading master key with recovery for: $email');

      final supabase = Supabase.instance.client;

      final res = await supabase
          .from('user_keys')
          .select('recovery_encrypted_key, user_id')
          .eq('email', email.trim().toLowerCase())
          .maybeSingle();

      if (res == null) {
        debugPrint('No user_keys record found for email: $email');
        return false;
      }

      final stored = res['recovery_encrypted_key'] as String;

      // Try with dashes as-is
      var masterKey = _decrypt(stored, recoveryKey);

      if (masterKey == null) {
        // Try without dashes
        final keyNoDashes = recoveryKey.replaceAll('-', '').trim();
        masterKey = _decrypt(stored, keyNoDashes);
      }

      if (masterKey == null) {
        // Try lowercase
        final keyLower = recoveryKey.toLowerCase();
        masterKey = _decrypt(stored, keyLower);
      }

      if (masterKey == null) {
        debugPrint('All decryption attempts failed');
        return false;
      }

      debugPrint('Decryption successful');
      _masterKey = masterKey;
      return true;
    } catch (e) {
      debugPrint('Exception in loadMasterKeyWithRecoveryKeyByEmail: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // AFTER PASSWORD RESET: Re-encrypt Master Key
  // ─────────────────────────────────────────────

  static Future<void> reEncryptAfterPasswordReset({
    required String newPassword,
    required String newRecoveryKey,
    required String email,
  }) async {
    if (_masterKey == null) throw Exception('Master key not in memory');

    final supabase = Supabase.instance.client;

    final passwordEncrypted = _encrypt(_masterKey!, newPassword);
    final recoveryEncrypted = _encrypt(_masterKey!, newRecoveryKey);

    await supabase.from('user_keys').update({
      'password_encrypted_key': passwordEncrypted,
      'recovery_encrypted_key': recoveryEncrypted,
    }).eq('email', email.trim().toLowerCase());

    debugPrint('Password reset completed for: $email');
  }

  // ─────────────────────────────────────────────
  // FILE ENCRYPTION
  // ─────────────────────────────────────────────

  static Uint8List encryptFile(Uint8List fileBytes) {
    if (_masterKey == null) throw Exception('Master key not loaded');
    final key = enc.Key(_masterKey!);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter =
    enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);
    final ivBytes = iv.bytes;
    final result = Uint8List(ivBytes.length + encrypted.bytes.length);
    result.setRange(0, ivBytes.length, ivBytes);
    result.setRange(
        ivBytes.length, result.length, encrypted.bytes);
    return result;
  }

  static Uint8List decryptFile(Uint8List encryptedBytes) {
    if (_masterKey == null) throw Exception('Master key not loaded');
    final iv = enc.IV(encryptedBytes.sublist(0, 16));
    final ciphertext =
    enc.Encrypted(encryptedBytes.sublist(16));
    final key = enc.Key(_masterKey!);
    final encrypter =
    enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return Uint8List.fromList(
        encrypter.decryptBytes(ciphertext, iv: iv));
  }
  // ─────────────────────────────────────────────
// COMPATIBILITY WRAPPERS (FIX FOR UI ERRORS)
// ─────────────────────────────────────────────

  static Uint8List encryptWithKey(Uint8List data, String key) {
    final result = _encrypt(data, key);
    return Uint8List.fromList(utf8.encode(result));
  }

  static Uint8List decryptWithKey(Uint8List data, String key) {
    try {
      final stored = utf8.decode(data);
      final result = _decrypt(stored, key);
      if (result == null) {
        throw Exception("Decryption failed");
      }
      return result;
    } catch (e) {
      throw Exception("decryptWithKey error: $e");
    }
  }
}
