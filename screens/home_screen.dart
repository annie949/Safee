import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import '../services/pin_service.dart';
import '../services/activity_logger.dart';
import '../services/error_helper.dart';
import '../models/file_model.dart';
import 'auth/welcome_screen.dart';
import 'category_screen.dart';
import 'file_viewer_screen.dart';
import 'share_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String userEmail;

  const HomeScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.userEmail,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, int> _storageStats = {};
  Map<String, int> _categoryCounts = {};
  int _cloudUsed = 0;
  int _totalFiles = 0;
  List<FileModel> _recentFiles = [];
  List<FileModel> _allFiles = [];
  List<FileModel> _searchResults = [];
  bool _loading = true;
  bool _isSearching = false;
  final TextEditingController _searchController =
  TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _storageUsed = 0;
  int _storageLimit = 10 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    ActivityLogger.init(widget.userId);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final stats =
    await DatabaseService.getStorageStats(widget.userId);
    final counts =
    await DatabaseService.getCategoryFileCounts(
        widget.userId);
    final cloudUsed =
    await DatabaseService.getCloudStorageUsed(
        widget.userId);
    final totalFiles =
    await DatabaseService.getTotalFileCount(widget.userId);
    final recentFiles = await DatabaseService.getRecentFiles(
        widget.userId,
        limit: 5);
    final allFiles =
    await DatabaseService.getFiles(widget.userId, 'date_desc');
    _storageUsed =
    await DatabaseService.getUserStorageUsed(widget.userId);
    _storageLimit =
    await DatabaseService.getUserStorageLimit(widget.userId);

    if (mounted) {
      setState(() {
        _storageStats = stats;
        _categoryCounts = counts;
        _cloudUsed = cloudUsed;
        _totalFiles = totalFiles;
        _recentFiles = recentFiles;
        _allFiles = allFiles;
        _loading = false;
      });
    }
  }

  void _searchFiles(String query) {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }
    final results = _allFiles
        .where((file) => file.displayName
        .toLowerCase()
        .contains(query.toLowerCase()))
        .toList();
    setState(() {
      _isSearching = true;
      _searchResults = results;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchResults = [];
    });
    _searchFocusNode.unfocus();
  }

  void _onFileSelected(FileModel file) async {
    _clearSearch();
    await ActivityLogger.logFileView(file.displayName);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileViewerScreen(file: file),
      ),
    );
    _loadData();
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          userId: widget.userId,
          username: widget.username,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _navigateToSharing() {
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

  // ─────────────────────────────────────────────
  // Upload File
  // CHANGED: deleteOriginal is always false in
  // uploadFile — we handle deletion manually
  // after upload using _showDeleteOriginalFlow
  // ─────────────────────────────────────────────
  Future<void> _uploadFile() async {
    final picked = await FileService.pickFile();
    if (picked == null) return;

    String displayName =
    picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final nameCtrl =
    TextEditingController(text: displayName);
    bool backupToCloud = false;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final isDark =
              Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark
                ? AppColors.darkCard
                : AppColors.lightCard,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                    AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                      Icons.cloud_upload_rounded,
                      color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                const Text('Upload File',
                    style: TextStyle(
                        fontWeight: FontWeight.w800)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkBg
                        : AppColors.lightBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? AppColors.border
                            : AppColors.lightBorder),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                        AppColors.primary.withOpacity(0.1),
                        borderRadius:
                        BorderRadius.circular(8),
                      ),
                      child: const Icon(
                          Icons.insert_drive_file_rounded,
                          color: AppColors.primary,
                          size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(picked.name,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                  FontWeight.w600),
                              overflow:
                              TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                              FileService.formatSize(
                                  picked.size),
                              style: TextStyle(
                                  color: isDark
                                      ? AppColors.muted
                                      : AppColors.lightMuted,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text('File Name',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(
                      color: isDark
                          ? AppColors.soft
                          : AppColors.lightText),
                  decoration: InputDecoration(
                    hintText: 'Enter file name',
                    filled: true,
                    fillColor: isDark
                        ? AppColors.darkBg
                        : AppColors.lightBg,
                    border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(12)),
                    contentPadding:
                    const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkBg
                        : AppColors.lightBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? AppColors.border
                            : AppColors.lightBorder),
                  ),
                  child: Row(children: [
                    const Icon(Icons.cloud_rounded,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Backup to Cloud',
                          style: TextStyle(
                              fontWeight: FontWeight.w600)),
                    ),
                    Switch(
                      value: backupToCloud,
                      onChanged: (v) =>
                          setS(() => backupToCloud = v),
                      activeColor: AppColors.primary,
                    ),
                  ]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  displayName =
                  nameCtrl.text.trim().isEmpty
                      ? picked.name
                      : nameCtrl.text.trim();
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(12)),
                ),
                child: const Text('Upload'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    // Ask if user wants to delete original
    final wantsToDelete = await showDialog<bool>(
      context: context,
      builder: (_) {
        final isDark =
            Theme.of(_).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor:
          isDark ? AppColors.darkCard : AppColors.lightCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  color: AppColors.warning, size: 24),
              const SizedBox(width: 8),
              const Text('Delete Original File?',
                  style:
                  TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          content: Text(
            'After importing, do you want to delete the original file from your device?',
            style: TextStyle(
                color: isDark
                    ? AppColors.muted
                    : AppColors.lightMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Keep Original'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(_, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete After Import'),
            ),
          ],
        );
      },
    ) ??
        false;

    double progress = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final isDark =
            Theme.of(_).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor:
          isDark ? AppColors.darkCard : AppColors.lightCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          content: StatefulBuilder(
            builder: (ctx, setS) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: AppColors.primary, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('Encrypting & Uploading',
                    style: TextStyle(
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: isDark
                        ? AppColors.border
                        : AppColors.lightBorder,
                    valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                    '${(progress * 100).toInt()}% complete',
                    style: TextStyle(
                        color: isDark
                            ? AppColors.muted
                            : AppColors.lightMuted,
                        fontSize: 12)),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );

    try {
      // FIX: Always pass deleteOriginal: false
      // We handle deletion manually after upload
      await FileService.uploadFile(
        pickedFile: picked,
        displayName: displayName,
        backupToCloud: backupToCloud,
        userId: widget.userId,
        onProgress: (p) => setState(() => progress = p),
        deleteOriginal: false,
      );

      await ActivityLogger.logFileUpload(
          displayName, picked.size, backupToCloud);

      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        _loadData();

        // Show delete flow if user chose to delete
        if (wantsToDelete) {
          await _showDeleteOriginalFlow(
              picked.path, displayName);
        } else {
          ErrorHelper.showSuccess(
              context, 'File imported successfully!');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ErrorHelper.showError(context, e.toString());
      }
    }
  }

  // ─────────────────────────────────────────────
  // Delete Original Flow
  // Shows step by step guide for user to
  // manually delete original file safely
  // ─────────────────────────────────────────────
  Future<void> _showDeleteOriginalFlow(
      String? filePath, String displayName) async {
    if (!mounted) return;

    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    // Step 1: Try automatic deletion first
    bool autoDeleted = false;
    if (filePath != null && filePath.isNotEmpty) {
      autoDeleted =
      await FileService.requestOfficialDelete(
          filePath, context);
    }

    if (!mounted) return;

    // Step 2: If auto deletion worked — show success
    if (autoDeleted) {
      ErrorHelper.showSuccess(
          context,
          'File imported and original deleted successfully!');
      return;
    }

    // Step 3: Auto deletion failed — show manual guide
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor:
        isDark ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'File Imported Successfully!',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_rounded,
                      color: AppColors.primary, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"$displayName" is safely stored in your vault.',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'To delete the original from your device:',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _StepTile(
                number: '1',
                text: 'Open your Gallery or Files app'),
            _StepTile(
                number: '2',
                text: 'Find "$displayName"'),
            _StepTile(
                number: '3',
                text:
                'Long press → tap Delete → confirm'),
            if (filePath != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                      AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded,
                        color: AppColors.warning, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        filePath,
                        style: const TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(_),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.card : AppColors.lightCard;
    final textColor = isDark ? AppColors.soft : AppColors.lightText;
    final mutedColor = isDark ? AppColors.muted : AppColors.lightMuted;
    final borderColor =
    isDark ? AppColors.border : AppColors.lightBorder;

    final totalLocal =
    _storageStats.values.fold(0, (sum, v) => sum + v);

    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              isDark
                  ? const Color(0xFF0A1F35)
                  : AppColors.primary.withOpacity(0.03),
              bgColor,
            ],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary))
              : RefreshIndicator(
            onRefresh: _loadData,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics:
              const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // Welcome Header
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient:
                          const LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryLight
                              ]),
                          borderRadius:
                          BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary
                                  .withOpacity(0.3),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: const Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                            size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back,',
                              style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                  fontWeight:
                                  FontWeight.w500),
                            ),
                            Text(
                              widget.username,
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: 20,
                                  fontWeight:
                                  FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius:
                          BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed:
                          _navigateToSettings,
                          icon: Icon(
                              Icons.settings_rounded,
                              color: mutedColor,
                              size: 22),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius:
                          BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: _navigateToSharing,
                          icon: Icon(
                              Icons.share_rounded,
                              color: AppColors.primary,
                              size: 22),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Search Bar
                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius:
                          BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withOpacity(0.03),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: (value) {
                            _searchFiles(value);
                            setState(() {});
                          },
                          style: TextStyle(
                              color: textColor,
                              fontSize: 15),
                          decoration: InputDecoration(
                            hintText:
                            'Search your files...',
                            hintStyle: TextStyle(
                                color: mutedColor
                                    .withOpacity(0.5),
                                fontSize: 14),
                            prefixIcon: Icon(
                                Icons.search_rounded,
                                color: mutedColor,
                                size: 20),
                            suffixIcon: _searchController
                                .text.isNotEmpty
                                ? IconButton(
                              icon: Icon(
                                  Icons
                                      .close_rounded,
                                  color: mutedColor,
                                  size: 20),
                              onPressed:
                              _clearSearch,
                            )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(
                                  20),
                              borderSide:
                              BorderSide.none,
                            ),
                            contentPadding:
                            const EdgeInsets
                                .symmetric(
                                vertical: 16,
                                horizontal: 16),
                          ),
                        ),
                      ),

                      // Search Suggestions
                      if (_isSearching &&
                          _searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(
                              top: 8),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius:
                            BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withOpacity(0.1),
                                blurRadius: 8,
                                offset:
                                const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics:
                            const NeverScrollableScrollPhysics(),
                            itemCount:
                            _searchResults.length > 5
                                ? 5
                                : _searchResults
                                .length,
                            separatorBuilder: (_, __) =>
                                Divider(
                                    height: 1,
                                    color: borderColor),
                            itemBuilder: (_, index) {
                              final file =
                              _searchResults[index];
                              final fileColor =
                              _getFileColor(
                                  file.category);
                              final fileIcon =
                              _getFileIcon(
                                  file.category);
                              return ListTile(
                                leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration:
                                  BoxDecoration(
                                    color: fileColor
                                        .withOpacity(
                                        0.15),
                                    borderRadius:
                                    BorderRadius
                                        .circular(10),
                                  ),
                                  child: Icon(fileIcon,
                                      color: fileColor,
                                      size: 18),
                                ),
                                title: Text(
                                  file.displayName,
                                  style: TextStyle(
                                      color: textColor,
                                      fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow
                                      .ellipsis,
                                ),
                                subtitle: Text(
                                  FileService.formatSize(
                                      file.sizeBytes),
                                  style: TextStyle(
                                      color: mutedColor,
                                      fontSize: 11),
                                ),
                                trailing: Icon(
                                    Icons
                                        .chevron_right_rounded,
                                    color: mutedColor,
                                    size: 18),
                                onTap: () =>
                                    _onFileSelected(file),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Stats Row
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.folder_rounded,
                          label: 'Files',
                          value: '$_totalFiles',
                          color:
                          const Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.storage_rounded,
                          label: 'Storage',
                          value: FileService.formatSize(
                              totalLocal),
                          color:
                          const Color(0xFF2196F3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.cloud_rounded,
                          label: 'Cloud Backup',
                          value: FileService.formatSize(
                              _cloudUsed),
                          color:
                          const Color(0xFF9C27B0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Storage Usage Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cardColor,
                          isDark
                              ? AppColors.darkBg
                              : AppColors.lightBg
                        ],
                      ),
                      borderRadius:
                      BorderRadius.circular(20),
                      border:
                      Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding:
                              const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary
                                    .withOpacity(0.1),
                                borderRadius:
                                BorderRadius.circular(
                                    12),
                              ),
                              child: const Icon(
                                  Icons
                                      .cloud_queue_rounded,
                                  color: AppColors.primary,
                                  size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                  'Storage Usage',
                                  style: TextStyle(
                                      fontWeight:
                                      FontWeight
                                          .w700)),
                            ),
                            Text(
                              '${FileService.formatSize(_storageUsed)} / ${FileService.formatSize(_storageLimit)}',
                              style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                  fontWeight:
                                  FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius:
                          BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _storageUsed /
                                _storageLimit,
                            backgroundColor: isDark
                                ? AppColors.border
                                : AppColors.lightBorder,
                            valueColor:
                            AlwaysStoppedAnimation(
                              _storageUsed >
                                  _storageLimit * 0.8
                                  ? AppColors.error
                                  : AppColors.primary,
                            ),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '⚠️ Videos are not backed up to save space. Compress images before uploading.',
                          style: TextStyle(
                              color: mutedColor
                                  .withOpacity(0.6),
                              fontSize: 10),
                        ),
                      ],
                    ),
                  ),

                  // Categories Section
                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Categories',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Categories Grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics:
                    const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                    children: [
                      _CategoryCard(
                        icon: Icons.image_rounded,
                        label: 'Images',
                        category: 'image',
                        color: const Color(0xFF4CAF50),
                        iconColor:
                        const Color(0xFF4CAF50),
                        count: _categoryCounts['image'] ??
                            0,
                        userId: widget.userId,
                      ),
                      _CategoryCard(
                        icon: Icons.videocam_rounded,
                        label: 'Videos',
                        category: 'video',
                        color: const Color(0xFF2196F3),
                        iconColor:
                        const Color(0xFF2196F3),
                        count: _categoryCounts['video'] ??
                            0,
                        userId: widget.userId,
                      ),
                      _CategoryCard(
                        icon: Icons.audiotrack_rounded,
                        label: 'Audios',
                        category: 'audio',
                        color: const Color(0xFF9C27B0),
                        iconColor:
                        const Color(0xFF9C27B0),
                        count: _categoryCounts['audio'] ??
                            0,
                        userId: widget.userId,
                      ),
                      _CategoryCard(
                        icon: Icons.description_rounded,
                        label: 'Documents',
                        category: 'document',
                        color: const Color(0xFFFF9800),
                        iconColor:
                        const Color(0xFFFF9800),
                        count:
                        _categoryCounts['document'] ??
                            0,
                        userId: widget.userId,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Recent Files
                  if (!_isSearching &&
                      _recentFiles.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: 12),
                      child: Text(
                        'Recently Added',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ..._recentFiles.map((file) =>
                        _RecentFileCard(
                          file: file,
                          onTap: () async {
                            await ActivityLogger
                                .logFileView(
                                file.displayName);
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    FileViewerScreen(
                                        file: file),
                              ),
                            );
                            _loadData();
                          },
                        )),
                  ],

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadFile,
        backgroundColor: AppColors.primary,
        elevation: 4,
        child: const Icon(Icons.add_rounded,
            color: Colors.white, size: 28),
      ),
    );
  }

  Color _getFileColor(String category) {
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

  IconData _getFileIcon(String category) {
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
}

// ─────────────────────────────────────────────
// Step Tile Widget for delete guide
// ─────────────────────────────────────────────
class _StepTile extends StatelessWidget {
  final String number;
  final String text;
  const _StepTile({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Stat Card
// ─────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
    isDark ? AppColors.card : AppColors.lightCard;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: isDark
                      ? AppColors.muted
                      : AppColors.lightMuted,
                  fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Category Card
// ─────────────────────────────────────────────
class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String category;
  final Color color;
  final Color iconColor;
  final int count;
  final String userId;

  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.category,
    required this.color,
    required this.iconColor,
    required this.count,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
    isDark ? AppColors.card : AppColors.lightCard;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryScreen(
            category: category,
            label: label,
            color: iconColor,
            userId: userId,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(
                    color: isDark
                        ? AppColors.soft
                        : AppColors.lightText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
                count == 1 ? '1 file' : '$count files',
                style: TextStyle(
                    color: isDark
                        ? AppColors.muted
                        : AppColors.lightMuted,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Recent File Card
// ─────────────────────────────────────────────
class _RecentFileCard extends StatelessWidget {
  final FileModel file;
  final VoidCallback onTap;

  const _RecentFileCard(
      {required this.file, required this.onTap});

  Color get _color {
    switch (file.category) {
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

  IconData get _icon {
    switch (file.category) {
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60)
      return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
    isDark ? AppColors.card : AppColors.lightCard;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_icon, color: _color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayName,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.soft
                          : AppColors.lightText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        FileService.formatSize(
                            file.sizeBytes),
                        style: TextStyle(
                          color: isDark
                              ? AppColors.muted
                              : AppColors.lightMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: AppColors.muted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(file.createdAt),
                        style: TextStyle(
                          color: isDark
                              ? AppColors.muted
                              : AppColors.lightMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: isDark
                    ? AppColors.muted
                    : AppColors.lightMuted,
                size: 18),
          ],
        ),
      ),
    );
  }
}