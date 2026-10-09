import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/download_item.dart';

enum DownloadLocation { app, downloads }

class DownloadFailure implements Exception {
  const DownloadFailure(this.messageKey);
  final String messageKey;

  @override
  String toString() => messageKey;
}

class DownloadService {
  DownloadService({Dio? dio}) : _dio = dio ?? _createDio();

  static const MethodChannel _storageChannel =
      MethodChannel('com.vezaro.downloader/storage');
  final Dio _dio;

  static Dio _createDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 15),
        followRedirects: true,
        maxRedirects: 8,
        receiveDataWhenStatusError: false,
        headers: const <String, String>{'Accept': '*/*'},
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ));

  static Future<int> androidSdkInt() async {
    try {
      return await _storageChannel.invokeMethod<int>('sdkInt') ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  static Uri? parseHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !const <String>{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  static String filenameFromUrl(Uri uri) {
    var candidate = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    try {
      candidate = Uri.decodeComponent(candidate);
    } on FormatException {
      // Keep the original path segment if percent-encoding is malformed.
    }
    candidate = candidate
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    candidate = candidate.replaceAll(RegExp(r'^\.+$'), '');
    if (candidate.isEmpty || candidate.length > 160) {
      candidate = 'download_${DateTime.now().millisecondsSinceEpoch}.bin';
    }
    return candidate;
  }

  static bool isKnownPlatformPage(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    const hosts = <String>{
      'youtube.com', 'm.youtube.com', 'youtu.be', 'youtube-nocookie.com',
      'tiktok.com', 'instagram.com', 'facebook.com', 'fb.watch',
      'x.com', 'twitter.com', 'vimeo.com', 'dailymotion.com',
    };
    return hosts.any((known) => host == known || host.endsWith('.$known'));
  }

  Future<DownloadItem> download({
    required String url,
    required DownloadLocation location,
    required void Function(int received, int total) onProgress,
    required CancelToken cancelToken,
  }) async {
    final uri = parseHttpUrl(url);
    if (uri == null) throw const DownloadFailure('invalidUrl');
    if (isKnownPlatformPage(uri)) {
      throw const DownloadFailure('platformNeedsExtractor');
    }

    final support = await getApplicationSupportDirectory();
    final workDir = Directory('${support.path}${Platform.pathSeparator}downloads_work');
    await workDir.create(recursive: true);
    var name = filenameFromUrl(uri);
    final nonce = '${DateTime.now().millisecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    final tempFile = File('${workDir.path}${Platform.pathSeparator}.$nonce.part');

    try {
      final response = await _dio.download(
        uri.toString(),
        tempFile.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: onProgress,
      );

      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw const DownloadFailure('httpError');
      }
      if (!await tempFile.exists()) throw const DownloadFailure('missingFile');
      final size = await tempFile.length();
      if (size <= 0) throw const DownloadFailure('emptyFile');

      name = _filenameFromDisposition(
            _header(response.headers, Headers.contentDispositionHeader),
          ) ??
          name;
      final contentType = _header(response.headers, Headers.contentTypeHeader) ??
          'application/octet-stream';
      final mimeType = contentType.split(';').first.trim().toLowerCase();
      if (mimeType == 'text/html' || mimeType == 'application/xhtml+xml') {
        throw const DownloadFailure('webPageNotFile');
      }
      if (await _looksLikeHtml(tempFile)) {
        throw const DownloadFailure('webPageNotFile');
      }

      final now = DateTime.now();
      final id = nonce;
      String savedPath;
      String savedName = name;
      if (location == DownloadLocation.app) {
        final targetDir = Directory('${support.path}${Platform.pathSeparator}Downloads');
        await targetDir.create(recursive: true);
        savedName = _uniqueName(targetDir, name, nonce);
        final target = File('${targetDir.path}${Platform.pathSeparator}$savedName');
        await tempFile.rename(target.path);
        savedPath = target.path;
      } else {
        final result = await _storageChannel.invokeMapMethod<String, dynamic>(
          'saveToDownloads',
          <String, Object?>{
            'sourcePath': tempFile.path,
            'displayName': name,
            'mimeType': mimeType,
          },
        );
        final destination = result?['uri'] as String?;
        if (destination == null || destination.isEmpty) {
          throw const DownloadFailure('publicSaveFailed');
        }
        savedPath = destination;
        savedName = result?['displayName'] as String? ?? name;
        await tempFile.delete();
      }

      return DownloadItem(
        id: id,
        name: savedName,
        path: savedPath,
        sourceUrl: uri.toString(),
        mimeType: mimeType,
        sizeBytes: size,
        createdAt: now,
        location: location == DownloadLocation.app ? 'app' : 'downloads',
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) rethrow;
      if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
        throw const DownloadFailure('accessDenied');
      }
      if (error.response?.statusCode != null) {
        throw const DownloadFailure('httpError');
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw const DownloadFailure('timeout');
      }
      throw const DownloadFailure('networkError');
    } on PlatformException catch (error) {
      if (error.code == 'permission_required') {
        throw const DownloadFailure('storagePermissionRequired');
      }
      throw const DownloadFailure('publicSaveFailed');
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on FileSystemException {
          // Best-effort cleanup; the history is never marked successful for this file.
        }
      }
    }
  }

  Future<bool> exists(DownloadItem item) async {
    if (!item.isPublic || !item.path.startsWith('content://')) {
      return File(item.path).exists();
    }
    try {
      return await _storageChannel.invokeMethod<bool>(
            'downloadExists', <String, Object?>{'uri': item.path},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> open(DownloadItem item) async {
    try {
      return await _storageChannel.invokeMethod<bool>(
            'openDownload',
            <String, Object?>{'uri': item.path, 'mimeType': item.mimeType},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> delete(DownloadItem item) async {
    if (item.isPublic && item.path.startsWith('content://')) {
      await _storageChannel.invokeMethod<void>(
        'deleteDownload', <String, Object?>{'uri': item.path},
      );
      return;
    }
    final file = File(item.path);
    if (await file.exists()) await file.delete();
  }

  static String? _header(Headers headers, String name) => headers.value(name);


  static String? _filenameFromDisposition(String? header) {
    if (header == null || header.isEmpty) return null;
    final encoded = RegExp(r"filename\*\s*=\s*UTF-8''([^;]+)", caseSensitive: false)
        .firstMatch(header)
        ?.group(1);
    final quoted = RegExp(r'filename\s*=\s*"([^"]+)"', caseSensitive: false)
        .firstMatch(header)
        ?.group(1);
    final plain = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false)
        .firstMatch(header)
        ?.group(1);
    var candidate = encoded ?? quoted ?? plain;
    if (candidate == null) return null;
    candidate = candidate.trim().replaceAll("'", "").replaceAll('"', '');
    try {
      candidate = Uri.decodeComponent(candidate);
    } on FormatException {
      // Retain the server-provided value; filename sanitization follows.
    }
    candidate = candidate
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F<>:"/\\|?*]'), '_')
        .trim()
        .replaceAll(RegExp(r'^\.+$'), '');
    if (candidate.isEmpty || candidate.length > 160) return null;
    return candidate;
  }

  static Future<bool> _looksLikeHtml(File file) async {
    final raf = await file.open();
    try {
      final bytes = await raf.read(512);
      final start = utf8.decode(bytes, allowMalformed: true).trimLeft().toLowerCase();
      return start.startsWith('<!doctype html') ||
          start.startsWith('<html') ||
          start.startsWith('<head') ||
          start.startsWith('<body');
    } finally {
      await raf.close();
    }
  }

  static String _uniqueName(Directory directory, String name, String nonce) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    var candidate = name;
    var counter = 1;
    while (File('${directory.path}${Platform.pathSeparator}$candidate').existsSync()) {
      candidate = '${stem}_$nonce${counter == 1 ? '' : '_$counter'}$extension';
      counter++;
    }
    return candidate;
  }
}
