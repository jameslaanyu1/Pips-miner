import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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

  // Do not use api.github.com here. Anonymous GitHub REST requests are
  // rate-limited per public IP. The public release page is the source of
  // truth and redirects to the current release tag.
  static const _latestReleaseUrl = 'https://github.com/jameslaanyu1/Pips-miner/releases/latest';
  static const _latestApkUrl = 'https://github.com/jameslaanyu1/Pips-miner/releases/latest/download/Pips-Miner-release.apk';

  final DioLike _feedClient = DioLike();

  Future<AppUpdateInfo?> checkForUpdate() async => (await checkForUpdateDetailed()).update;

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final installedVersion = (await PackageInfo.fromPlatform()).version;
    try {
      final version = await _feedClient.getLatestReleaseVersion(_latestReleaseUrl);
      if (version == null) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          installedVersion: installedVersion,
          message: 'Could not determine the latest Pips Miner release from GitHub.',
        );
      }

      if (_compareVersions(version, installedVersion) <= 0) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          installedVersion: installedVersion,
          message: 'Installed $installedVersion; latest published release is $version.',
        );
      }

      return UpdateCheckResult(
        status: UpdateCheckStatus.updateAvailable,
        installedVersion: installedVersion,
        update: AppUpdateInfo(
          version: version,
          downloadUrl: _latestApkUrl,
          releaseUrl: _latestReleaseUrl,
        ),
        message: 'Update $version found. Installed version is $installedVersion.',
      );
    } catch (error) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        installedVersion: installedVersion,
        message: 'Update check failed: $error',
      );
    }
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

/// Release discovery only. The actual APK download is handed to Chrome.
class DioLike {
  Future<String?> getLatestReleaseVersion(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      // Read the release redirect ourselves. This avoids depending on the
      // redirect chain being exposed by different Android HTTP implementations.
      request.followRedirects = false;
      request.headers.set('User-Agent', 'Pips-Miner-App');
      final response = await request.close();

      String? location = response.headers.value(HttpHeaders.locationHeader);
      final status = response.statusCode;

      if (status >= 300 && status < 400 && location != null) {
        await response.drain<void>();
        return _versionFromUrl(location);
      }

      if (status >= 200 && status < 300) {
        // A proxy may have followed the redirect before it reaches us.
        // Parse the public release page only as a fallback.
        final body = await response.transform(utf8.decoder).join();
        return _versionFromText(body);
      }

      final body = await response.transform(utf8.decoder).join();
      throw HttpException('GitHub release page returned HTTP $status${body.isEmpty ? '' : ': $body'}');
    } finally {
      client.close(force: true);
    }
  }

  String? _versionFromUrl(String value) {
    final match = RegExp(r'(?:^|/)(?:tag/)?v?(\d+(?:\.\d+)+)(?:[/?#]|$)').firstMatch(value);
    return match?.group(1);
  }

  String? _versionFromText(String value) {
    final tagMatch = RegExp(r'/releases/tag/v?(\d+(?:\.\d+)+)').firstMatch(value);
    if (tagMatch != null) return tagMatch.group(1);
    return null;
  }
}
