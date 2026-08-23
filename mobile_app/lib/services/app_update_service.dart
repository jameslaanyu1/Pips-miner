import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_installer/flutter_app_installer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseUrl,
  });

  final String version;
  final String downloadUrl;
  final String releaseUrl;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const _latestReleaseUrl =
      'https://api.github.com/repos/jameslaanyu1/Pips-miner/releases/latest';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: true,
      validateStatus: (status) => status != null && status >= 200 && status < 300,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Pips-Miner-App',
      },
    ),
  );

  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final response = await _dio.get<Map<String, dynamic>>(_latestReleaseUrl);
      final data = response.data;
      if (data == null) return null;

      // Release tags are deliberately unique CI identifiers and are NOT the
      // application version. The release title carries the actual app version.
      final releaseName = data['name']?.toString() ?? '';
      final versionMatch = RegExp(r'Pips Miner v(\d+(?:\.\d+)+)').firstMatch(releaseName);
      final remoteVersion = versionMatch?.group(1) ?? '';
      final releaseUrl = data['html_url']?.toString() ?? '';

      final assets = data['assets'];
      if (assets is! List || remoteVersion.isEmpty) return null;

      String? apkUrl;
      for (final asset in assets) {
        if (asset is Map<String, dynamic> &&
            asset['name']?.toString() == 'Pips-Miner-release.apk') {
          apkUrl = asset['browser_download_url']?.toString();
          break;
        }
      }

      if (apkUrl == null || apkUrl.isEmpty) return null;

      if (_compareVersions(remoteVersion, packageInfo.version) <= 0) {
        return null;
      }

      return AppUpdateInfo(
        version: remoteVersion,
        downloadUrl: apkUrl,
        releaseUrl: releaseUrl,
      );
    } catch (_) {
      // Update checks must never prevent Pips Miner from starting.
      return null;
    }
  }

  Future<void> promptIfUpdateAvailable(BuildContext context) async {
    final update = await checkForUpdate();
    if (update == null || !context.mounted) return;

    final install = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Pips Miner update available'),
          content: Text(
            'Version ${update.version} is ready. Update now to get the latest Pips Miner build.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Update now'),
            ),
          ],
        );
      },
    );

    if (install != true || !context.mounted) return;

    try {
      await _downloadAndInstall(update);
    } catch (_) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update failed'),
          content: const Text(
            'The update package could not be installed. Please try again when the new release is available.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _downloadAndInstall(AppUpdateInfo update) async {
    final directory = await getTemporaryDirectory();
    final apkPath = '${directory.path}/Pips-Miner-${update.version}.apk';
    final file = File(apkPath);

    if (await file.exists()) {
      await file.delete();
    }

    final response = await _dio.download(
      update.downloadUrl,
      apkPath,
      deleteOnError: true,
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {
          'Accept': 'application/octet-stream',
          'User-Agent': 'Pips-Miner-App',
        },
      ),
    );

    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw StateError('APK download failed with HTTP ${response.statusCode}.');
    }

    if (!await file.exists()) {
      throw StateError('APK download did not produce a file.');
    }

    final length = await file.length();
    if (length < 1024 * 1024) {
      throw StateError('Downloaded APK is unexpectedly small.');
    }

    final bytes = await file.openRead(0, 4).fold<List<int>>(
      <int>[],
      (previous, chunk) => previous..addAll(chunk),
    );
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4b ||
        bytes[2] != 0x03 ||
        bytes[3] != 0x04) {
      await file.delete();
      throw StateError('Downloaded file is not a valid APK package.');
    }

    final installer = FlutterAppInstaller();
    await installer.installApk(filePath: apkPath);
  }

  static int _compareVersions(String left, String right) {
    List<int> parts(String value) {
      final match = RegExp(r'^\d+(?:\.\d+)*').firstMatch(value);
      if (match == null) return const [0];
      return match.group(0)!
          .split('.')
          .map((part) => int.tryParse(part) ?? 0)
          .toList();
    }

    final a = parts(left);
    final b = parts(right);
    final length = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }

    return 0;
  }
}
