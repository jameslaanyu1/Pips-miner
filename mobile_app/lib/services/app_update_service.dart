import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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

  final DioLike _feedClient = DioLike();

  Future<AppUpdateInfo?> checkForUpdate() async => (await checkForUpdateDetailed()).update;

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final installedVersion = (await PackageInfo.fromPlatform()).version;
    try {
      final feed = await _feedClient.get(_releasesFeedUrl);
      if (feed.trim().isEmpty) {
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
      return UpdateCheckResult(status: UpdateCheckStatus.failed, installedVersion: installedVersion, message: 'Update check failed: $error');
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
        content: Text('Version ${update.version} is ready. Chrome will download the APK to your phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Update now')),
        ],
      ),
    );
    if (download != true || !context.mounted) return result;

    try {
      final uri = Uri.parse(update.downloadUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await _showMessage(context, 'Download could not start', 'Chrome could not be opened for the APK download.');
      }
    } catch (error) {
      if (context.mounted) await _showMessage(context, 'Download could not start', '$error');
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

  static int _compareVersions(String left, String right) {
    List<int> parts(String value) {
      final match = RegExp(r'^\d+(?:\.\d+)*').firstMatch(value);
      if (match == null) return const [0];
      return match.group(0)!.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    }
    final a = parts(left), b = parts(right), length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}

/// Small abstraction used only for the release-feed request so the updater's
/// public behavior remains unchanged while Chrome owns the APK download.
class DioLike {
  Future<String> get(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'Pips-Miner-App');
      final response = await request.close();
      return await response.transform(const SystemEncoding().decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}
