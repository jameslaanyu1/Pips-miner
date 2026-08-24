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

  // The phone previously failed DNS resolution for github.com. Release
  // discovery therefore goes through the Pips-Miner Vercel backend, which
  // reads GitHub's latest published release server-side.
  static const _releaseInfoUrl = 'https://pips-miner-backend.vercel.app/api/update';

  final Dio _client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/json'},
    ),
  );
  final FlutterAppInstaller _installer = FlutterAppInstaller();

  Future<AppUpdateInfo?> checkForUpdate() async =>
      (await checkForUpdateDetailed()).update;

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final installedVersion = (await PackageInfo.fromPlatform()).version;

    try {
      final response = await _client.get<Map<String, dynamic>>(_releaseInfoUrl);
      final data = response.data;
      if (data == null) {
        return _failed(installedVersion, 'Empty update service response.');
      }

      if (data['ok'] != true) {
        return _failed(
          installedVersion,
          'Update service could not check GitHub for a release.',
        );
      }

      // No published release is a valid no-update state, not an error.
      if (data['updateAvailable'] != true) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          installedVersion: installedVersion,
          message: 'Pips-Miner is up to date.',
        );
      }

      final version = _cleanVersion(data['version']);
      final downloadUrl = data['downloadUrl']?.toString().trim() ?? '';
      final releaseUrl = data['releaseUrl']?.toString().trim() ?? '';
      final assetName = data['assetName']?.toString().trim() ?? '';

      // The release contract requires this exact production APK asset.
      if (version == null ||
          downloadUrl.isEmpty ||
          releaseUrl.isEmpty ||
          assetName != 'Pips-Miner-release.apk') {
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
    } on DioException catch (error) {
      return _failed(
        installedVersion,
        'Update check is temporarily unavailable: ${error.message ?? 'network error'}.',
      );
    } catch (error) {
      return _failed(installedVersion, 'Update check failed: $error');
    }
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
    } catch (error) {
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
      // Ensure the dialog future is consumed so it does not outlive the update flow.
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
    final match = RegExp(r'^\d+(?:\.\d+){2}$').firstMatch(text);
    return match?.group(0);
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
