import 'dart:async';
import 'dart:convert';
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

  // Keep the release-discovery method that previously worked: GitHub's
  // public /releases/latest endpoint redirects to the actual latest tag.
  // Do not depend on Vercel or the GitHub REST API for discovery.
  static const _latestReleaseUrl =
      'https://github.com/jameslaanyu1/Pips-miner/releases/latest';
  static const _latestApkUrl =
      'https://github.com/jameslaanyu1/Pips-miner/releases/latest/download/Pips-Miner-release.apk';
  static const _expectedAppName = 'Pips-Miner';
  static const _expectedApk = 'Pips-Miner-release.apk';

  final Dio _downloadClient = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(seconds: 15),
      headers: const {
        'User-Agent': 'Pips-Miner-Android-Updater',
      },
    ),
  );
  final FlutterAppInstaller _installer = FlutterAppInstaller();

  Future<AppUpdateInfo?> checkForUpdate() async =>
      (await checkForUpdateDetailed()).update;

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final installedVersion =
        (await PackageInfo.fromPlatform()).version.trim();

    try {
      final latestVersion = await _getLatestReleaseVersion();
      if (latestVersion == null) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          installedVersion: installedVersion,
          message: 'Could not determine the latest $_expectedAppName release.',
        );
      }

      if (_compareVersions(latestVersion, installedVersion) <= 0) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          installedVersion: installedVersion,
          message:
              'Installed $installedVersion; latest published release is $latestVersion.',
        );
      }

      return UpdateCheckResult(
        status: UpdateCheckStatus.updateAvailable,
        installedVersion: installedVersion,
        update: AppUpdateInfo(
          version: latestVersion,
          downloadUrl: _latestApkUrl,
          releaseUrl: _latestReleaseUrl,
        ),
        message:
            '$_expectedAppName update $latestVersion found. Installed version is $installedVersion.',
      );
    } catch (error) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        installedVersion: installedVersion,
        message: 'Update check failed: $error',
      );
    }
  }

  Future<String?> _getLatestReleaseVersion() async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(_latestReleaseUrl).replace(
        queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'Pips-Miner-App');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();

      final location = response.headers.value(HttpHeaders.locationHeader);
      final status = response.statusCode;

      if (status >= 300 && status < 400 && location != null) {
        await response.drain<void>();
        return _versionFromUrl(location);
      }

      if (status >= 200 && status < 300) {
        final body = await response.transform(utf8.decoder).join();
        return _versionFromText(body);
      }

      await response.drain<void>();
      throw HttpException(
        'GitHub latest release returned HTTP $status.',
      );
    } finally {
      client.close(force: true);
    }
  }

  String? _versionFromUrl(String value) {
    final match = RegExp(
      r'(?:^|/)(?:tag/)?v?(\d+(?:\.\d+)+)(?:[/?#]|$)',
    ).firstMatch(value);
    return match?.group(1);
  }

  String? _versionFromText(String value) {
    final match = RegExp(
      r'/releases/tag/v?(\d+(?:\.\d+)+)',
    ).firstMatch(value);
    return match?.group(1);
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
            child: const Text('Update now'),
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
            '$_expectedAppName ${update.version} has been downloaded. Install the update now?',
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
            'Android could not open the downloaded $_expectedApk file.',
          );
        }
      }
    } catch (error) {
      if (context.mounted) {
        await _showMessage(
          context,
          'Update download failed',
          'The $_expectedAppName update could not be downloaded. Please try again.',
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

    final file = File('${directory.path}/$_expectedAppName-${update.version}.apk');
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
              Text(value > 0
                  ? '${(value * 100).round()}%'
                  : 'Starting download…'),
            ],
          ),
        ),
      ),
    );

    try {
      await _downloadClient.download(
        update.downloadUrl,
        file.path,
        onReceiveProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 8,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
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
