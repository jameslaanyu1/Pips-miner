import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const _installerChannel = MethodChannel('pips_miner/update_installer');

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 2),
    followRedirects: true,
    maxRedirects: 8,
    validateStatus: (status) => status != null && status >= 200 && status < 300,
    headers: const {
      'Accept': 'application/atom+xml, application/xml, text/xml, */*',
      'User-Agent': 'Pips-Miner-App',
    },
  ));

  Future<AppUpdateInfo?> checkForUpdate() async => (await checkForUpdateDetailed()).update;

  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final installedVersion = packageInfo.version;
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
    final install = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pips Miner update available'),
        content: Text('Version ${update.version} is ready. Update now to get the latest Pips Miner build.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Update now')),
        ],
      ),
    );
    if (install != true || !context.mounted) return result;

    try {
      final installerReady = await _prepareInstaller();
      if (!installerReady) {
        if (!context.mounted) return result;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Allow Pips Miner to install updates'),
            content: const Text('Android has opened the permission screen. Allow Pips Miner to install apps from this source, then return to Pips Miner and press Update now again.'),
            actions: [FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
          ),
        );
        return result;
      }
      await _downloadAndInstall(update);
    } catch (error) {
      if (!context.mounted) return result;
      final message = error is DioException
          ? 'The APK download was interrupted. Please try Update now again; the download will resume from the saved data.'
          : 'The update package could not be installed.\n\n$error';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update failed'),
          content: Text(message),
          actions: [FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
        ),
      );
    }
    return result;
  }

  Future<bool> _prepareInstaller() async {
    if (!Platform.isAndroid) return true;
    final allowed = await _installerChannel.invokeMethod<bool>('prepareInstaller') ?? true;
    return allowed;
  }

  Future<void> _downloadAndInstall(AppUpdateInfo update) async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) throw StateError('Android external app storage is unavailable.');
    final apkPath = '${directory.path}/Pips-Miner-${update.version}.apk';
    final file = File(apkPath);
    if (await file.exists()) await file.delete();

    await _downloadApkWithResume(update.downloadUrl, file);

    if (!await file.exists()) throw StateError('APK download did not produce a file.');
    final length = await file.length();
    if (length < 1024 * 1024) throw StateError('Downloaded APK is unexpectedly small.');
    final bytes = await file.openRead(0, 4).fold<List<int>>(<int>[], (previous, chunk) => previous..addAll(chunk));
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b || bytes[2] != 0x03 || bytes[3] != 0x04) {
      await file.delete();
      throw StateError('Downloaded file is not a valid APK package.');
    }
    await FlutterAppInstaller().installApk(filePath: apkPath);
  }

  Future<void> _downloadApkWithResume(String url, File file) async {
    const maxAttempts = 5;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final existingLength = await file.exists() ? await file.length() : 0;
        final headers = <String, dynamic>{
          'Accept': 'application/vnd.android.package-archive, application/octet-stream, */*',
          'User-Agent': 'Pips-Miner-App',
          'Accept-Encoding': 'identity',
        };
        if (existingLength > 0) {
          headers['Range'] = 'bytes=$existingLength-';
        }

        final response = await _dio.get<ResponseBody>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
          ),
        );
        final status = response.statusCode ?? 0;
        final stream = response.data?.stream;
        if (stream == null) throw StateError('GitHub returned an empty APK download stream.');

        if (existingLength > 0 && status != HttpStatus.partialContent) {
          await stream.listen((_) {}).cancel();
          await file.delete();
          if (status != HttpStatus.ok) {
            throw StateError('APK resume request returned HTTP $status.');
          }
          continue;
        }
        if (existingLength == 0 && status != HttpStatus.ok && status != HttpStatus.partialContent) {
          await stream.listen((_) {}).cancel();
          throw StateError('APK download returned HTTP $status.');
        }

        final sink = file.openWrite(
          mode: existingLength > 0 ? FileMode.append : FileMode.write,
        );
        try {
          await stream.pipe(sink);
        } finally {
          await sink.close();
        }
        return;
      } catch (error) {
        lastError = error;
        if (attempt == maxAttempts) break;
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
      }
    }

    if (lastError != null) throw lastError!;
    throw StateError('APK download failed without a reported error.');
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
