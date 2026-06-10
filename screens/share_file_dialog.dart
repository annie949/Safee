import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme/app_theme.dart';
import '../models/file_model.dart';
import '../services/encryption_service.dart';
import '../services/error_helper.dart';
import '../services/file_service.dart';
import '../services/firebase_auth_service.dart';
import 'package:flutter/services.dart';

class ShareFileDialog extends StatefulWidget {
  final FileModel file;
  const ShareFileDialog({super.key, required this.file});

  @override
  State<ShareFileDialog> createState() => _ShareFileDialogState();
}

class _ShareFileDialogState extends State<ShareFileDialog> {
  final _emailCtrl = TextEditingController();
  String _expiry = '1';
  bool _viewOnly = true;
  bool _loading = false;
  bool _verifying = false;
  String? _error;
  String? _verifiedEmail;

  // ─────────────────────────────────────────────
  // FIX: Load sender info from Firebase +
  // secure storage instead of Supabase auth
  // ─────────────────────────────────────────────
  String _senderEmail = '';
  String _senderId = '';

  final List<String> _expiryHours = ['1', '2', '4', '8', '12', '24'];

  @override
  void initState() {
    super.initState();
    _loadSenderInfo();
  }

  Future<void> _loadSenderInfo() async {
    // Get email from Firebase
    final firebaseUser = FirebaseAuthService.currentUser;
    _senderEmail = firebaseUser?.email ?? '';

    // Get userId from secure storage
    const storage = FlutterSecureStorage();
    _senderId =
        await storage.read(key: 'last_logged_in_user_id') ?? '';
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  DateTime _getExpiryDate() {
    final nowUtc = DateTime.now().toUtc();
    return nowUtc.add(Duration(hours: int.parse(_expiry)));
  }

  // ─────────────────────────────────────────────
  // Verify Recipient
  // FIX: Removed Supabase auth.currentUser check
  // Use _senderEmail loaded from Firebase
  // ─────────────────────────────────────────────

  Future<void> _verifyRecipient() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    setState(() => _error = null);

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }

    // FIX: Use Firebase email instead of Supabase auth
    if (email == _senderEmail.toLowerCase()) {
      setState(() => _error = 'You cannot share a file with yourself.');
      return;
    }

    setState(() {
      _verifying = true;
      _verifiedEmail = null;
    });

    try {
      final result = await Supabase.instance.client
          .from('user_keys')
          .select('email')
          .eq('email', email)
          .maybeSingle();

      if (result != null) {
        setState(() {
          _verifiedEmail = email;
          _verifying = false;
        });
        if (mounted) {
          ErrorHelper.showSuccess(context, 'Recipient verified!');
        }
      } else {
        setState(() => _verifying = false);
        _showInviteDialog(email);
      }
    } catch (e) {
      setState(() {
        _error = 'Verification failed: ${e.toString()}';
        _verifying = false;
      });
    }
  }

  void _showInviteDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkCard
            : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.person_off_rounded,
                color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            const Text('User Not Found'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$email" is not registered on Safe Locker.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.email_rounded,
                      color: AppColors.primary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Would you like to invite them to install Safe Locker?',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(_);
              _sendInvite(email);
            },
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Send Invite'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Future<void> _sendInvite(String email) async {
    final appLink = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.safelocker.app'
        : 'https://apps.apple.com/app/idXXXXXXXXX';

    // FIX: Use Firebase email
    final senderName = _senderEmail.isNotEmpty
        ? _senderEmail.split('@').first
        : 'Someone';

    final inviteMessage = '''
📱 Safe Locker Invitation

$senderName wants to share a secure file with you!

Download Safe Locker:
$appLink

What is Safe Locker?
• 🔒 AES-256 Military-grade encryption
• ☁️ Secure cloud backup
• 📁 Share files safely
• 👁 View-only permissions

After installing, ask $senderName to share the file again.

Stay secure! 🔒
    ''';

    await Clipboard.setData(ClipboardData(text: inviteMessage));

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkCard
            : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 24),
            SizedBox(width: 8),
            Text('Invite Ready!'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Invitation copied to clipboard.'),
            SizedBox(height: 12),
            Text(
              'Choose how to send it:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, 'close'),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(_, 'share'),
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('Share via App'),
          ),
        ],
      ),
    );

    if (action == 'share') {
      await Share.share(inviteMessage);
      if (mounted) {
        ErrorHelper.showSuccess(context, 'Invite sent successfully!');
      }
    } else {
      if (mounted) {
        ErrorHelper.showSuccess(
            context, 'Invite copied to clipboard!');
      }
    }
  }

  // ─────────────────────────────────────────────
  // Share File
  // FIX: Use _senderId and _senderEmail
  // instead of Supabase auth.currentUser
  // ─────────────────────────────────────────────

  Future<void> _share() async {
    // FIX: Validate sender info loaded correctly
    if (_senderId.isEmpty || _senderEmail.isEmpty) {
      setState(() => _error = 'Session expired. Please login again.');
      return;
    }

    final email = _verifiedEmail!;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Step 1: Read and decrypt original file
      final encryptedBytes =
      await File(widget.file.encryptedPath).readAsBytes();
      final decryptedBytes =
      EncryptionService.decryptFile(encryptedBytes);

      // Step 2: Generate unique share key
      final shareKey = _generateShareKey();

      // Step 3: Re-encrypt with share key
      final reEncryptedBytes =
      EncryptionService.encryptWithKey(decryptedBytes, shareKey);

      // Step 4: Upload to Supabase Storage
      final uniqueId =
      DateTime.now().millisecondsSinceEpoch.toString();
      final storageFileName =
          'shared_${_senderId}_$uniqueId.enc';
      const bucketName = 'shared-files';

      final storage = Supabase.instance.client.storage;

      await storage.from(bucketName).uploadBinary(
        storageFileName,
        reEncryptedBytes,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );

      // Step 5: Generate signed URL
      final expiresIn = Duration(hours: int.parse(_expiry));
      final signedUrl = await storage
          .from(bucketName)
          .createSignedUrl(storageFileName, expiresIn.inSeconds);

      // Step 6: Store metadata
      // FIX: Use _senderId and _senderEmail
      final shareResult = await Supabase.instance.client
          .from('shared_files')
          .insert({
        'sender_id': _senderId,
        'sender_email': _senderEmail,
        'recipient_email': email,
        'file_name': widget.file.displayName,
        'signed_url': signedUrl,
        'storage_path': storageFileName,
        'share_key': shareKey,
        'mime_type': widget.file.mimeType,
        'category': widget.file.category,
        'size_bytes': widget.file.sizeBytes,
        'view_only': _viewOnly,
        'expires_at': _getExpiryDate().toIso8601String(),
        'is_viewed': false,
      })
          .select('id')
          .single();

      final shareId = shareResult['id'] as String;

      // Step 7: Create notification
      await Supabase.instance.client.from('notifications').insert({
        'recipient_email': email,
        'sender_email': _senderEmail,
        'share_id': shareId,
        'file_name': widget.file.displayName,
        'message':
        '$_senderEmail shared "${widget.file.displayName}" with you',
        'is_read': false,
      });

      // Step 8: Schedule cleanup
      _scheduleCleanup(storageFileName, shareId);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'File shared with $email (expires in $_expiry hour${_expiry != '1' ? 's' : ''})'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to share: ${e.toString()}';
        _loading = false;
      });
    }
  }

  String _generateShareKey() {
    final random = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(Iterable.generate(
        32, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  void _scheduleCleanup(String storagePath, String shareId) {
    final expiryDate = _getExpiryDate();
    final now = DateTime.now().toUtc();
    final delay = expiryDate.difference(now);

    if (delay.isNegative) {
      _cleanupNow(storagePath, shareId);
      return;
    }

    Future.delayed(delay, () async {
      await _cleanupNow(storagePath, shareId);
    });
  }

  Future<void> _cleanupNow(
      String storagePath, String shareId) async {
    try {
      await Supabase.instance.client.storage
          .from('shared-files')
          .remove([storagePath]);

      await Supabase.instance.client
          .from('shared_files')
          .delete()
          .eq('id', shareId);

      debugPrint('Cleaned up expired share: $storagePath');
    } catch (e) {
      debugPrint('Cleanup failed: $e');
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

    return Dialog(
      backgroundColor: cardColor,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.share_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Share File',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text(widget.file.displayName,
                        style:
                        TextStyle(color: mutedColor, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded,
                    color: mutedColor, size: 20),
                padding: EdgeInsets.zero,
              ),
            ]),
            const SizedBox(height: 16),

            // Error display
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _error = null),
                      child: const Icon(Icons.close,
                          color: AppColors.error, size: 16),
                    ),
                  ],
                ),
              ),

            // Verified badge
            if (_verifiedEmail != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.verified_user_rounded,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('$_verifiedEmail ✓ Verified',
                        style: const TextStyle(
                            color: AppColors.primary, fontSize: 12)),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _verifiedEmail = null;
                      _emailCtrl.clear();
                      _error = null;
                    }),
                    child: Icon(Icons.edit_rounded,
                        color: mutedColor, size: 14),
                  ),
                ]),
              ),

            // Recipient email field
            if (_verifiedEmail == null) ...[
              Text('Recipient Email',
                  style: TextStyle(
                      color: mutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: textColor, fontSize: 14),
                    onSubmitted: (_) => _verifyRecipient(),
                    decoration: InputDecoration(
                      hintText: 'recipient@example.com',
                      hintStyle: TextStyle(
                          color: mutedColor.withOpacity(0.4)),
                      prefixIcon: Icon(Icons.email_outlined,
                          color: mutedColor, size: 18),
                      filled: true,
                      fillColor: bgColor,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                          BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                          BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed:
                    _verifying ? null : _verifyRecipient,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      AppColors.primary.withOpacity(0.15),
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      side: const BorderSide(
                          color: AppColors.primary),
                    ),
                    child: _verifying
                        ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary))
                        : const Text('Verify',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
            ],

            // Expiry time selector
            Text('Link Expires After',
                style: TextStyle(
                    color: mutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _expiry,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down, color: mutedColor),
                  dropdownColor: cardColor,
                  style: TextStyle(color: textColor, fontSize: 14),
                  items: _expiryHours.map((hour) {
                    return DropdownMenuItem(
                      value: hour,
                      child: Text(
                          '$hour hour${hour != '1' ? 's' : ''}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null)
                      setState(() => _expiry = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // View only toggle
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Row(children: [
                const Icon(Icons.visibility_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('View Only',
                          style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(
                          _viewOnly
                              ? 'Recipient can only view'
                              : 'Recipient can view and export',
                          style: TextStyle(
                              color: mutedColor, fontSize: 11)),
                    ],
                  ),
                ),
                Switch(
                  value: _viewOnly,
                  onChanged: (v) => setState(() => _viewOnly = v),
                  activeColor: AppColors.primary,
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // Share button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed:
                (_loading || _verifiedEmail == null) ? null : _share,
                icon: _loading
                    ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_loading ? 'Sharing...' : 'Share File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                  AppColors.primary.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}