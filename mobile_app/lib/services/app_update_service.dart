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

  // The GitHub Releases API is the single source of truth. Do not use the
  // repository manifest for version detection because it can lag behind or
  // contain metadata from a CI run rather than the release list itself.
  static const _releasesApi = 'https://api.github.com/repos/jameslaanyu1/Pips-miner/releases?per_page=100';
  static const _expectedAppName = 'Pips-Miner';
  static const _expectedApk = 'Pips-Miner-release.apk';

  final Dio _downloadClient = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 10),
    sendTimeout: const Duration(seconds: 15),
    headers: const {'User-Agent': 'Pips-Miner-Android-Updater', 'Accept': 'application/vnd.github+json'},
  ));
  final FlutterAppInstaller _installer = FlutterAppInstaller();

  Future<AppUpdateInfo?> checkForUpdate() async => (await checkForUpdateDetailed()).update;

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final installedVersion = (await PackageInfo.fromPlatform()).version.trim();
    try {
      final release = await _getLatestPublishedRelease();
      if (release == null) {
        return UpdateCheckResult(status: UpdateCheckStatus.upToDate, installedVersion: installedVersion, message: 'Installed $installedVersion; no valid published APK release was found.');
      }

      if (_compareVersions(release.version, installedVersion) <= 0) {
        return UpdateCheckResult(status: UpdateCheckStatus.upToDate, installedVersion: installedVersion, message: 'Installed $installedVersion; latest published APK release is ${release.version}.');
      }

      return UpdateCheckResult(
        status: UpdateCheckStatus.updateAvailable,
        installedVersion: installedVersion,
        update: AppUpdateInfo(version: release.version, downloadUrl: release.downloadUrl, releaseUrl: release.releaseUrl),
        message: '$_expectedAppName update ${release.version} found. Installed version is $installedVersion.',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final detail = e.message ?? e.type.toString();
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        installedVersion: installedVersion,
        message: 'GitHub update check failed${status != null ? ' (HTTP $status)' : ''}: $detail',
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        installedVersion: installedVersion,
        message: 'GitHub update check error: $e',
      );
    }
  }

  Future<_ReleaseInfo?> _getLatestPublishedRelease() async {
    final response = await _downloadClient.get<dynamic>(_releasesApi, options: Options(responseType: ResponseType.json, validateStatus: (status) => status != null && status >= 200 && status < 300));
    final data = response.data;
    if (data is! List) throw const FormatException('GitHub returned an invalid release list.');

    _ReleaseInfo? best;
    for (final item in data) {
      if (item is! Map || item['draft'] == true || item['prerelease'] == true) continue;
      final version = _normaliseVersion((item['tag_name'] as String?)?.trim() ?? '');
      if (version == null) continue;

      final assets = item['assets'];
      if (assets is! List) continue;
      String? downloadUrl;
      for (final asset in assets) {
        if (asset is Map && asset['name'] == _expectedApk) {
          final candidate = (asset['browser_download_url'] as String?)?.trim() ?? '';
          if (candidate.isNotEmpty) downloadUrl = candidate;
          break;
        }
      }
      if (downloadUrl == null) continue;

      final candidate = _ReleaseInfo(version: version, downloadUrl: downloadUrl, releaseUrl: (item['html_url'] as String?)?.trim() ?? '');
      if (best == null || _compareVersions(candidate.version, best.version) > 0) best = candidate;
    }
    return best;
  }

  String? _normaliseVersion(String tag) {
    final match = RegExp(r'^v?(\d+(?:\.\d+)+)$').firstMatch(tag);
    return match?.group(1);
  }

  Future<UpdateCheckResult> promptIfUpdateAvailable(BuildContext context) async {
    final result = await checkForUpdateDetailed();
    final update = result.update;
    if (update == null || !context.mounted) return result;

    final shouldDownload = await showDialog<bool>(context: context, barrierDismissible: false, builder: (dialogContext) => AlertDialog(
      title: const Text('Pips-Miner update available'),
      content: Text('Version ${update.version} is available. Download the new APK now?'),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Later')), FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Update now'))],
    ));
    if (shouldDownload != true || !context.mounted) return result;

    try {
      final apkFile = await _downloadApk(context, update);
      if (!context.mounted) return result;
      final shouldInstall = await showDialog<bool>(context: context, barrierDismissible: false, builder: (dialogContext) => AlertDialog(
        title: const Text('Download complete'),
        content: Text('$_expectedAppName ${update.version} has been downloaded. Install the update now?'),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Later')), FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Install update'))],
      ));
      if (shouldInstall == true && context.mounted) {
        final installed = await _installer.installApk(filePath: apkFile.path);
        if (!installed && context.mounted) await _showMessage(context, 'Installation could not start', 'Android could not open the downloaded $_expectedApk file.');
      }
    } catch (_) {
      if (context.mounted) await _showMessage(context, 'Update download failed', 'The $_expectedAppName update could not be downloaded. Please try again.');
    }
    return result;
  }

  Future<File> _downloadApk(BuildContext context, AppUpdateInfo update) async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) throw StateError('Android app storage is unavailable.');
    final file = File('${directory.path}/$_expectedAppName-${update.version}.apk');
    if (await file.exists()) await file.delete();

    final progress = ValueNotifier<double>(0);
    final dialogFuture = showDialog<void>(context: context, barrierDismissible: false, builder: (_) => ValueListenableBuilder<double>(valueListenable: progress, builder: (_, value, __) => AlertDialog(
      title: const Text('Downloading update'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [LinearProgressIndicator(value: value > 0 ? value : null), const SizedBox(height: 12), Text(value > 0 ? '${(value * 100).round()}%' : 'Starting download…')]),
    )));
    try {
      await _downloadClient.download(update.downloadUrl, file.path, onReceiveProgress: (received, total) { if (total > 0) progress.value = received / total; }, options: Options(responseType: ResponseType.bytes, followRedirects: true, maxRedirects: 8, validateStatus: (status) => status != null && status >= 200 && status < 400));
      if (!await file.exists() || await file.length() < 1024) throw StateError('Downloaded APK is empty or incomplete.');
      progress.value = 1;
      return file;
    } finally {
      progress.dispose();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      unawaited(dialogFuture);
    }
  }

  static int _compareVersions(String left, String right) {
    List<int> parts(String value) => value.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final a = parts(left), b = parts(right), length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0, bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  Future<void> _showMessage(BuildContext context, String title, String message) async => showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: Text(title), content: Text(message), actions: [FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))]));
}

class _ReleaseInfo {
  const _ReleaseInfo({required this.version, required this.downloadUrl, required this.releaseUrl});
  final String version;
  final String downloadUrl;
  final String releaseUrl;
}
