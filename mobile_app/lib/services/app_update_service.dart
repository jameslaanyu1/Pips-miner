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

  static const _releasesUrl =
      'https://api.github.com/repos/jameslaanyu1/Pips-miner/releases?per_page=20';

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
    final result = await checkForUpdateDetailed();
    return result.update;
  }

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final installedVersion = packageInfo.version;

    try {
      final response = await _dio.get<List<dynamic>>(_releasesUrl);
      final releases = response.data;
      if (releases == null) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          installedVersion: installedVersion,
          message: 'GitHub returned an empty releases response.',
        );
      }

      AppUpdateInfo? newestUpdate;
      var publishedReleaseCount = 0;
      var compatibleReleaseCount = 0;
      var apkAssetCount = 0;
      String? newestRemoteVersion;

      for (final release in releases) {
        if (release is! Map<String, dynamic>) continue;
        if (release['draft'] == true || release['prerelease'] == true) continue;
        publishedReleaseCount++;

        final releaseName = release['name']?.toString() ?? '';
        final releaseTag = release['tag_name']?.toString() ?? '';
        final remoteVersion = _extractVersion(releaseName, releaseTag);
        if (remoteVersion == null) continue;
        compatibleReleaseCount++;

        if (newestRemoteVersion == null ||
            _compareVersions(remoteVersion, newestRemoteVersion) > 0) {
          newestRemoteVersion = remoteVersion;
        }

        final assets = release['assets'];
        if (assets is! List) continue;

        String? apkUrl;
        for (final asset in assets) {
          if (asset is Map<String, dynamic> &&
              asset['name']?.toString() == 'Pips-Miner-release.apk') {
            apkAssetCount++;
            apkUrl = asset['browser_download_url']?.toString();
            break;
          }
        }
        if (apkUrl == null || apkUrl.isEmpty) continue;

        final releaseUrl = release['html_url']?.toString() ?? '';
        final candidate = AppUpdateInfo(
          version: remoteVersion,
          downloadUrl: apkUrl,
          releaseUrl: releaseUrl,
        );

        if (_compareVersions(candidate.version, installedVersion) <= 0) {
          continue;
        }

        if (newestUpdate == null ||
            _compareVersions(candidate.version, newestUpdate.version) > 0) {
          newestUpdate = candidate;
        }
      }

      if (newestUpdate != null) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.updateAvailable,
          installedVersion: installedVersion,
          update: newestUpdate,
          message: 'Update ${newestUpdate.version} found. Installed version is $installedVersion.',
        );
      }

      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        installedVersion: installedVersion,
        message: 'Installed $installedVersion; newest compatible release is ${newestRemoteVersion ?? 'none'}; published releases: $publishedReleaseCount; compatible releases: $compatibleReleaseCount; APK assets: $apkAssetCount.',
      );
    } catch (error) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        installedVersion: installedVersion,
        message: 'Update check failed: ${error.runtimeType}: $error',
      );
    }
  }

  String? _extractVersion(String releaseName, String releaseTag) {
    final patterns = <RegExp>[
      RegExp(r'Pips Miner v(\d+(?:\.\d+)+)', caseSensitive: false),
      RegExp(r'^v?(\d+(?:\.\d+)+)$', caseSensitive: false),
      RegExp(r'v(\d+(?:\.\d+)+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final nameMatch = pattern.firstMatch(releaseName);
      if (nameMatch != null) return nameMatch.group(1);
      final tagMatch = pattern.firstMatch(releaseTag);
      if (tagMatch != null) return tagMatch.group(1);
    }
    return null;
  }

  Future<UpdateCheckResult> promptIfUpdateAvailable(BuildContext context) async {
    final result = await checkForUpdateDetailed();
    final update = result.update;
    if (update == null || !context.mounted) return result;

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

    if (install != true || !context.mounted) return result;

    try {
      await _downloadAndInstall(update);
    } catch (error) {
      if (!context.mounted) return result;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update failed'),
          content: Text('The update package could not be installed.\n\n$error'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    return result;
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
