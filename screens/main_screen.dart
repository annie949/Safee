import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/firebase_auth_service.dart';
import 'home_screen.dart';
import 'files_screen.dart';
import 'logs_screen.dart';
import 'trash_screen.dart';
import 'share_screen.dart';
import 'notifications_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  String? _userId;
  String? _userEmail;
  String? _username;
  int _trashCount = 0;
  int _notifCount = 0;
  Timer? _cleanupTimer;
  RealtimeChannel? _notifChannel;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _cleanupExpiredShares();
    _cleanupTimer = Timer.periodic(
        const Duration(hours: 1), (_) => _cleanupExpiredShares());
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Load User
  // FIX: Use Firebase + secure storage
  // instead of Supabase auth.currentUser
  // ─────────────────────────────────────────────

  Future<void> _loadUser() async {
    try {
      const storage = FlutterSecureStorage();

      // FIX: Get userId from secure storage
      // — saved during login
      final userId =
      await storage.read(key: 'last_logged_in_user_id');

      // FIX: Get email from Firebase current user
      final firebaseUser = FirebaseAuthService.currentUser;
      final email = firebaseUser?.email ?? '';

      if (userId == null || userId.isEmpty) {
        debugPrint('No userId in secure storage');
        if (mounted) setState(() {});
        return;
      }

      // Get username from Supabase users table by email
      String username = 'User';
      try {
        final userRes = await Supabase.instance.client
            .from('users')
            .select('email')
            .eq('id', userId)
            .maybeSingle();

        if (userRes != null) {
          // Derive username from email
          username = email.isNotEmpty
              ? email.split('@').first
              : 'User';
        }
      } catch (e) {
        debugPrint('Error fetching username: $e');
        username = email.isNotEmpty ? email.split('@').first : 'User';
      }

      if (mounted) {
        setState(() {
          _userId = userId;
          _userEmail = email;
          _username = username;
        });
      }

      await DatabaseService.logActivity(
        userId: userId,
        action: 'app_open',
        description: 'Vault opened',
      );

      _loadTrashCount();
      _loadNotifCount();
      _subscribeToNotifications();
    } catch (e) {
      debugPrint('Error loading user: $e');
    }
  }

  Future<void> _loadTrashCount() async {
    if (_userId == null) return;
    final count = await DatabaseService.getTrashCount(_userId!);
    if (mounted) setState(() => _trashCount = count);
  }

  Future<void> _cleanupExpiredShares() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      final expiredShares = await Supabase.instance.client
          .from('shared_files')
          .select('id, storage_path')
          .lt('expires_at', now);

      for (final share in expiredShares) {
        if (share['storage_path'] != null) {
          await Supabase.instance.client.storage
              .from('shared-files')
              .remove([share['storage_path']]);
        }
        await Supabase.instance.client
            .from('shared_files')
            .delete()
            .eq('id', share['id']);
      }

      if (expiredShares.isNotEmpty) {
        debugPrint('Cleaned up ${expiredShares.length} expired shares');
      }
    } catch (e) {
      debugPrint('Cleanup failed: $e');
    }
  }

  Future<void> _loadNotifCount() async {
    if (_userEmail == null || _userEmail!.isEmpty) return;
    try {
      final result = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('recipient_email', _userEmail!)
          .eq('is_read', false);
      final count = (result as List).length;
      if (mounted) setState(() => _notifCount = count);
    } catch (_) {}
  }

  void _subscribeToNotifications() {
    if (_userEmail == null || _userEmail!.isEmpty) return;

    _notifChannel = Supabase.instance.client
        .channel('notifications:${_userEmail!}')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_email',
        value: _userEmail!,
      ),
      callback: (payload) {
        if (mounted) setState(() => _notifCount++);
        _showNotificationBanner(payload.newRecord);
      },
    )
        .subscribe();
  }

  void _showNotificationBanner(Map<String, dynamic> record) {
    final message = record['message'] as String? ??
        'New file shared with you';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.share_rounded,
              color: AppColors.dark, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.dark,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        backgroundColor: AppColors.mint,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          textColor: AppColors.dark,
          onPressed: () => setState(() => _currentIndex = 4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Show spinner while loading user
    // but with a timeout fallback
    if (_userId == null) {
      return const Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: CircularProgressIndicator(
              color: AppColors.mint),
        ),
      );
    }

    final screens = [
      HomeScreen(userId: _userId!, username: _username ?? 'User', userEmail: _userEmail ?? '',),
      FilesScreen(userId: _userId!),
      LogsScreen(userId: _userId!),
      TrashScreen(userId: _userId!),
      NotificationsScreen(
        userEmail: _userEmail!,
        userId: _userId!,
        onNotificationsRead: () => _loadNotifCount(),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Vault',
                  active: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _NavItem(
                  icon: Icons.folder_rounded,
                  label: 'Files',
                  active: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _NavItem(
                  icon: Icons.history_rounded,
                  label: 'Logs',
                  active: _currentIndex == 2,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
                _NavItem(
                  icon: Icons.delete_rounded,
                  label: 'Trash',
                  active: _currentIndex == 3,
                  badge: _trashCount,
                  onTap: () {
                    setState(() => _currentIndex = 3);
                    _loadTrashCount();
                  },
                ),
                _NavItem(
                  icon: Icons.notifications_rounded,
                  label: 'Inbox',
                  active: _currentIndex == 4,
                  badge: _notifCount,
                  onTap: () {
                    setState(() => _currentIndex = 4);
                    _loadNotifCount();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.mint.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: active ? AppColors.mint : AppColors.muted,
                  size: 24,
                ),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.mint : AppColors.muted,
                fontSize: 11,
                fontWeight:
                active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}