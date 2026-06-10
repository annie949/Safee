import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import '../models/file_model.dart';
import 'file_viewer_screen.dart';
import 'share_file_dialog.dart';

class FilesScreen extends StatefulWidget {
  final String userId;
  const FilesScreen({super.key, required this.userId});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _categories = [
    'all', 'image', 'video', 'audio', 'document'
  ];
  final _labels = ['All', 'Images', 'Videos', 'Audios', 'Docs'];
  final _icons = [
    Icons.grid_view_rounded,
    Icons.image_rounded,
    Icons.videocam_rounded,
    Icons.audiotrack_rounded,
    Icons.description_rounded,
  ];
  final _colors = [
    AppColors.mint,
    const Color(0xFF4CAF50),
    const Color(0xFF2196F3),
    const Color(0xFF9C27B0),
    const Color(0xFFFF9800),
  ];

  Map<String, List<FileModel>> _filesMap = {};
  bool _loading = true;
  String _sortBy = 'date_desc';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _loadFiles();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    final map = <String, List<FileModel>>{};
    for (final cat in _categories) {
      if (cat == 'all') {
        map[cat] = await DatabaseService.getFiles(
            widget.userId, _sortBy);
      } else {
        map[cat] = await DatabaseService.getFilesByCategory(
            widget.userId, cat, _sortBy);
      }
    }
    if (mounted) {
      setState(() {
        _filesMap = map;
        _loading = false;
      });
    }
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
        content: Text('Delete "${file.displayName}"?',
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
    await DatabaseService.logActivity(
      userId: widget.userId,
      action: 'file_delete',
      description: 'Deleted "${file.displayName}"',
    );
    _loadFiles();
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
              // ── Header ──────────────────────────────
              Padding(
                padding:
                const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    const Text('My Files',
                        style: TextStyle(
                            color: AppColors.soft,
                            fontSize: 22,
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

              // ── Tabs ────────────────────────────────
              TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.mint,
                indicatorWeight: 2,
                labelColor: AppColors.mint,
                unselectedLabelColor: AppColors.muted,
                labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
                tabs: List.generate(
                  5,
                      (i) => Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_icons[i], size: 16),
                        const SizedBox(width: 4),
                        Text(_labels[i]),
                      ],
                    ),
                  ),
                ),
              ),

              // ── File lists ───────────────────────────
              Expanded(
                child: _loading
                    ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.mint))
                    : TabBarView(
                  controller: _tabCtrl,
                  children: List.generate(5, (i) {
                    final files =
                        _filesMap[_categories[i]] ??
                            [];
                    if (files.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize:
                          MainAxisSize.min,
                          children: [
                            Icon(
                                Icons
                                    .folder_open_rounded,
                                color: AppColors.muted
                                    .withOpacity(0.3),
                                size: 64),
                            const SizedBox(height: 12),
                            Text(
                                'No ${_labels[i]} yet',
                                style: TextStyle(
                                    color: AppColors
                                        .muted
                                        .withOpacity(
                                        0.6),
                                    fontSize: 15)),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: _loadFiles,
                      color: AppColors.mint,
                      child: ListView.builder(
                        padding:
                        const EdgeInsets.all(16),
                        itemCount: files.length,
                        itemBuilder: (_, j) {
                          final file = files[j];
                          final catIndex =
                          _categories.indexOf(
                              file.category);
                          final color = _colors[
                          catIndex == -1
                              ? 0
                              : catIndex];
                          return GestureDetector(
                            onTap: () async {
                              final result =
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      FileViewerScreen(
                                          file: file),
                                ),
                              );
                              if (result == true)
                                _loadFiles();
                            },
                            child: Container(
                              margin:
                              const EdgeInsets.only(
                                  bottom: 8),
                              padding:
                              const EdgeInsets.all(
                                  14),
                              decoration: BoxDecoration(
                                color: AppColors.card
                                    .withOpacity(0.6),
                                borderRadius:
                                BorderRadius
                                    .circular(14),
                                border: Border.all(
                                    color:
                                    AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration:
                                    BoxDecoration(
                                      color: color
                                          .withOpacity(
                                          0.15),
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                          12),
                                    ),
                                    child: Icon(
                                      file.category ==
                                          'image'
                                          ? Icons
                                          .image_rounded
                                          : file.category ==
                                          'video'
                                          ? Icons
                                          .videocam_rounded
                                          : file.category ==
                                          'audio'
                                          ? Icons
                                          .audiotrack_rounded
                                          : Icons
                                          .description_rounded,
                                      color: color,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(
                                      width: 12),
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
                                                fontSize:
                                                14,
                                                fontWeight:
                                                FontWeight
                                                    .w600),
                                            overflow:
                                            TextOverflow
                                                .ellipsis),
                                        const SizedBox(
                                            height: 2),
                                        Row(children: [
                                          Text(
                                            FileService
                                                .formatSize(
                                                file.sizeBytes),
                                            style: TextStyle(
                                                color: AppColors
                                                    .muted
                                                    .withOpacity(
                                                    0.6),
                                                fontSize:
                                                12),
                                          ),
                                          if (file
                                              .isCloudBacked) ...[
                                            const SizedBox(
                                                width: 6),
                                            Icon(
                                                Icons
                                                    .cloud_done_rounded,
                                                color: AppColors
                                                    .mint
                                                    .withOpacity(
                                                    0.7),
                                                size:
                                                14),
                                          ],
                                        ]),
                                      ],
                                    ),
                                  ),

                                  // ── 3-dot menu ──
                                  PopupMenuButton(
                                    icon: const Icon(
                                        Icons
                                            .more_vert_rounded,
                                        color:
                                        AppColors
                                            .muted,
                                        size: 20),
                                    color:
                                    AppColors.card,
                                    itemBuilder: (_) =>
                                    [
                                      PopupMenuItem(
                                        onTap: () =>
                                            _shareFile(
                                                file),
                                        child: const Row(
                                            children: [
                                              Icon(
                                                  Icons
                                                      .share_rounded,
                                                  color: AppColors
                                                      .mint,
                                                  size: 18),
                                              SizedBox(
                                                  width: 10),
                                              Text('Share',
                                                  style: TextStyle(
                                                      color: AppColors
                                                          .soft)),
                                            ]),
                                      ),
                                      PopupMenuItem(
                                        onTap: () =>
                                            _deleteFile(
                                                file),
                                        child: Row(
                                            children: [
                                              const Icon(
                                                  Icons
                                                      .delete_rounded,
                                                  color: AppColors
                                                      .error,
                                                  size: 18),
                                              const SizedBox(
                                                  width: 10),
                                              Text('Delete',
                                                  style: TextStyle(
                                                      color: AppColors
                                                          .error)),
                                            ]),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
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
}