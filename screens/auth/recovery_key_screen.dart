import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../services/encryption_service.dart';
import 'login_screen.dart';

class RecoveryKeyScreen extends StatefulWidget {
  final bool isNew;
  final String? password;

  const RecoveryKeyScreen({
    super.key,
    this.isNew = true,
    this.password,
  });

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  late String _key;

  bool _confirmed = false;
  bool _copied = false;
  bool _saved = false;
  bool _loading = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _key = _generateKey();
    _saveRecoveryKeySecure();
  }

  // ---------------- KEY GENERATION ----------------
  String _generateKey() {
    final random = Random.secure();
    final bytes = List.generate(32, (_) => random.nextInt(256));

    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    final groups = <String>[];
    for (int i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4));
    }

    return groups.join('-');
  }

  Future<void> _saveRecoveryKeySecure() async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'recovery_key', value: _key);
  }

  // ---------------- COPY ----------------
  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _key));

    if (!mounted) return;

    setState(() => _copied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recovery key copied'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  // ---------------- SAVE FILE ----------------
  Future<void> _saveToFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/recovery_key_${DateTime.now().millisecondsSinceEpoch}.txt',
      );

      await file.writeAsString(
        "RECOVERY KEY\n\n$_key\n\nKeep safe.",
      );

      if (!mounted) return;

      setState(() => _saved = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved successfully'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ---------------- FIXED SAFE SUPABASE CHECK ----------------
  Future<Map<String, dynamic>?> _getUser(String email) async {
    try {
      final supabase = Supabase.instance.client;

      final res = await supabase
          .from('users')
          .select('id')
          .eq('email', email.trim().toLowerCase())
          .maybeSingle();

      return res;
    } catch (_) {
      return null;
    }
  }

  // ---------------- MAIN FLOW ----------------
  Future<void> _proceed() async {
    if (_loading) return;

    if (!_confirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm recovery key'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!widget.isNew) return;

      final password = widget.password;
      if (password == null || password.isEmpty) {
        throw Exception("Password missing");
      }

      final user = FirebaseAuth.instance.currentUser;

      if (user == null || user.email == null) {
        throw Exception("Session expired");
      }

      final email = user.email!.trim().toLowerCase();

      // Supabase check (optional safety only)
      final supabaseUser = await _getUser(email);

      if (supabaseUser == null) {
        // IMPORTANT: we DO NOT hard fail anymore
        debugPrint("Supabase user not found, continuing anyway...");
      }

      // Generate encryption keys
      await EncryptionService.generateAndStoreKeys(
        password: password,
        recoveryKey: _key,
        email: email,
      );

      // Sign out cleanly
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
      isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),

              const Icon(Icons.key, size: 60, color: AppColors.primary),

              const SizedBox(height: 20),

              const Text(
                "Recovery Key",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              SelectableText(
                _key,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _copyToClipboard,
                      child: Text(_copied ? "Copied" : "Copy"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saveToFile,
                      child: Text(_saved ? "Saved" : "Save"),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              CheckboxListTile(
                value: _confirmed,
                onChanged: (v) =>
                    setState(() => _confirmed = v ?? false),
                title: const Text("I saved my recovery key"),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _proceed,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text("Continue"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}