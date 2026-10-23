// The Android side of updates and links: method channels in MainActivity.kt. On any other platform (and in tests) the
// calls fail quietly and the app behaves as if no update is available.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../logic/update.dart';

/// This build and phone, as Android reports them.
class AppInfo {
  const AppInfo({required this.versionName, required this.versionCode, required this.flavor, required this.package,
      this.maker = '', this.model = '', this.android = '', this.sdk = 0});
  final String versionName, flavor, package, maker, model, android;
  final int versionCode, sdk;

  String get build => buildLine(versionName, versionCode, flavor);
  String get device => deviceLine(maker: maker, model: model, android: android, sdk: sdk);
}

class UpdateBridge {
  static const _ch = MethodChannel('nutrimeter/update');

  /// How install sessions end, as Android's PackageInstaller status codes (0 success, -1 waiting on the user's
  /// confirm, anything else a failure) with Android's message.
  static Stream<({int status, String? message})> get statuses {
    _statuses ??= StreamController<({int status, String? message})>.broadcast();
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'installStatus') {
        final m = Map<String, dynamic>.from(call.arguments as Map);
        _statuses!.add((status: (m['status'] as num?)?.toInt() ?? 1, message: m['message'] as String?));
      }
    });
    return _statuses!.stream;
  }

  static StreamController<({int status, String? message})>? _statuses;

  static Future<AppInfo?> appInfo() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('appInfo');
      if (m == null) return null;
      return AppInfo(
          versionName: m['versionName'] as String? ?? '',
          versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
          flavor: m['flavor'] as String? ?? 'prod',
          package: m['package'] as String? ?? '',
          maker: m['maker'] as String? ?? '',
          model: m['model'] as String? ?? '',
          android: m['android'] as String? ?? '',
          sdk: (m['sdk'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// The newest release on GitHub carrying [flavor]'s APK. `reachable` is false when the request itself failed; a
  /// reachable answer with no release means nothing has been published yet.
  static Future<({ReleaseInfo? release, bool reachable})> latest(String? flavor) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(updateFeed.isEmpty ? releasesUrl : updateFeed));
      req.headers.set(HttpHeaders.userAgentHeader, 'nutrimeter-app');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close();
      final body = await res.transform(const Utf8Decoder()).join();
      if (res.statusCode == 404) return (release: null, reachable: true);
      if (res.statusCode != 200) return (release: null, reachable: false);
      return (release: pickRelease(body, flavor), reachable: true);
    } catch (_) {
      return (release: null, reachable: false);
    } finally {
      client.close();
    }
  }

  static Future<bool> canInstall() async {
    try {
      return await _ch.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInstallSettings() async {
    try {
      await _ch.invokeMethod<bool>('openInstallSettings');
    } catch (_) {}
  }

  /// Downloads [url] into the app's update folder as [name], reporting 0..1, and returns the file path.
  static Future<String?> download(String url, String name, void Function(double) onProgress) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final dir = await _ch.invokeMethod<String>('cacheDir');
      if (dir == null) return null;
      final file = File('$dir/$name');
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = true;
      req.headers.set(HttpHeaders.userAgentHeader, 'nutrimeter-app');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final total = res.contentLength;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      onProgress(1);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<bool> install(String path) async {
    try {
      return await _ch.invokeMethod<bool>('install', {'path': path}) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Web pages, opened in the browser.
class LinkBridge {
  static const _ch = MethodChannel('nutrimeter/links');

  /// False when nothing on the phone can open [url].
  static Future<bool> open(Uri url) async {
    try {
      return await _ch.invokeMethod<bool>('open', {'url': url.toString()}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
