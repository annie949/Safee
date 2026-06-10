import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';
import '../theme/app_theme.dart';
import '../services/file_service.dart';
import '../services/encryption_service.dart';
import '../services/error_helper.dart';

class ShareScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  const ShareScreen(
      {super.key, required this.userId, required this.userEmail});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _sent = [];
  List<Map<String, dynamic>> _received = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _cleanupExpiredShares();
    _loadShares();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
  Future<void> _cleanupExpiredShares() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // Get ALL expired shares (both sent and received)
      final expiredShares = await Supabase.instance.client
          .from('shared_files')
          .select('id, storage_path')
          .lt('expires_at', now);

      for (final share in expiredShares) {
        // Delete from storage bucket
        if (share['storage_path'] != null) {
          try {
            await Supabase.instance.client.storage
                .from('shared-files')
                .remove([share['storage_path']]);
            print('✅ Deleted storage file: ${share['storage_path']}');
          } catch (e) {
            print('Storage delete failed: $e');
          }
        }

        // Delete from database
        await Supabase.instance.client
            .from('shared_files')
            .delete()
            .eq('id', share['id']);
        print('✅ Deleted database record: ${share['id']}');
      }

      if (expiredShares.isNotEmpty) {
        print('✅ Cleaned up ${expiredShares.length} expired shares');
      }
    } catch (e) {
      print('Cleanup failed: $e');
    }
  }
  Future<void> _loadShares() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;

    final sent = await supabase
        .from('shared_files')
        .select()
        .eq('sender_id', widget.userId)
        .order('created_at', ascending: false);

    final received = await supabase
        .from('shared_files')
        .select()
        .eq('recipient_email', widget.userEmail)
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() {
        _sent = List<Map<String, dynamic>>.from(sent);
        _received = List<Map<String, dynamic>>.from(received);
        _loading = false;
      });
    }
  }

  Future<void> _revokeShare(String shareId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Revoke Share',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
            'Recipient will no longer be able to access this file.',
            style: TextStyle()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await Supabase.instance.client
        .from('shared_files')
        .delete()
        .eq('id', shareId);
    _loadShares();
    if (mounted) {
      ErrorHelper.showSuccess(context, 'Share revoked');
    }
  }

  bool _isExpired(String expiresAt) {
    return DateTime.parse(expiresAt).isBefore(DateTime.now());
  }

  String _timeLeft(String expiresAt) {
    final exp = DateTime.parse(expiresAt);
    if (exp.isBefore(DateTime.now())) return 'Expired';
    final diff = exp.difference(DateTime.now());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m left';
    if (diff.inHours < 24) return '${diff.inHours}h left';
    return '${diff.inDays}d left';
  }

  String _timeAgo(String createdAt) {
    final dt = DateTime.parse(createdAt);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _fileColor(String category) {
    switch (category) {
      case 'image':
        return const Color(0xFF4CAF50);
      case 'video':
        return const Color(0xFF2196F3);
      case 'audio':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFFFF9800);
    }
  }

  IconData _fileIcon(String category) {
    switch (category) {
      case 'image':
        return Icons.image_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'audio':
        return Icons.audiotrack_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  Future<Uint8List> _decryptSharedFile(String signedUrl, String shareKey) async {
    final response = await http.get(Uri.parse(signedUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download file');
    }

    final decryptedBytes = EncryptionService.decryptWithKey(
        Uint8List.fromList(response.bodyBytes),
        shareKey
    );

    return decryptedBytes;
  }

  Future<void> _openSharedFile(Map<String, dynamic> share) async {
    // Check if expired
    if (DateTime.parse(share['expires_at']).isBefore(DateTime.now())) {
      ErrorHelper.showError(context, 'This share link has expired.');
      await Supabase.instance.client
          .from('shared_files')
          .delete()
          .eq('id', share['id']);
      _loadShares();
      return;
    }

    // ✅ Mark as viewed (if not already) - FIXED
    if (share['is_viewed'] != true) {
      try {
        // Update database
        await Supabase.instance.client
            .from('shared_files')
            .update({
          'is_viewed': true,
          'viewed_at': DateTime.now().toUtc().toIso8601String(),
        })
            .eq('id', share['id']);

        // ✅ Force refresh UI immediately
        _loadShares();

        print('✅ Marked as viewed: ${share['file_name']}');
      } catch (e) {
        print('Failed to mark as viewed: $e');
      }
    }

    final signedUrl = share['signed_url'] as String;
    final shareKey = share['share_key'] as String;
    final fileName = share['file_name'] as String;
    final mimeType = share['mime_type'] as String;
    final canExport = share['view_only'] != true;

    try {
      final decryptedBytes = await _decryptSharedFile(signedUrl, shareKey);
      final tempDir = await getTemporaryDirectory();
      final ext = mimeType.split('/').last;
      final tempFile = File(p.join(tempDir.path, 'shared_${DateTime.now().millisecondsSinceEpoch}.$ext'));
      await tempFile.writeAsBytes(decryptedBytes);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SharedFileViewer(
            file: tempFile,
            fileName: fileName,
            mimeType: mimeType,
            canExport: canExport,
          ),
        ),
      );
    } catch (e) {
      ErrorHelper.showError(context, 'Failed to open file: $e');
    }
  }

  int _getUnviewedCount() {
    return _received.where((r) =>
    r['is_viewed'] != true && !_isExpired(r['expires_at'])
    ).length;
  }

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
              isDark ? const Color(0xFF0A1F35) : AppColors.primary.withOpacity(0.05),
              bgColor,
            ],
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
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_rounded, color: mutedColor),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 4),
                    Text('Sharing',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(
                      onPressed: _loadShares,
                      icon: Icon(Icons.refresh_rounded, color: mutedColor),
                    ),
                  ],
                ),
              ),

              // Tabs with unviewed badge
              TabBar(
                controller: _tabCtrl,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2,
                labelColor: AppColors.primary,
                unselectedLabelColor: mutedColor,
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.send_rounded, size: 16),
                        const SizedBox(width: 6),
                        const Text('Sent'),
                        if (_sent.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _Badge(count: _sent.length),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.move_to_inbox_rounded, size: 16),
                        const SizedBox(width: 6),
                        const Text('Received'),
                        if (_received.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _Badge(count: _received.length),
                        ],
                        if (_getUnviewedCount() > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_getUnviewedCount()} new',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Content
              Expanded(
                child: _loading
                    ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                    : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    // Sent tab
                    _sent.isEmpty
                        ? _emptyState(
                      Icons.send_rounded,
                      'No shared files',
                      'Files you share will appear here',
                    )
                        : RefreshIndicator(
                      onRefresh: _loadShares,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sent.length,
                        itemBuilder: (_, i) {
                          final s = _sent[i];
                          final expired = _isExpired(s['expires_at']);
                          final color = _fileColor(s['category']);
                          final isViewed = s['is_viewed'] == true;
                          return _SentCard(
                            share: s,
                            expired: expired,
                            color: color,
                            icon: _fileIcon(s['category']),
                            timeLeft: _timeLeft(s['expires_at']),
                            timeAgo: _timeAgo(s['created_at']),
                            isViewed: isViewed,
                            onRevoke: () => _revokeShare(s['id']),
                          );
                        },
                      ),
                    ),

                    // Received tab
                    _received.isEmpty
                        ? _emptyState(
                      Icons.move_to_inbox_rounded,
                      'No files received',
                      'Files shared with you will appear here',
                    )
                        : RefreshIndicator(
                      onRefresh: _loadShares,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _received.length,
                        itemBuilder: (_, i) {
                          final r = _received[i];
                          final expired = _isExpired(r['expires_at']);
                          final color = _fileColor(r['category']);
                          final isViewed = r['is_viewed'] == true;
                          return _ReceivedCard(
                            share: r,
                            expired: expired,
                            color: color,
                            icon: _fileIcon(r['category']),
                            timeLeft: _timeLeft(r['expires_at']),
                            isViewed: isViewed,
                            onTap: expired ? null : () => _openSharedFile(r),
                          );
                        },
                      ),
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

  Widget _emptyState(IconData icon, String title, String subtitle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: mutedColor.withOpacity(0.3), size: 64),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: mutedColor.withOpacity(0.6),
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(color: mutedColor.withOpacity(0.4), fontSize: 13)),
        ],
      ),
    );
  }
}

// Sent card with viewed indicator
class _SentCard extends StatelessWidget {
  final Map<String, dynamic> share;
  final bool expired;
  final Color color;
  final IconData icon;
  final String timeLeft;
  final String timeAgo;
  final bool isViewed;
  final VoidCallback onRevoke;

  const _SentCard({
    required this.share,
    required this.expired,
    required this.color,
    required this.icon,
    required this.timeLeft,
    required this.timeAgo,
    required this.isViewed,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expired ? AppColors.error.withOpacity(0.3) : borderColor,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(share['file_name'],
                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('To: ${share['recipient_email']}',
                    style: TextStyle(color: mutedColor, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            onPressed: onRevoke,
            icon: const Icon(Icons.link_off_rounded, color: AppColors.error, size: 20),
            padding: EdgeInsets.zero,
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _Tag(text: timeLeft, color: expired ? AppColors.error : AppColors.primary),
          const SizedBox(width: 8),
          _Tag(
            text: share['view_only'] == true ? '👁 View Only' : '📤 Can Export',
            color: mutedColor,
          ),
          const Spacer(),
          // ✅ Viewed indicator for sent files
          if (isViewed && !expired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.remove_red_eye_rounded, size: 10, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text('Viewed', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          if (!isViewed && !expired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_rounded, size: 10, color: AppColors.warning),
                  const SizedBox(width: 2),
                  Text('Not viewed', style: TextStyle(color: AppColors.warning, fontSize: 9, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const SizedBox(width: 8),
          Text(timeAgo, style: TextStyle(color: mutedColor.withOpacity(0.4), fontSize: 11)),
        ]),
      ]),
    );
  }
}

// Received card with NEW badge
class _ReceivedCard extends StatelessWidget {
  final Map<String, dynamic> share;
  final bool expired;
  final Color color;
  final IconData icon;
  final String timeLeft;
  final bool isViewed;
  final VoidCallback? onTap;

  const _ReceivedCard({
    required this.share,
    required this.expired,
    required this.color,
    required this.icon,
    required this.timeLeft,
    required this.isViewed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: expired ? cardColor.withOpacity(0.3) : cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: expired ? AppColors.error.withOpacity(0.3) : borderColor,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // ✅ NEW badge position
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(expired ? 0.05 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: expired ? mutedColor : color, size: 20),
                ),
                if (!expired && !isViewed)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          share['file_name'],
                          style: TextStyle(
                            color: expired ? mutedColor : textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // ✅ Viewed checkmark for already viewed
                      if (!expired && isViewed)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('From: ${share['sender_email']}',
                      style: TextStyle(color: mutedColor, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!expired && !isViewed)
              Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 20),
            if (!expired && isViewed)
              Icon(Icons.chevron_right_rounded, color: mutedColor, size: 20),
            if (expired)
              Icon(Icons.lock_clock_rounded, color: AppColors.error, size: 18),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _Tag(text: timeLeft, color: expired ? AppColors.error : AppColors.primary),
            const SizedBox(width: 8),
            _Tag(
              text: share['view_only'] == true ? '👁 View Only' : '📤 Can Export',
              color: mutedColor,
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$count',
          style: const TextStyle(
              color: AppColors.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
    );
  }
}

// Shared file viewer (same as before, no changes needed)
class SharedFileViewer extends StatefulWidget {
  final File file;
  final String fileName;
  final String mimeType;
  final bool canExport;

  const SharedFileViewer({
    super.key,
    required this.file,
    required this.fileName,
    required this.mimeType,
    required this.canExport,
  });

  @override
  State<SharedFileViewer> createState() => _SharedFileViewerState();
}

class _SharedFileViewerState extends State<SharedFileViewer> {
  bool _loading = true;
  String? _error;

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  PlayerState _audioState = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    final mimeType = widget.mimeType;
    final tempFile = widget.file;

    try {
      if (mimeType.startsWith('video/')) {
        _videoController = VideoPlayerController.file(tempFile);
        await _videoController!.initialize();
        _videoController!.addListener(() {
          if (mounted) setState(() {});
        });
        if (mounted) setState(() => _videoInitialized = true);
      } else if (mimeType.startsWith('audio/')) {
        _audioPlayer.onDurationChanged.listen((d) {
          if (mounted) setState(() => _audioDuration = d);
        });
        _audioPlayer.onPositionChanged.listen((pos) {
          if (mounted) setState(() => _audioPosition = pos);
        });
        _audioPlayer.onPlayerStateChanged.listen((s) {
          if (mounted) setState(() => _audioState = s);
        });
        await _audioPlayer.setSourceDeviceFile(tempFile.path);
      } else if (!mimeType.startsWith('image/') && mimeType != 'application/pdf') {
        await OpenFilex.open(tempFile.path);
        if (mounted) Navigator.pop(context);
        return;
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to open file: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  Future<void> _exportFile() async {
    try {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      final ext = widget.mimeType.split('/').last;
      final exportPath = '${downloadsDir.path}/${widget.fileName}.$ext';
      await widget.file.copy(exportPath);
      await OpenFilex.open(exportPath);
      if (mounted) {
        ErrorHelper.showSuccess(context, 'Saved to Downloads');
      }
    } catch (e) {
      if (mounted) {
        ErrorHelper.showError(context, 'Export failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.black.withOpacity(0.7),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.canExport && !_loading && _error == null)
                    IconButton(
                      onPressed: _exportFile,
                      icon: const Icon(Icons.download_rounded, color: AppColors.primary),
                      tooltip: 'Export',
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('Loading file...',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              )
                  : _error != null
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.error),
                      textAlign: TextAlign.center),
                ),
              )
                  : _buildViewer(),
            ),
            if (!widget.canExport)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black.withOpacity(0.7),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.visibility_rounded, color: Colors.white54, size: 16),
                    SizedBox(width: 6),
                    Text('View Only — Export disabled',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    if (widget.mimeType.startsWith('image/')) return _buildImageViewer();
    if (widget.mimeType.startsWith('video/')) return _buildVideoViewer();
    if (widget.mimeType.startsWith('audio/')) return _buildAudioViewer();
    if (widget.mimeType == 'application/pdf') return _buildPdfViewer();
    return const Center(
      child: Text('Cannot preview this file type', style: TextStyle(color: Colors.white54)),
    );
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(child: Image.file(widget.file, fit: BoxFit.contain)),
    );
  }

  Widget _buildVideoViewer() {
    if (!_videoInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return Column(children: [
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.black,
        child: Column(children: [
          VideoProgressIndicator(
            _videoController!,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.primary,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white12,
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              onPressed: () {
                final pos = _videoController!.value.position;
                _videoController!.seekTo(pos - const Duration(seconds: 10));
              },
              icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                if (_videoController!.value.isPlaying) {
                  _videoController!.pause();
                } else {
                  _videoController!.play();
                }
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Icon(
                  _videoController!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () {
                final pos = _videoController!.value.position;
                _videoController!.seekTo(pos + const Duration(seconds: 10));
              },
              icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_formatDuration(_videoController!.value.position),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Text(_formatDuration(_videoController!.value.duration),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ]),
      ),
    ]);
  }

  Widget _buildAudioViewer() {
    final progress = _audioDuration.inMilliseconds > 0
        ? _audioPosition.inMilliseconds / _audioDuration.inMilliseconds
        : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.audiotrack_rounded, color: AppColors.primary, size: 80),
          ),
          const SizedBox(height: 32),
          Text(widget.fileName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SliderTheme(
            data: SliderThemeData(
              thumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white24,
              overlayColor: AppColors.primary.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (v) {
                final seek = Duration(milliseconds: (v * _audioDuration.inMilliseconds).toInt());
                _audioPlayer.seek(seek);
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_formatDuration(_audioPosition),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Text(_formatDuration(_audioDuration),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              onPressed: () => _audioPlayer.seek(_audioPosition - const Duration(seconds: 10)),
              icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () async {
                if (_audioState == PlayerState.playing) {
                  await _audioPlayer.pause();
                } else {
                  await _audioPlayer.resume();
                }
              },
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Icon(
                  _audioState == PlayerState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: () => _audioPlayer.seek(_audioPosition + const Duration(seconds: 10)),
              icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildPdfViewer() {
    OpenFilex.open(widget.file.path);
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary, size: 64),
        SizedBox(height: 16),
        Text('Opening PDF...', style: TextStyle(color: Colors.white54, fontSize: 14)),
      ]),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}