import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/file_model.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import 'file_viewer_screen.dart';
import 'share_file_dialog.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/error_helper.dart';
import 'dart:io';
class CategoryScreen extends StatefulWidget {
  final String category;
  final String label;
  final Color color;
  final String userId;

  const CategoryScreen({
    super.key,
    required this.category,
    required this.label,
    required this.color,
    required this.userId,
  });

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<FileModel> _files = [];
  bool _loading = true;
  String _sortBy = 'date_desc';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    final files = await DatabaseService.getFilesByCategory(
        widget.userId, widget.category, _sortBy);
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
      });
    }
  }

  Future<void> _openFile(FileModel file) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileViewerScreen(file: file),
      ),
    );
    if (result == true) _loadFiles();
  }

  Future<void> _shareFile(FileModel file) async {
    await showDialog(
      context: context,
      builder: (_) => ShareFileDialog(file: file),
    );
  }

  Future<void> _deleteFile(FileModel file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete File',
            style: TextStyle(
                color: AppColors.soft,
                fontWeight: FontWeight.w800)),
        content: Text(
            'Delete "${file.displayName}"? This cannot be undone.',
            style: TextStyle(
                color: AppColors.muted.withOpacity(0.8))),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FileService.deleteFile(file);
    _loadFiles();
  }

  Future<void> _renameFile(FileModel file) async {
    final ctrl =
    TextEditingController(text: file.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename File',
            style: TextStyle(
                color: AppColors.soft,
                fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.soft),
          decoration: InputDecoration(
            hintText: 'Enter new name',
            hintStyle: TextStyle(
                color: AppColors.muted.withOpacity(0.4)),
            filled: true,
            fillColor: AppColors.darkBg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: AppColors.mint, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await FileService.renameFile(file, newName);
    _loadFiles();
  }

  // In category_screen.dart, find the _uploadForCategory method
// Replace the entire upload confirmation and deletion part with this:

  Future<void> _uploadForCategory() async {
    FileType fileType;
    List<String>? allowedExtensions;

    switch (widget.category) {
      case 'image':
        fileType = FileType.image;
        break;
      case 'video':
        fileType = FileType.video;
        break;
      case 'audio':
        fileType = FileType.audio;
        break;
      default:
        fileType = FileType.custom;
        allowedExtensions = [
          'pdf', 'doc', 'docx', 'txt',
          'xls', 'xlsx', 'ppt', 'pptx'
        ];
    }

    final picked = await FileService.pickFileOfType(
        fileType: fileType,
        allowedExtensions: allowedExtensions);
    if (picked == null) return;

    String displayName = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final nameCtrl = TextEditingController(text: displayName);
    bool backupToCloud = false;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.category == 'image'
                        ? Icons.image_rounded
                        : widget.category == 'video'
                        ? Icons.videocam_rounded
                        : widget.category == 'audio'
                        ? Icons.audiotrack_rounded
                        : Icons.description_rounded,
                    color: widget.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Upload ${widget.label}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBg : AppColors.lightBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder),
                  ),
                  child: Row(children: [
                    Icon(
                      widget.category == 'image'
                          ? Icons.image_rounded
                          : widget.category == 'video'
                          ? Icons.videocam_rounded
                          : widget.category == 'audio'
                          ? Icons.audiotrack_rounded
                          : Icons.description_rounded,
                      color: widget.color,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(picked.name,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                          Text(FileService.formatSize(picked.size),
                              style: TextStyle(
                                  color: isDark ? AppColors.muted : AppColors.lightMuted,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Text('File Name',
                    style: TextStyle(
                        color: isDark ? AppColors.muted : AppColors.lightMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: isDark ? AppColors.soft : AppColors.lightText),
                  decoration: InputDecoration(
                    hintText: 'Enter file name',
                    filled: true,
                    fillColor: isDark ? AppColors.darkBg : AppColors.lightBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBg : AppColors.lightBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder),
                  ),
                  child: Row(children: [
                    Icon(Icons.cloud_upload_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Backup to Cloud', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Switch(
                      value: backupToCloud,
                      onChanged: (v) => setS(() => backupToCloud = v),
                      activeColor: AppColors.primary,
                    ),
                  ]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  displayName = nameCtrl.text.trim().isEmpty
                      ? picked.name
                      : nameCtrl.text.trim();
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Upload'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    // ASK USER IF THEY WANT TO DELETE ORIGINAL FILE (BEFORE UPLOAD)
    final deleteOriginal = await showDialog<bool>(
      context: context,
      builder: (_) {
        final isDark = Theme.of(_).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: AppColors.warning, size: 24),
              const SizedBox(width: 8),
              const Text('Delete Original File?', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          content: Text(
            'Do you want to delete the original file from your device?',
            style: TextStyle(color: isDark ? AppColors.muted : AppColors.lightMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Keep'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(_, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    ) ?? false;

    double progress = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final isDark = Theme.of(_).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded, color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 20),
              const Text('Encrypting & Uploading', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: isDark ? AppColors.border : AppColors.lightBorder,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text('${(progress * 100).toInt()}% complete',
                  style: TextStyle(color: isDark ? AppColors.muted : AppColors.lightMuted, fontSize: 12)),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );

    try {
      await FileService.uploadFile(
        pickedFile: picked,
        displayName: displayName,
        backupToCloud: backupToCloud,
        userId: widget.userId,
        onProgress: (p) => setState(() => progress = p),
        deleteOriginal: deleteOriginal,  // Pass the user's choice
      );

      await DatabaseService.logActivity(
        userId: widget.userId,
        action: 'file_upload',
        description: 'Uploaded "$displayName" to ${widget.label}',
      );

      if (mounted) {
        Navigator.pop(context);
        _loadFiles();
        ErrorHelper.showSuccess(context, 'File uploaded successfully!');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ErrorHelper.showError(context, e.toString());
      }
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
            colors: [Color(0xFF0C2E4A), AppColors.darkBg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── App bar ───────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () =>
                          Navigator.pop(context),
                      icon: const Icon(
                          Icons.arrow_back_ios_rounded,
                          color: AppColors.muted),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                        widget.color.withOpacity(0.15),
                        borderRadius:
                        BorderRadius.circular(10),
                      ),
                      child: Icon(
                        widget.category == 'image'
                            ? Icons.image_rounded
                            : widget.category == 'video'
                            ? Icons.videocam_rounded
                            : widget.category == 'audio'
                            ? Icons.audiotrack_rounded
                            : Icons
                            .description_rounded,
                        color: widget.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(widget.label,
                        style: const TextStyle(
                            color: AppColors.soft,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.sort_rounded,
                          color: AppColors.muted),
                      color: AppColors.card,
                      onSelected: (v) {
                        setState(() => _sortBy = v);
                        _loadFiles();
                      },
                      itemBuilder: (_) => [
                        _sortItem(
                            'date_desc', 'Newest First'),
                        _sortItem(
                            'date_asc', 'Oldest First'),
                        _sortItem('name_asc', 'Name A-Z'),
                        _sortItem(
                            'name_desc', 'Name Z-A'),
                        _sortItem(
                            'size_desc', 'Largest First'),
                      ],
                    ),
                  ],
                ),
              ),

              // ── File count ────────────────────────────
              if (!_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20),
                  child: Row(children: [
                    Text(
                      '${_files.length} file${_files.length != 1 ? 's' : ''}',
                      style: TextStyle(
                          color:
                          AppColors.muted.withOpacity(0.7),
                          fontSize: 13),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),

              // ── File list ─────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.mint))
                    : _files.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                  padding:
                  const EdgeInsets.symmetric(
                      horizontal: 16),
                  itemCount: _files.length,
                  itemBuilder: (_, i) => _FileItem(
                    file: _files[i],
                    color: widget.color,
                    onTap: () =>
                        _openFile(_files[i]),
                    onShare: () =>
                        _shareFile(_files[i]),
                    onDelete: () =>
                        _deleteFile(_files[i]),
                    onRename: () =>
                        _renameFile(_files[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // ── FAB ──────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadForCategory,
        backgroundColor: widget.color,
        foregroundColor: Colors.white,
        icon: Icon(
          widget.category == 'image'
              ? Icons.add_photo_alternate_rounded
              : widget.category == 'video'
              ? Icons.video_call_rounded
              : widget.category == 'audio'
              ? Icons.audio_file_rounded
              : Icons.upload_file_rounded,
        ),
        label: Text(
          'Add ${widget.label.replaceAll('s', '')}',
          style:
          const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  PopupMenuItem<String> _sortItem(
      String value, String label) =>
      PopupMenuItem(
        value: value,
        child: Text(label,
            style: TextStyle(
                color: _sortBy == value
                    ? AppColors.mint
                    : AppColors.soft,
                fontSize: 13)),
      );

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_open_rounded,
            color: AppColors.muted.withOpacity(0.3),
            size: 64),
        const SizedBox(height: 12),
        Text('No ${widget.label} yet',
            style: TextStyle(
                color: AppColors.muted.withOpacity(0.6),
                fontSize: 15)),
        const SizedBox(height: 6),
        Text('Tap the button below to add',
            style: TextStyle(
                color: AppColors.muted.withOpacity(0.4),
                fontSize: 13)),
      ],
    ),
  );
}

// ── File item widget ─────────────────────────────────────────────
class _FileItem extends StatelessWidget {
  final FileModel file;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _FileItem({
    required this.file,
    required this.color,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                file.category == 'image'
                    ? Icons.image_rounded
                    : file.category == 'video'
                    ? Icons.videocam_rounded
                    : file.category == 'audio'
                    ? Icons.audiotrack_rounded
                    : Icons.description_rounded,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(file.displayName,
                      style: const TextStyle(
                          color: AppColors.soft,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(
                        FileService.formatSize(
                            file.sizeBytes),
                        style: TextStyle(
                            color: AppColors.muted
                                .withOpacity(0.6),
                            fontSize: 12)),
                    if (file.isCloudBacked) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.cloud_done_rounded,
                          color: AppColors.mint
                              .withOpacity(0.7),
                          size: 14),
                    ],
                  ]),
                ],
              ),
            ),

            // ── 3-dot menu with Share, Rename, Delete ──
            PopupMenuButton(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.muted, size: 20),
              color: AppColors.card,
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: onShare,
                  child: const Row(children: [
                    Icon(Icons.share_rounded,
                        color: AppColors.mint, size: 18),
                    SizedBox(width: 10),
                    Text('Share',
                        style: TextStyle(
                            color: AppColors.soft)),
                  ]),
                ),
                PopupMenuItem(
                  onTap: onRename,
                  child: const Row(children: [
                    Icon(Icons.edit_rounded,
                        color: AppColors.mint, size: 18),
                    SizedBox(width: 10),
                    Text('Rename',
                        style: TextStyle(
                            color: AppColors.soft)),
                  ]),
                ),
                PopupMenuItem(
                  onTap: onDelete,
                  child: Row(children: [
                    const Icon(Icons.delete_rounded,
                        color: AppColors.error, size: 18),
                    const SizedBox(width: 10),
                    Text('Delete',
                        style: TextStyle(
                            color: AppColors.error)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}