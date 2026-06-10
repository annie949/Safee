import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'share_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final String userEmail;
  final String userId;
  final VoidCallback? onNotificationsRead;

  const NotificationsScreen({
    super.key,
    required this.userEmail,
    required this.userId,
    this.onNotificationsRead,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loading = true);
    try {
      final result = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('recipient_email', widget.userEmail)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(result);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_email', widget.userEmail)
        .eq('is_read', false);
    widget.onNotificationsRead?.call();
    _loadNotifications();
  }

  Future<void> _markRead(String notifId) async {
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notifId);
  }

  Future<void> _openShare(Map<String, dynamic> notif) async {
    // Mark as read
    if (notif['is_read'] != true) {
      await _markRead(notif['id'] as String);
      widget.onNotificationsRead?.call();
    }

    if (!mounted) return;

    // Navigate to the received tab of ShareScreen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareScreen(
          userId: widget.userId,
          userEmail: widget.userEmail,
        ),
      ),
    );
  }

  Future<void> _deleteNotification(String id) async {
    await Supabase.instance.client
        .from('notifications')
        .delete()
        .eq('id', id);
    _loadNotifications();
    widget.onNotificationsRead?.call();
  }

  String _timeAgo(String createdAt) {
    final dt = DateTime.parse(createdAt);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  int get _unreadCount =>
      _notifications.where((n) => n['is_read'] != true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF0A1F35), AppColors.darkBg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.mint.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.notifications_rounded,
                          color: AppColors.mint, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('Notifications',
                        style: TextStyle(
                            color: AppColors.soft,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_unreadCount > 0)
                      TextButton(
                        onPressed: _markAllRead,
                        child: const Text('Mark all read',
                            style: TextStyle(
                                color: AppColors.mint, fontSize: 12)),
                      ),
                    IconButton(
                      onPressed: _loadNotifications,
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ),

              // Unread count
              if (_unreadCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.mint.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_unreadCount unread',
                          style: const TextStyle(
                              color: AppColors.mint,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),

              // List
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.mint))
                    : _notifications.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_none_rounded,
                                    color:
                                        AppColors.muted.withOpacity(0.3),
                                    size: 64),
                                const SizedBox(height: 12),
                                Text(
                                  'No notifications yet',
                                  style: TextStyle(
                                      color:
                                          AppColors.muted.withOpacity(0.6),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'You\'ll be notified when someone shares a file with you',
                                  style: TextStyle(
                                      color:
                                          AppColors.muted.withOpacity(0.4),
                                      fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadNotifications,
                            color: AppColors.mint,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _notifications.length,
                              itemBuilder: (_, i) {
                                final n = _notifications[i];
                                final isUnread = n['is_read'] != true;
                                return Dismissible(
                                  key: Key(n['id'] as String),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(
                                        right: 20),
                                    margin: const EdgeInsets.only(
                                        bottom: 10),
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.error.withOpacity(0.2),
                                      borderRadius:
                                          BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.delete_rounded,
                                        color: AppColors.error),
                                  ),
                                  onDismissed: (_) =>
                                      _deleteNotification(n['id'] as String),
                                  child: GestureDetector(
                                    onTap: () => _openShare(n),
                                    child: Container(
                                      margin: const EdgeInsets.only(
                                          bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: isUnread
                                            ? AppColors.mint
                                                .withOpacity(0.08)
                                            : AppColors.card
                                                .withOpacity(0.4),
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isUnread
                                              ? AppColors.mint
                                                  .withOpacity(0.3)
                                              : AppColors.border,
                                        ),
                                      ),
                                      child: Row(children: [
                                        // Icon
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: AppColors.mint
                                                .withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Stack(
                                            children: [
                                              const Center(
                                                child: Icon(
                                                    Icons.share_rounded,
                                                    color: AppColors.mint,
                                                    size: 20),
                                              ),
                                              if (isUnread)
                                                Positioned(
                                                  right: 6,
                                                  top: 6,
                                                  child: Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: AppColors.mint,
                                                      shape:
                                                          BoxShape.circle,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Content
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                n['message'] as String,
                                                style: TextStyle(
                                                    color: isUnread
                                                        ? AppColors.soft
                                                        : AppColors.muted,
                                                    fontSize: 13,
                                                    fontWeight: isUnread
                                                        ? FontWeight.w600
                                                        : FontWeight.w400),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.mint
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(4),
                                                  ),
                                                  child: const Text(
                                                      'Tap to view file',
                                                      style: TextStyle(
                                                          color:
                                                              AppColors.mint,
                                                          fontSize: 10)),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  _timeAgo(n['created_at']
                                                      as String),
                                                  style: TextStyle(
                                                      color: AppColors.muted
                                                          .withOpacity(0.4),
                                                      fontSize: 11),
                                                ),
                                              ]),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                            Icons.chevron_right_rounded,
                                            color: AppColors.muted,
                                            size: 18),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
