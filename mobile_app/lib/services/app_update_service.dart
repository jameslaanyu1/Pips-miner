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
      receiveTimeout: const Duration(seconds: 30),
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

      if (response.data == null) return null;

      final tag = response.data!['tag_name']?.toString() ?? '';
      final remoteVersion = tag.startsWith('v') ? tag.substring(1) : tag;
      final releaseUrl = response.data!['html_url']?.toString() ?? '';

      final assets = response.data!['assets'];
      if (assets is! List) return null;

      String? apkUrl;
      for (final asset in assets) {
        if (asset is Map<String, dynamic> &&
            asset['name']?.toString() == 'Pips-Miner-release.apk') {
          apkUrl = asset['browser_download_url']?.toString();
          break;
        }
      }

      if (apkUrl == null || remoteVersion.isEmpty) return null;

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

    await _downloadAndInstall(update);
  }

  Future<void> _downloadAndInstall(AppUpdateInfo update) async {
    final directory = await getTemporaryDirectory();
    final apkPath = '${directory.path}/Pips-Miner-${update.version}.apk';
    final file = File(apkPath);

    if (!await file.exists()) {
      await _dio.download(
        update.downloadUrl,
        apkPath,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {
            'Accept': 'application/octet-stream',
            'User-Agent': 'Pips-Miner-App',
          },
        ),
      );
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
