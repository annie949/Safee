import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';

class LogsScreen extends StatefulWidget {
  final String userId;
  const LogsScreen({super.key, required this.userId});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _allLogs = [];
  bool _loading = true;

  // Tab filter categories
  final _fileActions = [
    'file_upload',
    'file_delete',
    'file_export',
    'file_share'
  ];
  final _securityActions = [
    'login',
    'logout',
    'pin_change',
    'password_change',
    'failed_login'
  ];
  final _systemActions = [
    'app_open',
    'data_wipe',
    'sync',
    'backup'
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadLogs();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final logs =
    await DatabaseService.getActivityLogs(widget.userId, limit: 100);
    if (mounted) {
      setState(() {
        _allLogs = logs;
        _loading = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Logs',
            style: TextStyle(
                color: AppColors.soft, fontWeight: FontWeight.w800)),
        content: const Text(
            'Clear all activity logs? This cannot be undone.',
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await DatabaseService.clearActivityLogs(widget.userId);
    _loadLogs();
  }

  List<Map<String, dynamic>> _filtered(List<String>? actions) {
    if (actions == null) return _allLogs;
    return _allLogs
        .where((l) => actions.contains(l['action'] as String))
        .toList();
  }

  IconData _icon(String action) {
    switch (action) {
      case 'app_open':
        return Icons.lock_open_rounded;
      case 'file_upload':
        return Icons.upload_file_rounded;
      case 'file_delete':
        return Icons.delete_rounded;
      case 'file_export':
        return Icons.download_rounded;
      case 'file_share':
        return Icons.share_rounded;
      case 'password_change':
        return Icons.lock_reset_rounded;
      case 'pin_change':
        return Icons.pin_rounded;
      case 'data_wipe':
        return Icons.delete_sweep_rounded;
      case 'login':
        return Icons.login_rounded;
      case 'logout':
        return Icons.logout_rounded;
      case 'failed_login':
        return Icons.warning_rounded;
      case 'sync':
        return Icons.sync_rounded;
      case 'backup':
        return Icons.cloud_upload_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _color(String action) {
    switch (action) {
      case 'app_open':
      case 'login':
        return AppColors.mint;
      case 'file_upload':
      case 'backup':
      case 'sync':
        return const Color(0xFF2196F3);
      case 'file_delete':
      case 'data_wipe':
      case 'failed_login':
        return AppColors.error;
      case 'file_export':
      case 'file_share':
        return const Color(0xFF9C27B0);
      case 'password_change':
      case 'pin_change':
        return AppColors.warning;
      case 'logout':
        return AppColors.muted;
      default:
        return AppColors.muted;
    }
  }

  String _timeAgo(String isoString) {
    final dt = DateTime.parse(isoString);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _fullTime(String isoString) {
    final dt = DateTime.parse(isoString);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year} $h:$m';
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
            colors: [Color(0xFF0A1F35), AppColors.darkBg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    const Text('Activity Logs',
                        style: TextStyle(
                            color: AppColors.soft,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_allLogs.isNotEmpty)
                      IconButton(
                        onPressed: _clearLogs,
                        icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.muted),
                        tooltip: 'Clear logs',
                      ),
                    IconButton(
                      onPressed: _loadLogs,
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ),

              // ── Tabs ─────────────────────────────────────
              TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.mint,
                indicatorWeight: 2,
                labelColor: AppColors.mint,
                unselectedLabelColor: AppColors.muted,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
                tabs: [
                  _buildTab(Icons.grid_view_rounded, 'All',
                      _allLogs.length),
                  _buildTab(Icons.folder_rounded, 'Files',
                      _filtered(_fileActions).length),
                  _buildTab(Icons.shield_rounded, 'Security',
                      _filtered(_securityActions).length),
                  _buildTab(Icons.settings_rounded, 'System',
                      _filtered(_systemActions).length),
                ],
              ),

              // ── Log lists ────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.mint))
                    : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _LogList(
                      logs: _allLogs,
                      iconFn: _icon,
                      colorFn: _color,
                      timeAgoFn: _timeAgo,
                      fullTimeFn: _fullTime,
                      emptyLabel: 'No activity yet',
                    ),
                    _LogList(
                      logs: _filtered(_fileActions),
                      iconFn: _icon,
                      colorFn: _color,
                      timeAgoFn: _timeAgo,
                      fullTimeFn: _fullTime,
                      emptyLabel: 'No file activity yet',
                    ),
                    _LogList(
                      logs: _filtered(_securityActions),
                      iconFn: _icon,
                      colorFn: _color,
                      timeAgoFn: _timeAgo,
                      fullTimeFn: _fullTime,
                      emptyLabel: 'No security events yet',
                    ),
                    _LogList(
                      logs: _filtered(_systemActions),
                      iconFn: _icon,
                      colorFn: _color,
                      timeAgoFn: _timeAgo,
                      fullTimeFn: _fullTime,
                      emptyLabel: 'No system events yet',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Tab _buildTab(IconData icon, String label, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.mint.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                    color: AppColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Log list widget ─────────────────────────────────────────────
class _LogList extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  final IconData Function(String) iconFn;
  final Color Function(String) colorFn;
  final String Function(String) timeAgoFn;
  final String Function(String) fullTimeFn;
  final String emptyLabel;

  const _LogList({
    required this.logs,
    required this.iconFn,
    required this.colorFn,
    required this.timeAgoFn,
    required this.fullTimeFn,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded,
                color: AppColors.muted.withOpacity(0.3), size: 64),
            const SizedBox(height: 12),
            Text(emptyLabel,
                style: TextStyle(
                    color: AppColors.muted.withOpacity(0.6),
                    fontSize: 15)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {},
      color: AppColors.mint,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: logs.length,
        itemBuilder: (_, i) {
          final log = logs[i];
          final action = log['action'] as String;
          final color = colorFn(action);
          final createdAt = log['created_at'] as String;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                  Icon(iconFn(action), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log['description'] as String,
                        style: const TextStyle(
                            color: AppColors.soft,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.access_time_rounded,
                            color: AppColors.muted.withOpacity(0.5),
                            size: 11),
                        const SizedBox(width: 3),
                        Text(
                          fullTimeFn(createdAt),
                          style: TextStyle(
                              color: AppColors.muted.withOpacity(0.5),
                              fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${timeAgoFn(createdAt)}',
                          style: TextStyle(
                              color: color.withOpacity(0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}