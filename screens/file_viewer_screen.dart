import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';
import '../theme/app_theme.dart';
import '../models/file_model.dart';
import '../services/file_service.dart';
import 'share_file_dialog.dart';
import 'dart:io';
import 'package:photo_manager/photo_manager.dart';

class FileViewerScreen extends StatefulWidget {
  final FileModel file;

  const FileViewerScreen({super.key, required this.file});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  File? _tempFile;
  bool _loading = true;
  String? _error;

  // Video
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  // Audio
  final AudioPlayer _audioPlayer = AudioPlayer();
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  PlayerState _audioState = PlayerState.stopped;

  // Image
  int _imageRotation = 0;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final temp = await FileService.decryptToTemp(widget.file);
      if (!mounted) return;
      setState(() => _tempFile = temp);

      final mime = widget.file.mimeType;

      if (mime.startsWith('video/')) {
        _videoController = VideoPlayerController.file(temp);
        await _videoController!.initialize();
        _videoController!.addListener(() {
          if (mounted) setState(() {});
        });
        if (mounted) setState(() => _videoInitialized = true);
      } else if (mime.startsWith('audio/')) {
        _audioPlayer.onDurationChanged.listen((d) {
          if (mounted) setState(() => _audioDuration = d);
        });
        _audioPlayer.onPositionChanged.listen((p) {
          if (mounted) setState(() => _audioPosition = p);
        });
        _audioPlayer.onPlayerStateChanged.listen((s) {
          if (mounted) setState(() => _audioState = s);
        });
        await _audioPlayer.setSourceDeviceFile(temp.path);
      } else if (!mime.startsWith('image/') &&
          mime != 'application/pdf') {
        await OpenFilex.open(temp.path);
        if (mounted) Navigator.pop(context);
        return;
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to decrypt file: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer.dispose();
    if (_tempFile != null) {
      FileService.deleteTempFile(_tempFile!);
    }
    super.dispose();
  }

  Future<void> _share() async {
    await showDialog(
      context: context,
      builder: (_) => ShareFileDialog(file: widget.file),
    );
  }

  Future<void> _export() async {
    if (_tempFile == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Export File',
            style: TextStyle(
                color: AppColors.soft,
                fontWeight: FontWeight.w800)),
        content: const Text(
          'Export will save a decrypted copy. Delete from vault after export?',
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep in Vault',
                style: TextStyle(color: AppColors.mint)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Delete from Vault'),
          ),
        ],
      ),
    );
    if (confirm == null) return;

    try {
      final isImage = widget.file.mimeType.startsWith('image/');
      final isVideo = widget.file.mimeType.startsWith('video/');

      String savedPath;

      if (isImage || isVideo) {
        // For images/videos, save to Pictures or Movies folder (appears in gallery)
        final directory = isImage
            ? Directory('/storage/emulated/0/Pictures/SafeLocker')
            : Directory('/storage/emulated/0/Movies/SafeLocker');

        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        final ext = widget.file.mimeType.split('/').last;
        final fileName = '${widget.file.displayName}.$ext';
        savedPath = '${directory.path}/$fileName';
        await _tempFile!.copy(savedPath);

        // Notify Android MediaStore to scan the file (so it appears in gallery)
        if (Platform.isAndroid) {
          try {
            await PhotoManager.editor.saveImageWithPath(
              savedPath,
              title: widget.file.displayName,
            );
          } catch (e) {
            print('MediaStore scan error: $e');
          }
        }
      } else {
        // For documents, save to Downloads
        final downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
        final ext = widget.file.mimeType.split('/').last;
        savedPath = '${downloadsDir.path}/${widget.file.displayName}.$ext';
        await _tempFile!.copy(savedPath);
      }

      if (confirm) {
        await FileService.deleteFile(widget.file);
        if (mounted) Navigator.pop(context, true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File exported to ${isImage || isVideo ? (isImage ? 'Pictures' : 'Movies') : 'Downloads'}'),
            backgroundColor: AppColors.mint,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
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
          'Delete "${widget.file.displayName}"?',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FileService.deleteFile(widget.file);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              color: Colors.black.withOpacity(0.7),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      widget.file.displayName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.file.mimeType
                      .startsWith('image/'))
                    IconButton(
                      onPressed: () => setState(() =>
                      _imageRotation =
                          (_imageRotation + 90) % 360),
                      icon: const Icon(
                          Icons.rotate_right_rounded,
                          color: Colors.white),
                    ),
                ],
              ),
            ),

            // ── Content area ─────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                        color: AppColors.mint),
                    SizedBox(height: 16),
                    Text('Decrypting file...',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13)),
                  ],
                ),
              )
                  : _error != null
                  ? Center(
                child: Padding(
                  padding:
                  const EdgeInsets.all(24),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: AppColors.error),
                      textAlign:
                      TextAlign.center),
                ),
              )
                  : _buildViewer(),
            ),

            // ── Bottom bar ───────────────────────────────
            if (!_loading && _error == null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                color: Colors.black.withOpacity(0.7),
                child: Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
                  children: [
                    _BottomAction(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      color: AppColors.mint,
                      onTap: _share,
                    ),
                    _BottomAction(
                      icon: Icons.upload_file_rounded,
                      label: 'Export',
                      onTap: _export,
                    ),
                    _BottomAction(
                      icon: Icons.delete_rounded,
                      label: 'Delete',
                      color: AppColors.error,
                      onTap: _delete,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    final mime = widget.file.mimeType;
    if (mime.startsWith('image/')) return _buildImageViewer();
    if (mime.startsWith('video/')) return _buildVideoViewer();
    if (mime.startsWith('audio/')) return _buildAudioViewer();
    if (mime == 'application/pdf') return _buildPdfViewer();
    return const Center(
      child: Text('Cannot preview this file type',
          style: TextStyle(color: Colors.white54)),
    );
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: RotatedBox(
          quarterTurns: _imageRotation ~/ 90,
          child: Image.file(_tempFile!, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildVideoViewer() {
    if (!_videoInitialized) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppColors.mint));
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio:
              _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          color: Colors.black,
          child: Column(
            children: [
              VideoProgressIndicator(
                _videoController!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: AppColors.mint,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      final pos = _videoController!
                          .value.position;
                      _videoController!.seekTo(pos -
                          const Duration(seconds: 10));
                    },
                    icon: const Icon(
                        Icons.replay_10_rounded,
                        color: Colors.white,
                        size: 28),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      if (_videoController!
                          .value.isPlaying) {
                        _videoController!.pause();
                      } else {
                        _videoController!.play();
                      }
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppColors.mint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _videoController!.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: AppColors.dark,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {
                      final pos = _videoController!
                          .value.position;
                      _videoController!.seekTo(pos +
                          const Duration(seconds: 10));
                    },
                    icon: const Icon(
                        Icons.forward_10_rounded,
                        color: Colors.white,
                        size: 28),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(
                        _videoController!.value.position),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12),
                  ),
                  Text(
                    _formatDuration(
                        _videoController!.value.duration),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAudioViewer() {
    final progress = _audioDuration.inMilliseconds > 0
        ? _audioPosition.inMilliseconds /
        _audioDuration.inMilliseconds
        : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.audiotrack_rounded,
                  color: AppColors.mint, size: 80),
            ),
            const SizedBox(height: 32),
            Text(
              widget.file.displayName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SliderTheme(
              data: SliderThemeData(
                thumbColor: AppColors.mint,
                activeTrackColor: AppColors.mint,
                inactiveTrackColor: Colors.white24,
                overlayColor:
                AppColors.mint.withOpacity(0.2),
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8),
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (v) {
                  final seek = Duration(
                      milliseconds: (v *
                          _audioDuration.inMilliseconds)
                          .toInt());
                  _audioPlayer.seek(seek);
                },
              ),
            ),
            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_audioPosition),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12)),
                Text(_formatDuration(_audioDuration),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _audioPlayer.seek(
                      _audioPosition -
                          const Duration(seconds: 10)),
                  icon: const Icon(Icons.replay_10_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () async {
                    if (_audioState ==
                        PlayerState.playing) {
                      await _audioPlayer.pause();
                    } else {
                      await _audioPlayer.resume();
                    }
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AppColors.mint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _audioState == PlayerState.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: AppColors.dark,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () => _audioPlayer.seek(
                      _audioPosition +
                          const Duration(seconds: 10)),
                  icon: const Icon(
                      Icons.forward_10_rounded,
                      color: Colors.white,
                      size: 28),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (_tempFile != null) {
      OpenFilex.open(_tempFile!.path);
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf_rounded,
              color: AppColors.mint, size: 64),
          SizedBox(height: 16),
          Text('Opening PDF...',
              style: TextStyle(
                  color: Colors.white54, fontSize: 14)),
          SizedBox(height: 8),
          Text('File opened in external viewer',
              style: TextStyle(
                  color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m =
    d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s =
    d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Bottom action button ──────────────────────────────────────────
class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}