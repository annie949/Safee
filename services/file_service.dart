import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../models/file_model.dart';
import '../services/database_service.dart';
import '../services/encryption_service.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter/foundation.dart';

class FileService {
  static const int maxCloudBytes = 200 * 1024 * 1024;
  static AssetEntity? _lastPickedAsset;
  static String? _originalFilePath;
  static String? _originalFileName;

  // ── Native MediaStore channel ─────────────────────────────
  static const _mediaChannel =
  MethodChannel('com.example.safelocker_app/media');

  // ── Pick any file ────────────────────────────────────────
  static Future<PlatformFile?> pickFile() async {
    _lastPickedAsset = null;
    _originalFilePath = null;
    _originalFileName = null;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;

    _originalFileName = picked.name;
    _originalFilePath = picked.path;

    debugPrint('Picked: ${picked.name}');
    debugPrint('Original path: ${picked.path}');

    return picked;
  }

  // ── Pick file of specific type ───────────────────────────
  static Future<PlatformFile?> pickFileOfType({
    required FileType fileType,
    List<String>? allowedExtensions,
  }) async {
    _lastPickedAsset = null;
    _originalFilePath = null;
    _originalFileName = null;

    final result = await FilePicker.platform.pickFiles(
      type: fileType,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    _originalFileName = picked.name;
    _originalFilePath = picked.path;
    debugPrint('Picked: ${picked.name}');
    return picked;
  }

  // ── Get stored original file name ────────────────────────
  static String? get originalFileName => _originalFileName;

  // ── Open file directly using Flutter's open_filex ────────────
  static Future<String> openOriginalFileInGalleryWithPath(
      String filePath) async {
    try {
      debugPrint('Opening file: $filePath');

      // Convert file:// URL to actual path
      String actualPath = filePath;
      if (filePath.startsWith('file://')) {
        actualPath = filePath.substring(7); // Remove 'file://' prefix
      }

      debugPrint('Actual path: $actualPath');

      // Open file directly using open_filex
      final status = await OpenFilex.open(actualPath);

      debugPrint('Open file status: ${status.type}');

      if (status.type == ResultType.done) {
        return "opened";
      } else {
        return "failed";
      }
    } catch (e) {
      debugPrint('Open file error: $e');
      return 'failed';
    }
  }

  // ── Request delete via Android system dialog ─────────────
  // Returns: "deleted", "cancelled", "not_found", "failed"
  // ✅ FIXED: Now sends filePath instead of fileName
  static Future<String> requestOfficialDelete(
      String filePath, dynamic context) async {
    try {
      debugPrint('Requesting delete for: $filePath');
      final result = await _mediaChannel
          .invokeMethod<String>(
        'deleteFile',
        {'filePath': filePath},  // ✅ Changed: fileName -> filePath
      );
      debugPrint('Delete result: $result');
      return result ?? 'failed';
    } catch (e) {
      debugPrint('Delete request error: $e');
      return 'failed';
    }
  }

  // ── Get category from mime type ──────────────────────────
  static String getCategory(
      String mimeType, String? fileName) {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    if (fileName != null) {
      final ext = fileName.toLowerCase();
      if (ext.endsWith('.mp3') ||
          ext.endsWith('.wav') ||
          ext.endsWith('.aac') ||
          ext.endsWith('.flac') ||
          ext.endsWith('.m4a') ||
          ext.endsWith('.ogg') ||
          ext.endsWith('.opus')) return 'audio';
      if (ext.endsWith('.mp4') ||
          ext.endsWith('.mov') ||
          ext.endsWith('.avi') ||
          ext.endsWith('.mkv') ||
          ext.endsWith('.webm')) return 'video';
      if (ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.png') ||
          ext.endsWith('.gif') ||
          ext.endsWith('.webp')) return 'image';
    }
    return 'document';
  }

  // ── Compress file (images only) ──────────────────────────
  static Future<Uint8List> compressFile(
      Uint8List bytes, String mimeType) async {
    if (mimeType.startsWith('image/')) {
      try {
        final compressed =
        await FlutterImageCompress.compressWithList(
          bytes,
          minHeight: 1024,
          minWidth: 1024,
          quality: 70,
        );
        debugPrint(
            'Compressed: ${bytes.length} -> '
                '${compressed?.length ?? 0} bytes');
        return compressed ?? bytes;
      } catch (e) {
        debugPrint('Compression failed: $e');
        return bytes;
      }
    }
    return bytes;
  }

  // ── Upload file with encryption ──────────────────────────
  static Future<FileModel> uploadFile({
    required PlatformFile pickedFile,
    required String displayName,
    required bool backupToCloud,
    required String userId,
    required Function(double) onProgress,
    required bool deleteOriginal,
  }) async {
    onProgress(0.1);
    Uint8List fileBytes;
    if (pickedFile.bytes != null) {
      fileBytes = pickedFile.bytes!;
    } else if (pickedFile.path != null) {
      fileBytes =
      await File(pickedFile.path!).readAsBytes();
    } else {
      throw Exception('Cannot read file');
    }

    onProgress(0.15);
    final mimeType = pickedFile.extension != null
        ? lookupMimeType(
        'file.${pickedFile.extension}') ??
        lookupMimeType(pickedFile.name) ??
        'application/octet-stream'
        : lookupMimeType(pickedFile.name) ??
        'application/octet-stream';
    final category =
    getCategory(mimeType, pickedFile.name);

    if (backupToCloud && category == 'video') {
      throw Exception(
          'Videos cannot be backed up to cloud '
              'due to storage limits.');
    }

    if (backupToCloud) {
      final currentUsed =
      await DatabaseService.getUserStorageUsed(
          userId);
      final limit =
      await DatabaseService.getUserStorageLimit(
          userId);
      int estimatedSize = fileBytes.length;
      if (category == 'image') {
        estimatedSize =
            (fileBytes.length * 0.3).toInt();
      }
      if (currentUsed + estimatedSize > limit) {
        throw Exception(
            'Storage limit exceeded '
                '(${(limit / 1024 / 1024).toInt()} MB). '
                'Delete some files.');
      }
    }

    onProgress(0.2);
    final compressedBytes =
    await compressFile(fileBytes, mimeType);
    final compressedSize = compressedBytes.length;

    debugPrint(
        'Original: ${(fileBytes.length / 1024).toStringAsFixed(1)} KB');
    debugPrint(
        'Compressed: ${(compressedSize / 1024).toStringAsFixed(1)} KB');

    onProgress(0.4);
    final encryptedBytes =
    EncryptionService.encryptFile(compressedBytes);

    onProgress(0.6);
    final appDir =
    await getApplicationDocumentsDirectory();
    final vaultDir =
    Directory(p.join(appDir.path, 'vault', userId));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_'
        '${pickedFile.name}.enc';
    final encryptedFile =
    File(p.join(vaultDir.path, fileName));
    await encryptedFile.writeAsBytes(encryptedBytes);

    onProgress(0.7);
    String? cloudPath;
    if (backupToCloud) {
      final used =
      await DatabaseService.getCloudStorageUsed(
          userId);
      if (used + compressedSize > maxCloudBytes) {
        throw Exception(
            'Cloud storage limit reached (200MB)');
      }
      cloudPath = '$userId/$fileName';
      await Supabase.instance.client.storage
          .from('vault-files')
          .uploadBinary(cloudPath, encryptedBytes);
      final newTotal = used + compressedSize;
      await DatabaseService.updateUserStorageUsed(
          userId, newTotal);
    }

    onProgress(0.9);
    final fileModel = FileModel(
      userId: userId,
      displayName: displayName,
      encryptedPath: encryptedFile.path,
      mimeType: mimeType,
      sizeBytes: compressedSize,
      category: category,
      isCloudBacked: backupToCloud,
      cloudPath: cloudPath,
      createdAt: DateTime.now(),
    );
    final id =
    await DatabaseService.insertFile(fileModel);
    onProgress(1.0);

    return fileModel.copyWith(id: id);
  }

  // ── Delete all local encrypted files ─────────────────────
  static Future<void> deleteAllLocalFiles(
      String userId) async {
    try {
      final appDir =
      await getApplicationDocumentsDirectory();
      final vaultDir = Directory(
          p.join(appDir.path, 'vault', userId));
      if (await vaultDir.exists()) {
        await vaultDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error deleting local files: $e');
    }
  }

  // ── Delete all cloud files ───────────────────────────────
  static Future<void> deleteAllCloudFiles(
      String userId) async {
    try {
      final files = await Supabase.instance.client
          .storage
          .from('vault-files')
          .list(path: userId);
      if (files.isNotEmpty) {
        final paths = files
            .map((file) => '$userId/${file.name}')
            .toList();
        await Supabase.instance.client.storage
            .from('vault-files')
            .remove(paths);
      }
    } catch (e) {
      debugPrint('Error deleting cloud files: $e');
    }
  }

  // ── Decrypt to temp file ─────────────────────────────────
  static Future<File> decryptToTemp(
      FileModel file) async {
    final encryptedBytes =
    await File(file.encryptedPath).readAsBytes();
    final decryptedBytes =
    EncryptionService.decryptFile(encryptedBytes);
    final tempDir = await getTemporaryDirectory();
    final ext = _mimeToExt(file.mimeType);
    final tempFile = File(p.join(
        tempDir.path, '${file.displayName}.$ext'));
    await tempFile.writeAsBytes(decryptedBytes);
    return tempFile;
  }

  // ── Delete temp file ─────────────────────────────────────
  static Future<void> deleteTempFile(
      File tempFile) async {
    if (await tempFile.exists())
      await tempFile.delete();
  }

  // ── Move to trash (soft delete) ──────────────────────────
  static Future<void> deleteFile(
      FileModel file) async {
    if (file.id != null) {
      await DatabaseService.moveToTrash(file.id!);
    }
  }

  // ── Mime type to extension ───────────────────────────────
  static String _mimeToExt(String mimeType) {
    const map = {
      'audio/mpeg': 'mp3',
      'audio/mp4': 'm4a',
      'audio/aac': 'aac',
      'audio/wav': 'wav',
      'audio/x-wav': 'wav',
      'audio/ogg': 'ogg',
      'audio/flac': 'flac',
      'video/mp4': 'mp4',
      'video/x-matroska': 'mkv',
      'video/webm': 'webm',
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'application/pdf': 'pdf',
    };
    return map[mimeType] ?? mimeType.split('/').last;
  }

  // ── Export file to Downloads ─────────────────────────────
  static Future<void> exportFile(
      FileModel file, File tempFile) async {
    final isImage =
    file.mimeType.startsWith('image/');
    final isVideo =
    file.mimeType.startsWith('video/');
    String savedPath;

    if (isImage || isVideo) {
      final directory = isImage
          ? Directory(
          '/storage/emulated/0/Pictures/SafeLocker')
          : Directory(
          '/storage/emulated/0/Movies/SafeLocker');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final ext = file.mimeType.split('/').last;
      savedPath =
      '${directory.path}/${file.displayName}.$ext';
      await tempFile.copy(savedPath);
      if (Platform.isAndroid) {
        try {
          await PhotoManager.editor.saveImageWithPath(
            savedPath,
            title: file.displayName,
          );
        } catch (e) {
          debugPrint('MediaStore error: $e');
        }
      }
    } else {
      final downloadsDir =
      Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      final ext = file.mimeType.split('/').last;
      savedPath =
      '${downloadsDir.path}/${file.displayName}.$ext';
      await tempFile.copy(savedPath);
    }
    await OpenFilex.open(savedPath);
  }

  // ── Rename file ──────────────────────────────────────────
  static Future<void> renameFile(
      FileModel file, String newName) async {
    final updated =
    file.copyWith(displayName: newName);
    await DatabaseService.updateFile(updated);
  }

  // ── Format size ──────────────────────────────────────────
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024)
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
