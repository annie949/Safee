import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import 'auth/welcome_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _requesting = false;

  Future<void> _grantAccess() async {
    setState(() => _requesting = true);

    // Request all media/storage permissions.
    // Android 13+ uses granular media permissions (photos/videos/audio).
    // Android ≤12 uses the single READ_EXTERNAL_STORAGE.
    // manageExternalStorage is needed to save files to Downloads.
    // Permissions that are not applicable on a given Android version
    // are simply ignored by permission_handler — safe to request all.
    final results = await [
      Permission.photos,
      Permission.videos,
      Permission.audio,
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();

    if (!mounted) return;

    final anyGranted = results.values.any(
      (s) =>
          s == PermissionStatus.granted || s == PermissionStatus.limited,
    );

    if (!anyGranted) {
      setState(() => _requesting = false);
      _showDeniedDialog();
      return;
    }

    const storage = FlutterSecureStorage();
    await storage.write(key: 'onboarding_done', value: 'true');

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  void _showDeniedDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Permissions Required',
            style: TextStyle(
                color: AppColors.soft, fontWeight: FontWeight.w800)),
        content: Text(
          'Safe Locker needs access to your photos, videos, audio, and '
          'files to encrypt and store them securely.\n\n'
          'Without these permissions the app cannot function. '
          'Please grant access in Settings to continue.',
          style: TextStyle(
              color: AppColors.muted.withOpacity(0.9), height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now',
                style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.mint,
              foregroundColor: AppColors.dark,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _exit() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Exit App',
            style: TextStyle(
                color: AppColors.soft, fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to exit?',
            style:
                TextStyle(color: AppColors.muted.withOpacity(0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              SystemNavigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  void _showPrivacy() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.80,
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text('Privacy Policy',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.soft)),
          Text('Last updated: March 2026',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.muted.withOpacity(0.6))),
          Divider(height: 24, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _PolicyItem('1. Data We Collect',
                        'We collect your email, username, and encrypted files. All files are encrypted with AES-256. We never access your file contents.'),
                    _PolicyItem('2. How We Use Your Data',
                        'Your data is used solely to provide Safe Locker services. We never sell or share your data with third parties.'),
                    _PolicyItem('3. Encryption',
                        'All files are encrypted using AES-256. Your password is never stored in plain text. Only you can decrypt your files.'),
                    _PolicyItem('4. Cloud Storage',
                        'Files you choose to back up are stored encrypted on Supabase servers. You can delete them at any time.'),
                    _PolicyItem('5. Your Rights',
                        'You can delete your account and all data using the Data Wipe feature in Settings. This action is permanent.'),
                    SizedBox(height: 24),
                  ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mint,
                  foregroundColor: AppColors.dark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Got it',
                    style:
                        TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Container(
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const Spacer(),

              // Logo
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.mint, AppColors.teal]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.mint.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: const Icon(Icons.lock_rounded,
                    size: 44, color: AppColors.dark),
              ),
              const SizedBox(height: 24),
              const Text('Safe Locker',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.soft)),
              const SizedBox(height: 6),
              Text('Your personal encrypted vault.',
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.muted.withOpacity(0.8))),
              const SizedBox(height: 44),

              // Feature rows
              const _Feature(Icons.lock_outline_rounded,
                  'AES-256 Encryption',
                  'Military-grade protection for all your files'),
              const SizedBox(height: 12),
              const _Feature(Icons.cloud_done_rounded,
                  'Secure Cloud Backup',
                  'Your files safely stored and synced'),
              const SizedBox(height: 12),
              const _Feature(Icons.share_rounded, 'Safe Sharing',
                  'Share files only with trusted users'),

              const Spacer(),

              // Permission notice
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.mint.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.mint.withOpacity(0.2)),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Icon(Icons.folder_open_rounded,
                      color: AppColors.mint, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tapping "Grant Access" will ask permission to access '
                      'your photos, videos, audio, and files so Safe Locker '
                      'can encrypt and protect them.',
                      style: TextStyle(
                          color: AppColors.muted.withOpacity(0.85),
                          fontSize: 12,
                          height: 1.5),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // Privacy link
              GestureDetector(
                onTap: _showPrivacy,
                child: Text(
                  'By continuing you agree to our Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.mint.withOpacity(0.8),
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.mint.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Grant Access button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _requesting ? null : _grantAccess,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mint,
                    foregroundColor: AppColors.dark,
                    disabledBackgroundColor:
                        AppColors.mint.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _requesting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.dark))
                      : const Text('Grant Access & Continue',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),

              // Exit button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: _requesting ? null : _exit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                        color: AppColors.error.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Exit',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Feature row ─────────────────────────────────────────────────────
class _Feature extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _Feature(this.icon, this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.mint.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.mint, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.soft,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              Text(subtitle,
                  style: TextStyle(
                      color: AppColors.muted.withOpacity(0.7),
                      fontSize: 12)),
            ])),
      ]),
    );
  }
}

// ── Privacy policy item ─────────────────────────────────────────────
class _PolicyItem extends StatelessWidget {
  final String title, content;
  const _PolicyItem(this.title, this.content);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.soft)),
        const SizedBox(height: 6),
        Text(content,
            style: TextStyle(
                fontSize: 13,
                color: AppColors.muted.withOpacity(0.85),
                height: 1.6)),
      ]),
    );
  }
}
