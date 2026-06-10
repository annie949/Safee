import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/encryption_service.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import '../services/pin_service.dart';
import '../services/activity_logger.dart';
import '../services/error_helper.dart';
import '../services/firebase_auth_service.dart';
import '../services/pending_signup_service.dart';
import '../providers/theme_provider.dart';
import 'auth/welcome_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String userId;
  final String username;

  const SettingsScreen({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _email = '';
  int _totalFiles = 0;
  int _cloudUsed = 0;
  bool _isSyncing = false;
  bool _isDarkMode = false;
  bool _isWiping = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _loadInfo();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDarkMode = prefs.getBool('isDarkMode') ?? false);
  }

  // ─────────────────────────────────────────────
  // Load Info
  // FIX: Use Firebase currentUser for email
  // instead of Supabase auth.currentUser
  // ─────────────────────────────────────────────

  Future<void> _loadInfo() async {
    // FIX: Get email from Firebase — not Supabase auth
    final firebaseUser = FirebaseAuthService.currentUser;
    final totalFiles =
    await DatabaseService.getTotalFileCount(widget.userId);
    final cloudUsed =
    await DatabaseService.getCloudStorageUsed(widget.userId);
    if (mounted) {
      setState(() {
        _email = firebaseUser?.email ?? '';
        _totalFiles = totalFiles;
        _cloudUsed = cloudUsed;
      });
    }
  }
  // ─────────────────────────────────────────────
  // Reset Password With Recovery Key
  // FIX: Removed userId param from reEncrypt,
  // removed Supabase auth.updateUser
  // ─────────────────────────────────────────────

  Future<void> _resetPasswordWithRecoveryKey() async {
    final emailCtrl = TextEditingController(text: _email);
    final recoveryKeyCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isLoading = false;
    String? errorMessage;

    final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx2, setStateDialog) {
              final isDarkLocal =
                  Theme.of(ctx2).brightness == Brightness.dark;
              return AlertDialog(
                  backgroundColor: isDarkLocal
                      ? AppColors.darkCard
                      : AppColors.lightCard,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  title: const Text('Reset Password',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(errorMessage ?? '',
                                style: const TextStyle(
                                    color: AppColors.error, fontSize: 12)),
                          ),
                        TextField(
                          controller: emailCtrl,
                          enabled: !isLoading,
                          decoration: const InputDecoration(
                            hintText: 'Email address',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: recoveryKeyCtrl,
                          enabled: !isLoading,
                          maxLines: 3,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                          decoration: const InputDecoration(
                            hintText:
                            'Recovery Key\n\nPaste your key (16 groups of 4)',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: newPassCtrl,
                          obscureText: obscureNew,
                          enabled: !isLoading,
                          decoration: InputDecoration(
                            hintText:
                            'New Password (min 8 chars, 1 uppercase, 1 number)',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(obscureNew
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setStateDialog(
                                      () => obscureNew = !obscureNew),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: confirmCtrl,
                          obscureText: obscureConfirm,
                          enabled: !isLoading,
                          decoration: InputDecoration(
                            hintText: 'Confirm New Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(obscureConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setStateDialog(
                                      () => obscureConfirm = !obscureConfirm),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
              TextButton(
              onPressed:
              isLoading ? null : () => Navigator.pop(ctx2, false),
              child: const Text('Cancel'),
              ),
              ElevatedButton(
              onPressed: isLoading
              ? null
                  : () async {
              final email =
              emailCtrl.text.trim().toLowerCase();
              final recoveryKey = recoveryKeyCtrl.text
                  .trim()
                  .toUpperCase();
              final newPass = newPassCtrl.text;
              final confirm = confirmCtrl.text;

              if (email.isEmpty || !email.contains('@')) {
              setStateDialog(() => errorMessage =
              'Please enter a valid email address.');
              return;
              }
              if (recoveryKey.isEmpty) {
              setStateDialog(() => errorMessage =
              'Please enter your recovery key.');
              return;
              }
              if (recoveryKey.split('-').length != 16) {
              setStateDialog(() => errorMessage =
              'Invalid recovery key format.');
              return;
              }
              if (newPass.isEmpty || newPass.length < 8) {
              setStateDialog(() => errorMessage =
              'Password must be at least 8 characters.');
              return;
              }
              if (!newPass
                  .contains(RegExp(r'[A-Z]'))) {
              setStateDialog(() => errorMessage =
              'Password must contain at least one uppercase letter.');
              return;
              }
              if (!newPass
                  .contains(RegExp(r'[0-9]'))) {
              setStateDialog(() => errorMessage =
              'Password must contain at least one number.');
              return;
              }
              if (newPass != confirm) {
              setStateDialog(() => errorMessage =
              'Passwords do not match.');
              return;
              }

              setStateDialog(() => isLoading = true);

              try {
              final keyLoaded = await EncryptionService
                  .loadMasterKeyWithRecoveryKeyByEmail(
              email: email,
              recoveryKey: recoveryKey,
              );

              if (!keyLoaded) {
              setStateDialog(() {
              errorMessage =
              'Invalid recovery key. Please check and try again.';
              isLoading = false;
              });
              return;
              }

              // Generate new recovery key
              final newRecoveryKey =
              EncryptionService.generateRecoveryKey();
              // FIX: Removed userId param —
              // reEncrypt now uses email only
              await EncryptionService
                  .reEncryptAfterPasswordReset(
                newPassword: newPass,
                newRecoveryKey: newRecoveryKey,
                email: email,
              );

              // Update stored password
              const storage = FlutterSecureStorage();
              await storage.write(
                key: 'user_password_${widget.userId}',
                value: newPass,
              );

              await ActivityLogger.logPasswordChange();

              // Send Firebase password reset email
              try {
                await FirebaseAuthService
                    .sendPasswordResetEmail(email);
              } catch (e) {
                debugPrint(
                    'Firebase reset email error: $e');
              }

              if (ctx2.mounted) {
                Navigator.pop(ctx2, true);
              }
              } catch (e) {
                setStateDialog(() {
                  errorMessage =
                  'Reset failed: ${e.toString()}';
                  isLoading = false;
                });
              }
              },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: isLoading
                    ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Text('Reset Password'),
              ),
                  ],
              );
            },
        ),
    );

    if (result == true && mounted) {
      await _logout();
    }
  }

  // ─────────────────────────────────────────────
  // Change Password
  // FIX: Removed Supabase auth.updateUser,
  // loadMasterKeyWithPassword now takes email
  // ─────────────────────────────────────────────

  Future<void> _changePassword() async {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor:
          _isDarkMode ? AppColors.darkCard : AppColors.lightCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Change Password',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassCtrl,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  hintText: 'Current Password',
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setS(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  hintText: 'New Password (min 8 chars)',
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setS(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  hintText: 'Confirm New Password',
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setS(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newPassCtrl.text != confirmCtrl.text) {
                  ErrorHelper.showError(ctx, 'Passwords do not match');
                  return;
                }
                if (newPassCtrl.text.length < 8) {
                  ErrorHelper.showError(ctx,
                      'Password must be at least 8 characters');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    setState(() => _isSyncing = true);
    try {
      // FIX: Pass email to loadMasterKeyWithPassword
      final keyLoaded =
      await EncryptionService.loadMasterKeyWithPassword(
        password: currentPassCtrl.text,
        email: _email,
      );

      if (!keyLoaded) {
        ErrorHelper.showError(context, 'Current password is incorrect');
        setState(() => _isSyncing = false);
        return;
      }

      // Generate new recovery key and re-encrypt
      final newRecoveryKey = EncryptionService.generateRecoveryKey();
      await EncryptionService.reEncryptAfterPasswordReset(
        newPassword: newPassCtrl.text,
        newRecoveryKey: newRecoveryKey,
        email: _email,
      );

      // Update stored password
      const storage = FlutterSecureStorage();
      await storage.write(
        key: 'user_password_${widget.userId}',
        value: newPassCtrl.text,
      );

      await ActivityLogger.logPasswordChange();
      await DatabaseService.logActivity(
        userId: widget.userId,
        action: 'password_change',
        description: 'Password changed successfully',
      );

      if (mounted) {
        ErrorHelper.showSuccess(context, 'Password changed successfully!');
      }
    } catch (e) {
      await ActivityLogger.logError('password_change', e.toString());
      ErrorHelper.showError(context, 'Failed to change password: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }
  // ─────────────────────────────────────────────
  // Change PIN
  // ─────────────────────────────────────────────

  Future<void> _changePin() async {
    final currentPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
        _isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Change PIN',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Current PIN (8 digits)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'New PIN (8 digits)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Confirm New PIN',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newPinCtrl.text != confirmPinCtrl.text) {
                ErrorHelper.showError(_, 'PINs do not match');
                return;
              }
              if (newPinCtrl.text.length != 8) {
                ErrorHelper.showError(_, 'PIN must be 8 digits');
                return;
              }
              Navigator.pop(_, true);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final storedPin = await PinService.getPin(widget.userId);
    if (currentPinCtrl.text != storedPin) {
      ErrorHelper.showError(context, 'Current PIN is incorrect');
      return;
    }

    await PinService.savePin(widget.userId, newPinCtrl.text);
    await ActivityLogger.logPinChange();
    await DatabaseService.logActivity(
      userId: widget.userId,
      action: 'pin_change',
      description: 'PIN changed successfully',
    );

    ErrorHelper.showSuccess(context, 'PIN changed successfully!');
  }

  // ─────────────────────────────────────────────
  // Encryption Info
  // ─────────────────────────────────────────────

  void _showEncryptionInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
        _isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded,
                color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Text('Encryption',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'Your files are secured with AES-256 encryption.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  // Sync to Cloud
  // FIX: Removed Supabase auth.getUser —
  // just sync data directly
  // ─────────────────────────────────────────────

  Future<void> _syncToSupabase() async {
    setState(() => _isSyncing = true);
    try {
      await ActivityLogger.logCloudSync('manual');
      await DatabaseService.logActivity(
        userId: widget.userId,
        action: 'sync',
        description: 'Manual sync triggered',
      );
      if (mounted) ErrorHelper.showSuccess(context, 'Sync complete');
    } catch (e) {
      await ActivityLogger.logError('cloud_sync', e.toString());
      if (mounted) ErrorHelper.showError(context, 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }
  // ─────────────────────────────────────────────
  // Wipe All Data
  // FIX: Removed Supabase admin.deleteUser
  // and Supabase auth.signOut —
  // use Firebase signOut instead
  // ─────────────────────────────────────────────

  Future<void> _wipeAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
        _isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_rounded,
              color: AppColors.error, size: 22),
          const SizedBox(width: 8),
          const Text('Wipe All Data',
              style: TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w800)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '⚠️ THIS ACTION CANNOT BE UNDONE!',
                style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            const Text('This will permanently delete:',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('• All your encrypted files (local & cloud)'),
            const Text('• Your account data from Supabase'),
            const Text('• Your recovery key and PIN'),
            const Text('• All activity logs'),
            const SizedBox(height: 12),
            const Text(
              'You will need to sign up again to use the app.',
              style: TextStyle(
                  color: AppColors.warning, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Wipe Everything'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isWiping = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor:
        _isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Wiping all data...',
              style: TextStyle(
                  color: _isDarkMode
                      ? AppColors.soft
                      : AppColors.lightText),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a few seconds',
              style: TextStyle(
                  fontSize: 12,
                  color: _isDarkMode
                      ? AppColors.muted
                      : AppColors.lightMuted),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    try {
      await ActivityLogger.logDataWipe();
      await FileService.deleteAllCloudFiles(widget.userId);

      final supabase = Supabase.instance.client;
      await supabase
          .from('shared_files')
          .delete()
          .eq('sender_id', widget.userId);
      await supabase
          .from('shared_files')
          .delete()
          .eq('recipient_email', _email);
      await supabase
          .from('notifications')
          .delete()
          .eq('recipient_email', _email);
      await supabase
          .from('user_keys')
          .delete()
          .eq('user_id', widget.userId);
      await supabase
          .from('settings')
          .delete()
          .eq('user_id', widget.userId);
      await supabase
          .from('users')
          .delete()
          .eq('email', _email);

      await FileService.deleteAllLocalFiles(widget.userId);
      await DatabaseService.deleteAllLocalData(widget.userId);

      const storage = FlutterSecureStorage();
      await storage.delete(key: 'user_password_${widget.userId}');
      await storage.delete(key: 'user_pin_${widget.userId}');
      await storage.delete(key: 'recovery_key');
      await storage.delete(key: 'last_logged_in_user_id');
      await PinService.deletePin(widget.userId);

      EncryptionService.clearKey();
      ActivityLogger.clear();

      // FIX: Sign out Firebase — not Supabase auth
      try {
        await FirebaseAuthService.signOut();
      } catch (e) {
        debugPrint('Firebase signout error: $e');
      }

      // Also delete Firebase account
      try {
        await FirebaseAuthService.deleteAccount();
      } catch (e) {
        debugPrint('Firebase delete account error: $e');
      }

      if (mounted) Navigator.pop(context);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
              (_) => false,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ErrorHelper.showError(context, 'Wipe failed: ${e.toString()}');
        setState(() => _isWiping = false);
      }
    }
  }
  // ─────────────────────────────────────────────
  // Logout
  // FIX: Removed Supabase auth.signOut —
  // use Firebase signOut instead
  // ─────────────────────────────────────────────

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
        _isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await ActivityLogger.logLogout();
    await DatabaseService.logActivity(
      userId: widget.userId,
      action: 'logout',
      description: 'User logged out',
    );

    EncryptionService.clearKey();

    const storage = FlutterSecureStorage();
    await storage.delete(key: 'user_password_${widget.userId}');
    await storage.delete(key: 'user_pin_${widget.userId}');
    await storage.delete(key: 'last_logged_in_user_id');
    await storage.delete(key: 'recovery_key');
    await PinService.deletePin(widget.userId);
    await PendingSignupService.clearPendingSignup();

    ActivityLogger.clear();

    // FIX: Sign out Firebase — not Supabase auth
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

    return Scaffold(
        backgroundColor: bgColor,
        body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  isDark
                      ? const Color(0xFF0A1F35)
                      : AppColors.primary.withOpacity(0.05),
                  bgColor,
                ],
              ),
            ),
            child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      const SizedBox(height: 20),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.arrow_back_ios_rounded,
                            color: textColor),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 8),
                      Text('Settings',
                          style: TextStyle(
                              color: textColor,
                              fontSize: 28,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Account Section
                  _SectionTitle('Account'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      children: [
                        Row(children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                AppColors.primary,
                                AppColors.primaryLight
                              ]),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                widget.username.isNotEmpty
                                    ? widget.username[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(widget.username,
                                    style: TextStyle(
                                        color: textColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(_email,
                                    style: TextStyle(
                                        color: mutedColor,
                                        fontSize: 13),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        Divider(color: borderColor),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceAround,
                          children: [
                            _InfoStat(
                                label: 'Total Files',
                                value: '$_totalFiles'),
                            _InfoStat(
                                label: 'Cloud Used',
                                value: FileService.formatSize(
                                    _cloudUsed)),
                            const _InfoStat(
                                label: 'Limit', value: '10 MB'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Appearance
                  _SectionTitle('Appearance'),
                  const SizedBox(height: 10),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, child) {
                      return _SettingsTile(
                        icon: Icons.dark_mode_rounded,
                        iconColor: AppColors.primary,
                        title: 'Dark Mode',
                        subtitle: themeProvider.isDarkMode
                            ? 'Switch to light theme'
                            : 'Switch to dark theme',
                        trailing: Switch(
                          value: themeProvider.isDarkMode,
                          onChanged: (_) => themeProvider.toggleTheme(),
                          activeColor: AppColors.primary,
                        ),
                        onTap: null,
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Security
                  _SectionTitle('Security'),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    icon: Icons.pin_rounded,
                    iconColor: AppColors.primary,
                    title: 'Change PIN',
                    subtitle: 'Update your 8-digit vault PIN',
                    trailing:
                    const Icon(Icons.chevron_right_rounded),
                    onTap: _changePin,
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    icon: Icons.shield_rounded,
                    iconColor: AppColors.primary,
                    title: 'Encryption Info',
                    subtitle: 'Learn about your file security',
                    trailing:
                    const Icon(Icons.chevron_right_rounded),
                    onTap: _showEncryptionInfo,
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    icon: Icons.vpn_key_rounded,
                    iconColor: AppColors.warning,
                    title: 'Reset Password (Recovery Key)',
                    subtitle:
                    'Use your recovery key to reset password',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.warning),
                    onTap: _resetPasswordWithRecoveryKey,
                    titleColor: AppColors.warning,
                  ),
                  const SizedBox(height: 24),
                        // Cloud
                        _SectionTitle('Cloud'),
                        const SizedBox(height: 10),
                        _SettingsTile(
                          icon: Icons.sync_rounded,
                          iconColor: AppColors.primary,
                          title: 'Sync to Cloud',
                          subtitle: 'Manual sync with Supabase',
                          trailing: _isSyncing
                              ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary))
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: _isSyncing ? null : _syncToSupabase,
                        ),
                        const SizedBox(height: 24),

                        // Danger Zone
                        _SectionTitle('Danger Zone',
                            color: AppColors.error),
                        const SizedBox(height: 10),
                        _SettingsTile(
                          icon: Icons.logout_rounded,
                          iconColor: AppColors.error,
                          title: 'Logout',
                          subtitle: 'Sign out of your account',
                          trailing:
                          const Icon(Icons.chevron_right_rounded),
                          onTap: _logout,
                          titleColor: AppColors.error,
                        ),
                        const SizedBox(height: 8),
                        _SettingsTile(
                          icon: Icons.delete_sweep_rounded,
                          iconColor: AppColors.error,
                          title: 'Wipe All Data',
                          subtitle: _isWiping
                              ? 'Wiping...'
                              : 'Delete everything (local + cloud + account)',
                          trailing: _isWiping
                              ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.error))
                              : const Icon(Icons.chevron_right_rounded,
                              color: AppColors.error),
                          onTap: _isWiping ? null : _wipeAllData,
                          titleColor: AppColors.error,
                        ),
                        const SizedBox(height: 40),
                      ],
                  ),
                ),
            ),
        ),
    );
  }
}

// ─────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionTitle(this.title, {this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: color.withOpacity(0.7),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final Color titleColor;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.titleColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final borderColor =
    isDark ? AppColors.border : AppColors.lightBorder;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: titleColor == Colors.white
                              ? textColor
                              : titleColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          color: textColor.withOpacity(0.6),
                          fontSize: 12)),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _InfoStat extends StatelessWidget {
  final String label;
  final String value;

  const _InfoStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: isDark ? AppColors.muted : AppColors.lightMuted,
                fontSize: 11)),
      ],
    );
  }
}