import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_installer/flutter_app_installer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

enum UpdateCheckStatus { updateAvailable, upToDate, failed }

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.installedVersion,
    this.update,
    required this.message,
  });

  final UpdateCheckStatus status;
  final String installedVersion;
  final AppUpdateInfo? update;
  final String message;
}

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

  static const _githubLatestReleaseUrl =
      'https://api.github.com/repos/jameslaanyu1/Pips-miner/releases/latest';
  static const _releaseInfoUrl =
      'https://pips-miner-backend.vercel.app/api/update';
  static const _expectedApk = 'Pips-Miner-release.apk';

  final Dio _client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Pips-Miner-Android-Updater',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    ),
  );
  final FlutterAppInstaller _installer = FlutterAppInstaller();

  Future<AppUpdateInfo?> checkForUpdate() async =>
      (await checkForUpdateDetailed()).update;

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final installedVersion = (await PackageInfo.fromPlatform()).version.trim();

    // GitHub Releases is the source of truth. Vercel is retained only as a
    // fallback so a temporary GitHub/API/network problem cannot prevent an
    // installed app from discovering a published release.
    final sources = <Future<Map<String, dynamic>? Function()>>[];
    try {
      final update = await _queryGitHubLatestRelease();
      if (update != null) {
        return _compareRelease(installedVersion, update);
      }
    } catch (_) {
      // Try the server-side fallback below.
    }

    try {
      final update = await _queryVercelReleaseInfo();
      if (update != null) {
        return _compareRelease(installedVersion, update);
      }
    } catch (error) {
      return _failed(
        installedVersion,
        'Update check is temporarily unavailable. Please try again.',
      );
    }

    return _failed(
      installedVersion,
      'No valid Pips-Miner release information was returned.',
    );
  }

  Future<Map<String, dynamic>?> _queryGitHubLatestRelease() async {
    final response = await _client.get<Map<String, dynamic>>(
      _githubLatestReleaseUrl,
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
      options: Options(
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Pips-Miner-Android-Updater',
          'X-GitHub-Api-Version': '2022-11-28',
          'Cache-Control': 'no-cache',
        },
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );

    final data = response.data;
    if (data == null) throw StateError('GitHub returned an empty release response.');

    final tag = data['tag_name']?.toString().trim() ?? '';
    final version = _cleanVersion(tag);
    if (version == null) {
      throw StateError('GitHub latest release has an invalid version tag.');
    }

    final assets = data['assets'];
    if (assets is! List) {
      throw StateError('GitHub latest release has no APK asset list.');
    }

    Map<String, dynamic>? apk;
    for (final item in assets) {
      if (item is Map<String, dynamic> &&
          item['name']?.toString().trim() == _expectedApk) {
        apk = item;
        break;
      }
    }
    if (apk == null) {
      throw StateError('GitHub latest release is missing $_expectedApk.');
    }

    final downloadUrl = apk['browser_download_url']?.toString().trim() ?? '';
    final releaseUrl = data['html_url']?.toString().trim() ?? '';
    if (downloadUrl.isEmpty || releaseUrl.isEmpty) {
      throw StateError('GitHub latest release is missing required URLs.');
    }

    return {
      'version': version,
      'downloadUrl': downloadUrl,
      'releaseUrl': releaseUrl,
      'assetName': _expectedApk,
    };
  }

  Future<Map<String, dynamic>?> _queryVercelReleaseInfo() async {
    final response = await _client.get<Map<String, dynamic>>(
      _releaseInfoUrl,
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
      options: Options(
        headers: const {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );

    final data = response.data;
    if (data == null || data['ok'] != true) {
      throw StateError('Update service could not retrieve the latest release.');
    }

    return {
      'version': data['version'],
      'downloadUrl': data['downloadUrl'],
      'releaseUrl': data['releaseUrl'],
      'assetName': data['assetName'],
    };
  }

  UpdateCheckResult _compareRelease(
    String installedVersion,
    Map<String, dynamic> data,
  ) {
    final version = _cleanVersion(data['version']);
    final downloadUrl = data['downloadUrl']?.toString().trim() ?? '';
    final releaseUrl = data['releaseUrl']?.toString().trim() ?? '';
    final assetName = data['assetName']?.toString().trim() ?? '';

    if (version == null ||
        downloadUrl.isEmpty ||
        releaseUrl.isEmpty ||
        assetName != _expectedApk) {
      return _failed(
        installedVersion,
        'Latest GitHub release is missing required Pips-Miner release data.',
      );
    }

    if (_compareVersions(version, installedVersion) <= 0) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        installedVersion: installedVersion,
        message: 'Pips-Miner is up to date.',
      );
    }

    return UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      installedVersion: installedVersion,
      update: AppUpdateInfo(
        version: version,
        downloadUrl: downloadUrl,
        releaseUrl: releaseUrl,
      ),
      message: 'Pips-Miner update $version is available.',
    );
  }

  Future<UpdateCheckResult> promptIfUpdateAvailable(
    BuildContext context,
  ) async {
    final result = await checkForUpdateDetailed();
    final update = result.update;
    if (update == null || !context.mounted) return result;

    final shouldDownload = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pips-Miner update available'),
        content: Text(
          'Version ${update.version} is available. Download the new APK now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (shouldDownload != true || !context.mounted) return result;

    try {
      final apkFile = await _downloadApk(context, update);
      if (!context.mounted) return result;

      final shouldInstall = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Download complete'),
          content: Text(
            'Pips-Miner ${update.version} is downloaded. Install the update now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Install update'),
            ),
          ],
        ),
      );

      if (shouldInstall == true && context.mounted) {
        final installed = await _installer.installApk(filePath: apkFile.path);
        if (!installed && context.mounted) {
          await _showMessage(
            context,
            'Installation could not start',
            'Android could not open the downloaded Pips-Miner APK.',
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        await _showMessage(
          context,
          'Download could not start',
          'The Pips-Miner update could not be downloaded. Please try again.',
        );
      }
    }

    return result;
  }

  Future<File> _downloadApk(
    BuildContext context,
    AppUpdateInfo update,
  ) async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) {
      throw StateError('Android app storage is unavailable.');
    }

    final file = File('${directory.path}/Pips-Miner-${update.version}.apk');
    if (await file.exists()) await file.delete();

    final progress = ValueNotifier<double>(0);
    var dialogOpen = true;

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, __) => AlertDialog(
          title: const Text('Downloading update'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value > 0 ? value : null),
              const SizedBox(height: 12),
              Text(value > 0 ? '${(value * 100).round()}%' : 'Starting download…'),
            ],
          ),
        ),
      ),
    );

    try {
      await _client.download(
        update.downloadUrl,
        file.path,
        onReceiveProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 8,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );

      if (!await file.exists() || await file.length() < 1024) {
        throw StateError('Downloaded APK is empty or incomplete.');
      }
      progress.value = 1;
      return file;
    } finally {
      progress.dispose();
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      unawaited(dialogFuture);
    }
  }

  UpdateCheckResult _failed(String installedVersion, String message) =>
      UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        installedVersion: installedVersion,
        message: message,
      );

  String? _cleanVersion(dynamic value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^v?(\d+(?:\.\d+){2})$').firstMatch(text);
    return match?.group(1);
  }

  static int _compareVersions(String left, String right) {
    List<int> parts(String value) => value
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();

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

  Future<void> _showMessage(
    BuildContext context,
    String title,
    String message,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
