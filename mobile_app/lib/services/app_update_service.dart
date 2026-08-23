import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_installer/flutter_app_installer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

enum UpdateCheckStatus { updateAvailable, upToDate, failed }

class UpdateCheckResult {
  const UpdateCheckResult({required this.status, required this.installedVersion, this.update, required this.message});
  final UpdateCheckStatus status;
  final String installedVersion;
  final AppUpdateInfo? update;
  final String message;
}

class AppUpdateInfo {
  const AppUpdateInfo({required this.version, required this.downloadUrl, required this.releaseUrl});
  final String version;
  final String downloadUrl;
  final String releaseUrl;
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const _releasesFeedUrl = 'https://github.com/jameslaanyu1/Pips-miner/releases.atom';
  static const _latestReleaseUrl = 'https://github.com/jameslaanyu1/Pips-miner/releases/latest';
  static const _latestApkUrl = 'https://github.com/jameslaanyu1/Pips-miner/releases/latest/download/Pips-Miner-release.apk';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 10),
    followRedirects: true,
    maxRedirects: 8,
    validateStatus: (status) => status != null && status >= 200 && status < 300,
    headers: const {'Accept': 'application/atom+xml, application/xml, text/xml, */*', 'User-Agent': 'Pips-Miner-App'},
  ));

  Future<AppUpdateInfo?> checkForUpdate() async => (await checkForUpdateDetailed()).update;

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final installedVersion = (await PackageInfo.fromPlatform()).version;
    try {
      final response = await _dio.get<String>(_releasesFeedUrl);
      final feed = response.data;
      if (feed == null || feed.trim().isEmpty) {
        return UpdateCheckResult(status: UpdateCheckStatus.failed, installedVersion: installedVersion, message: 'GitHub returned an empty releases feed.');
      }
      final latestRelease = _parseLatestRelease(feed);
      if (latestRelease == null) {
        return UpdateCheckResult(status: UpdateCheckStatus.failed, installedVersion: installedVersion, message: 'GitHub releases feed did not contain a compatible Pips Miner version.');
      }
      if (_compareVersions(latestRelease.version, installedVersion) <= 0) {
        return UpdateCheckResult(status: UpdateCheckStatus.upToDate, installedVersion: installedVersion, message: 'Installed $installedVersion; latest published release is ${latestRelease.version}.');
      }
      return UpdateCheckResult(status: UpdateCheckStatus.updateAvailable, installedVersion: installedVersion, update: latestRelease, message: 'Update ${latestRelease.version} found. Installed version is $installedVersion.');
    } catch (error) {
      return UpdateCheckResult(status: UpdateCheckStatus.failed, installedVersion: installedVersion, message: 'Update check failed: ${error.runtimeType}: $error');
    }
  }

  AppUpdateInfo? _parseLatestRelease(String feed) {
    final entryMatch = RegExp(r'<entry\b[^>]*>([\s\S]*?)</entry>', caseSensitive: false).firstMatch(feed);
    if (entryMatch == null) return null;
    final entry = entryMatch.group(1)!;
    final titleMatch = RegExp(r'<title\b[^>]*>\s*(?:Pips\s+Miner\s+)?v?(\d+(?:\.\d+)+)\s*</title>', caseSensitive: false).firstMatch(entry);
    if (titleMatch == null) return null;
    final version = titleMatch.group(1)!;
    return AppUpdateInfo(version: version, downloadUrl: _latestApkUrl, releaseUrl: _latestReleaseUrl);
  }

  Future<UpdateCheckResult> promptIfUpdateAvailable(BuildContext context) async {
    final result = await checkForUpdateDetailed();
    final update = result.update;
    if (update == null || !context.mounted) return result;

    final download = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pips Miner update available'),
        content: Text('Version ${update.version} is ready. Download the new app version to this device now.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Update now')),
        ],
      ),
    );
    if (download != true || !context.mounted) return result;

    String? apkPath;
    try {
      apkPath = await _downloadApk(update, context);
    } catch (error) {
      if (!context.mounted) return result;
      await _showMessage(context, 'Update download failed', 'The new app version could not be downloaded.\n\n$error');
      return result;
    }

    if (!context.mounted || apkPath == null) return result;

    final install = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update downloaded'),
        content: Text('Version ${update.version} has been downloaded to this device.\n\nPress Update app to install it.'),
        actions: [
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Update app')),
        ],
      ),
    );

    if (install != true || !context.mounted) return result;

    try {
      await FlutterAppInstaller().installApk(filePath: apkPath);
    } catch (error) {
      if (!context.mounted) return result;
      await _showMessage(context, 'Installation could not start', 'The downloaded APK is still saved on the device.\n\n$error');
    }
    return result;
  }

  Future<void> _showMessage(BuildContext context, String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
      ),
    );
  }

  Future<String> _downloadApk(AppUpdateInfo update, BuildContext context) async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) throw StateError('Android local app storage is unavailable.');
    await directory.create(recursive: true);

    final apkPath = '${directory.path}/Pips-Miner-${update.version}.apk';
    final tempPath = '$apkPath.part';
    final tempFile = File(tempPath);
    final apkFile = File(apkPath);
    if (await tempFile.exists()) await tempFile.delete();
    if (await apkFile.exists()) await apkFile.delete();

    final downloadFuture = _dio.download(
      update.downloadUrl,
      tempPath,
      deleteOnError: false,
      options: Options(
        headers: const {
          'Accept': 'application/vnd.android.package-archive, application/octet-stream, */*',
          'User-Agent': 'Pips-Miner-App',
          'Accept-Encoding': 'identity',
        },
        responseType: ResponseType.bytes,
      ),
      onReceiveProgress: (received, total) {
        if (context.mounted) _downloadProgressNotifier.value = DownloadProgress(received: received, total: total);
      },
    );

    _downloadProgressNotifier.value = const DownloadProgress(received: 0, total: -1);
    await _showDownloadProgress(context, update, downloadFuture);
    await downloadFuture;

    if (!await tempFile.exists()) throw StateError('APK download did not produce a file.');
    final length = await tempFile.length();
    if (length < 1024 * 1024) {
      await tempFile.delete();
      throw StateError('Downloaded APK is unexpectedly small.');
    }

    final bytes = await tempFile.openRead(0, 4).fold<List<int>>(<int>[], (previous, chunk) => previous..addAll(chunk));
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b || bytes[2] != 0x03 || bytes[3] != 0x04) {
      await tempFile.delete();
      throw StateError('Downloaded file is not a valid APK package.');
    }

    await tempFile.rename(apkPath);
    return apkPath;
  }

  final ValueNotifier<DownloadProgress> _downloadProgressNotifier = ValueNotifier(const DownloadProgress(received: 0, total: -1));

  Future<void> _showDownloadProgress(BuildContext context, AppUpdateInfo update, Future<Response> downloadFuture) async {
    final completer = Future<void>.delayed(const Duration(days: 1));
    downloadFuture.whenComplete(() {}).then((_) {});

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        downloadFuture.whenComplete(() {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        });
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Downloading update'),
            content: ValueListenableBuilder<DownloadProgress>(
              valueListenable: _downloadProgressNotifier,
              builder: (_, progress, __) {
                final fraction = progress.total > 0 ? (progress.received / progress.total).clamp(0.0, 1.0) : null;
                final receivedText = _formatBytes(progress.received);
                final totalText = progress.total > 0 ? ' / ${_formatBytes(progress.total)}' : '';
                final percentText = fraction == null ? 'Downloading…' : '${(fraction * 100).round()}%';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Version ${update.version}', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: fraction),
                    const SizedBox(height: 10),
                    Text('$percentText  •  $receivedText$totalText'),
                    const SizedBox(height: 6),
                    const Text('Please keep Pips-Miner open until the download is complete.'),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    await completer;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static int _compareVersions(String left, String right) {
    List<int> parts(String value) {
      final match = RegExp(r'^\d+(?:\.\d+)*').firstMatch(value);
      if (match == null) return const [0];
      return match.group(0)!.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    }
    final a = parts(left), b = parts(right), length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0, bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}

class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});
  final int received;
  final int total;
}
