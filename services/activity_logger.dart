import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

class ActivityLogger {
  // Singleton pattern for easy access
  static final ActivityLogger _instance = ActivityLogger._internal();
  factory ActivityLogger() => _instance;
  ActivityLogger._internal();

  static String? _currentUserId;

  // Initialize with current user
  static void init(String userId) {
    _currentUserId = userId;
  }

  // Clear on logout
  static void clear() {
    _currentUserId = null;
  }

  // Main logging method
  static Future<void> log({
    required String action,
    required String description,
    String? details,
    String? error,
  }) async {
    if (_currentUserId == null) {
      // Try to get current user
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        _currentUserId = user.id;
      } else {
        debugPrint('ActivityLogger: No user logged in - skipping log: $action');
        return;
      }
    }

    final fullDescription = details != null
        ? '$description | Details: $details'
        : (error != null
        ? '$description | Error: $error'
        : description);

    await DatabaseService.logActivity(
      userId: _currentUserId!,
      action: action,
      description: fullDescription,
    );
  }

  // ==================== AUTHENTICATION LOGS ====================

  static Future<void> logLogin(String email) => log(
    action: 'login',
    description: 'User logged in successfully',
    details: 'Email: $email',
  );

  static Future<void> logLoginFailed(String email, String reason) => log(
    action: 'login_failed',
    description: 'Failed login attempt',
    details: 'Email: $email',
    error: reason,
  );

  static Future<void> logLogout() => log(
    action: 'logout',
    description: 'User logged out',
  );

  static Future<void> logSignup(String email) => log(
    action: 'signup',
    description: 'New user registered',
    details: 'Email: $email',
  );

  static Future<void> logPasswordReset(String email) => log(
    action: 'password_reset',
    description: 'Password reset completed',
    details: 'Email: $email',
  );

  static Future<void> logPasswordChange() => log(
    action: 'password_change',
    description: 'Password changed successfully',
  );

  // ==================== FILE OPERATION LOGS ====================

  static Future<void> logFileUpload(String fileName, int sizeBytes, bool isCloudBackup) => log(
    action: 'file_upload',
    description: 'File uploaded to vault',
    details: 'Name: $fileName, Size: ${_formatSize(sizeBytes)}, Cloud backup: $isCloudBackup',
  );

  static Future<void> logFileDelete(String fileName, bool isPermanent) => log(
    action: 'file_delete',
    description: isPermanent ? 'File permanently deleted' : 'File moved to trash',
    details: 'Name: $fileName',
  );

  static Future<void> logFileRestore(String fileName) => log(
    action: 'file_restore',
    description: 'File restored from trash',
    details: 'Name: $fileName',
  );

  static Future<void> logFileRename(String oldName, String newName) => log(
    action: 'file_rename',
    description: 'File renamed',
    details: 'From: "$oldName" → To: "$newName"',
  );

  static Future<void> logFileExport(String fileName) => log(
    action: 'file_export',
    description: 'File exported to device storage',
    details: 'Name: $fileName',
  );

  static Future<void> logFileShare(String fileName, String recipientEmail) => log(
    action: 'file_share',
    description: 'File shared with another user',
    details: 'Name: $fileName, Shared with: $recipientEmail',
  );

  static Future<void> logFileView(String fileName) => log(
    action: 'file_view',
    description: 'File previewed/opened',
    details: 'Name: $fileName',
  );

  // ==================== PIN OPERATION LOGS ====================

  static Future<void> logPinCreate() => log(
    action: 'pin_create',
    description: 'PIN created for vault access',
  );

  static Future<void> logPinChange() => log(
    action: 'pin_change',
    description: 'PIN changed successfully',
  );

  static Future<void> logPinFailed(int attemptsLeft) => log(
    action: 'pin_failed',
    description: 'Incorrect PIN entered',
    details: 'Attempts remaining: $attemptsLeft',
  );

  static Future<void> logPinLockout() => log(
    action: 'pin_lockout',
    description: 'Too many failed PIN attempts - forced logout',
  );

  static Future<void> logPinSuccess() => log(
    action: 'pin_success',
    description: 'Vault unlocked with PIN',
  );

  // ==================== SECURITY LOGS ====================

  static Future<void> logDataWipe() => log(
    action: 'data_wipe',
    description: 'All vault data wiped permanently',
  );

  static Future<void> logEncryptionKeyLoaded() => log(
    action: 'encryption_ready',
    description: 'Encryption key loaded successfully',
  );

  // ==================== APP LIFECYCLE LOGS ====================

  static Future<void> logAppOpen() => log(
    action: 'app_open',
    description: 'Application started',
  );

  static Future<void> logAppClose() => log(
    action: 'app_close',
    description: 'Application closed',
  );

  // ==================== CLOUD/SYNC LOGS ====================

  static Future<void> logCloudSync(String type) => log(
    action: 'cloud_sync',
    description: 'Cloud sync performed',
    details: 'Type: $type',
  );

  static Future<void> logCloudBackup(String fileName) => log(
    action: 'cloud_backup',
    description: 'File backed up to cloud storage',
    details: 'Name: $fileName',
  );

  static Future<void> logCloudRestore(String fileName) => log(
    action: 'cloud_restore',
    description: 'File restored from cloud storage',
    details: 'Name: $fileName',
  );

  // ==================== ERROR LOGS ====================

  static Future<void> logError(String action, String error, {String? context}) => log(
    action: 'error',
    description: 'Error occurred',
    details: 'Action: $action, Context: ${context ?? "N/A"}',
    error: error,
  );

  // ==================== HELPER ====================

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}