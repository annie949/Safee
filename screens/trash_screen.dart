import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import '../models/file_model.dart';

class TrashScreen extends StatefulWidget {
  final String userId;
  const TrashScreen({super.key, required this.userId});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<FileModel> _trashedFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrash();
    _autoCleanExpired();
  }

  Future<void> _loadTrash() async {
    setState(() => _loading = true);
    final files =
    await DatabaseService.getTrashedFiles(widget.userId);
    if (mounted) {
      setState(() {
        _trashedFiles = files;
        _loading = false;
      });
    }
  }

  // Auto delete files trashed more than 30 days ago
  Future<void> _autoCleanExpired() async {
    final expired =
    await DatabaseService.getExpiredTrashedFiles(widget.userId);
    for (final file in expired) {
      await _permanentDelete(file, silent: true);
    }
  }

  Future<void> _restore(FileModel file) async {
    await DatabaseService.restoreFromTrash(file.id!);
    await DatabaseService.logActivity(
      userId: widget.userId,
      action: 'file_restore',
      description: 'Restored "${file.displayName}" from trash',
    );
    _loadTrash();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${file.displayName}" restored'),
          backgroundColor: AppColors.mint,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _permanentDelete(FileModel file,
      {bool silent = false}) async {
    if (!silent) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Forever',
              style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w800)),
          content: Text(
            'Permanently delete "${file.displayName}"? This cannot be undone.',
            style: const TextStyle(color: AppColors.muted),
          ),
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
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // Delete encrypted file from device
    final localFile = File(file.encryptedPath);
    if (await localFile.exists()) await localFile.delete();

    // Delete from cloud if backed up
    if (file.isCloudBacked && file.cloudPath != null) {
      try {
        await Supabase.instance.client.storage
            .from('vault-files')
            .remove([file.cloudPath!]);
      } catch (_) {}
    }

    // Delete from SQLite
    if (file.id != null) {
      await DatabaseService.deleteFile(file.id!);
    }

    if (!silent) {
      await DatabaseService.logActivity(
        userId: widget.userId,
        action: 'file_delete',
        description:
        'Permanently deleted "${file.displayName}"',
      );
      _loadTrash();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${file.displayName}" deleted forever'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _emptyTrash() async {
    if (_trashedFiles.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_rounded,
              color: AppColors.error, size: 22),
          const SizedBox(width: 8),
          const Text('Empty Trash',
              style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w800)),
        ]),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.error.withOpacity(0.3)),
          ),
          child: Text(
            '⚠️ Permanently delete all ${_trashedFiles.length} file(s) in trash? This cannot be undone.',
            style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                height: 1.5),
          ),
        ),
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
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final file in _trashedFiles) {
      await _permanentDelete(file, silent: true);
    }
    await DatabaseService.logActivity(
      userId: widget.userId,
      action: 'data_wipe',
      description: 'Trash emptied — all files permanently deleted',
    );
    _loadTrash();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trash emptied'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _daysLeft(DateTime trashedAt) {
    final deleteOn = trashedAt.add(const Duration(days: 7));  // ← CHANGED from 30 to 7
    final daysLeft = deleteOn.difference(DateTime.now()).inDays;
    if (daysLeft <= 0) return 'Deletes today';
    if (daysLeft == 1) return 'Deletes tomorrow';
    return 'Deletes in $daysLeft days';
  }

  Color get _categoryColor => AppColors.muted;

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
                    const Icon(Icons.delete_rounded,
                        color: AppColors.error, size: 22),
                    const SizedBox(width: 10),
                    const Text('Trash',
                        style: TextStyle(
                            color: AppColors.soft,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_trashedFiles.isNotEmpty)
                      TextButton.icon(
                        onPressed: _emptyTrash,
                        icon: const Icon(Icons.delete_forever_rounded,
                            color: AppColors.error, size: 18),
                        label: const Text('Empty',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w700)),
                      ),
                    IconButton(
                      onPressed: _loadTrash,
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ),

              // ── Info banner ──────────────────────────────
              if (_trashedFiles.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.warning.withOpacity(0.8),
                        size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Files in trash are permanently deleted after 7 days.',
                        style: TextStyle(
                            color: AppColors.warning.withOpacity(0.9),
                            fontSize: 12),
                      ),
                    ),
                  ]),
                ),

              // ── Trash list ───────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.mint))
                    : _trashedFiles.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: AppColors.muted
                              .withOpacity(0.3),
                          size: 72),
                      const SizedBox(height: 16),
                      Text('Trash is empty',
                          style: TextStyle(
                              color: AppColors.muted
                                  .withOpacity(0.6),
                              fontSize: 16,
                              fontWeight:
                              FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                          'Deleted files will appear here',
                          style: TextStyle(
                              color: AppColors.muted
                                  .withOpacity(0.4),
                              fontSize: 13)),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _trashedFiles.length,
                  itemBuilder: (_, i) {
                    final file = _trashedFiles[i];
                    final color =
                    _fileColor(file.category);
                    return Container(
                      margin: const EdgeInsets.only(
                          bottom: 10),
                      decoration: BoxDecoration(
                        color: AppColors.card
                            .withOpacity(0.6),
                        borderRadius:
                        BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          // File info row
                          Padding(
                            padding:
                            const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: color
                                        .withOpacity(0.15),
                                    borderRadius:
                                    BorderRadius
                                        .circular(12),
                                  ),
                                  child: Icon(
                                      _fileIcon(
                                          file.category),
                                      color: color,
                                      size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                    children: [
                                      Text(
                                        file.displayName,
                                        style: const TextStyle(
                                            color: AppColors
                                                .soft,
                                            fontSize: 14,
                                            fontWeight:
                                            FontWeight
                                                .w600),
                                        overflow:
                                        TextOverflow
                                            .ellipsis,
                                      ),
                                      const SizedBox(
                                          height: 2),
                                      Text(
                                        FileService
                                            .formatSize(
                                            file.sizeBytes),
                                        style: TextStyle(
                                            color: AppColors
                                                .muted
                                                .withOpacity(
                                                0.6),
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Days left warning
                          if (file.trashedAt != null)
                            Container(
                              margin: const EdgeInsets
                                  .fromLTRB(14, 0, 14, 8),
                              padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.error
                                    .withOpacity(0.08),
                                borderRadius:
                                BorderRadius.circular(8),
                              ),
                              child: Row(children: [
                                Icon(
                                    Icons
                                        .timer_outlined,
                                    color: AppColors.error
                                        .withOpacity(0.7),
                                    size: 13),
                                const SizedBox(width: 5),
                                Text(
                                  _daysLeft(
                                      file.trashedAt!),
                                  style: TextStyle(
                                      color: AppColors.error
                                          .withOpacity(0.8),
                                      fontSize: 11,
                                      fontWeight:
                                      FontWeight.w600),
                                ),
                              ]),
                            ),

                          // Action buttons
                          const Divider(
                              color: AppColors.border,
                              height: 1),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _restore(file),
                                  icon: const Icon(
                                      Icons
                                          .restore_rounded,
                                      size: 16),
                                  label: const Text(
                                      'Restore'),
                                  style:
                                  TextButton.styleFrom(
                                    foregroundColor:
                                    AppColors.mint,
                                    padding:
                                    const EdgeInsets
                                        .symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 32,
                                color: AppColors.border,
                              ),
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _permanentDelete(
                                          file),
                                  icon: const Icon(
                                      Icons
                                          .delete_forever_rounded,
                                      size: 16),
                                  label: const Text(
                                      'Delete Forever'),
                                  style:
                                  TextButton.styleFrom(
                                    foregroundColor:
                                    AppColors.error,
                                    padding:
                                    const EdgeInsets
                                        .symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}