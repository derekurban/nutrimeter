// In-app updates: the app's releases live on GitHub (derekurban/nutrimeter, public), published by CI
// (.github/workflows/release.yml). A merge into staging releases v<version>-staging.<versionCode> carrying only
// nutrimeter-staging.apk; a merge into main releases v<version>-prod.<versionCode> carrying only nutrimeter.apk, marked
// latest. The tag's last number is the build's versionCode, which is how two builds of one version tell apart. Each
// flavour reads the release list and takes the newest release carrying its own APK. This file is the pure part:
// reading releases, picking one, and comparing versions.
import 'dart:convert';

const updateRepo = 'derekurban/nutrimeter';
const releasesUrl = 'https://api.github.com/repos/$updateRepo/releases?per_page=30';

/// A test build can read its release list from elsewhere, such as `--dart-define=UPDATE_FEED=http://127.0.0.1:8765/feed.json`
/// served from the computer through `adb reverse` (a JSON list shaped like GitHub's). Empty in every real build.
const updateFeed = String.fromEnvironment('UPDATE_FEED');

/// One published build: its version (from the tag), notes, and the download URL per asset name.
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.tag, required this.notes, required this.assets, this.at, this.build});
  final String version;

  /// The versionCode a CI tag ends in, or null for a tag without one.
  final int? build;
  final String tag;
  final String notes;
  final Map<String, String> assets;
  final DateTime? at;
}

/// The asset a flavour installs.
String assetFor(String? flavor) => flavor == 'staging' ? 'nutrimeter-staging.apk' : 'nutrimeter.apk';

/// "v0.1.5", "0.1.5+19" or "0.1.5-staging" -> [0, 1, 5]. Anything unparsable is an empty list.
List<int> versionParts(String v) {
  final core = v.trim().replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[+\-\s]')).first;
  final out = <int>[];
  for (final p in core.split('.')) {
    final n = int.tryParse(p);
    if (n == null) return const [];
    out.add(n);
  }
  return out;
}

/// Negative when [a] is older than [b], zero when equal, positive when newer. Missing parts count as zero.
int compareVersions(String a, String b) {
  final x = versionParts(a), y = versionParts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// The build number in a CI tag: "v0.1.7-staging.100042" or "v0.1.7-prod.100043" -> the number; null otherwise.
int? tagBuild(String tag) {
  final m = RegExp(r'-(?:staging|prod)\.(\d+)$').firstMatch(tag.trim());
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Whether [r] is newer than the installed build: a higher version, or for a CI build of the same version, a higher
/// build number than [installedCode].
bool isNewer(ReleaseInfo r, String installedName, int installedCode) {
  final c = compareVersions(r.version, installedName);
  if (c != 0) return c > 0;
  return r.build != null && r.build! > installedCode;
}

/// A release as people read it: "0.1.7 (build 100042)", or just "0.1.6" for a release without a build number.
String releaseLabel(ReleaseInfo r) => '${versionParts(r.version).join('.')}${r.build == null ? '' : ' (build ${r.build})'}';

/// A GitHub release JSON (the /releases/latest shape) as a ReleaseInfo, or null when it has no usable tag.
ReleaseInfo? parseRelease(String body) {
  final dynamic j;
  try {
    j = jsonDecode(body);
  } catch (_) {
    return null;
  }
  return _release(j);
}

/// The /releases list as a flavour's pick: the newest release (drafts aside) carrying [assetFor] the flavour. Null
/// when the body is not a list or nothing has the asset.
ReleaseInfo? pickRelease(String body, String? flavor) {
  final dynamic j;
  try {
    j = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (j is! List) return null;
  final all = [for (final x in j) if (x is Map<String, dynamic> && x['draft'] != true) _release(x)]
      .whereType<ReleaseInfo>()
      .where((r) => r.assets.containsKey(assetFor(flavor)))
      .toList()
    ..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
  return all.isEmpty ? null : all.first;
}

ReleaseInfo? _release(dynamic j) {
  if (j is! Map<String, dynamic>) return null;
  final tag = j['tag_name'] as String?;
  if (tag == null || versionParts(tag).isEmpty) return null;
  final assets = <String, String>{};
  for (final a in (j['assets'] as List? ?? const [])) {
    if (a is Map && a['name'] is String && a['browser_download_url'] is String) assets[a['name'] as String] = a['browser_download_url'] as String;
  }
  return ReleaseInfo(
    version: tag.replaceFirst(RegExp(r'^v'), ''),
    tag: tag,
    notes: (j['body'] as String? ?? '').trim(),
    assets: assets,
    at: DateTime.tryParse(j['published_at'] as String? ?? ''),
    build: tagBuild(tag),
  );
}

/// The build as one line: "0.1.7 (build 100042) · staging", or "0.1.7 (build 100042)" for prod.
String buildLine(String versionName, int versionCode, String flavor) =>
    '${versionParts(versionName).join('.')}${versionCode > 0 ? ' (build $versionCode)' : ''}${flavor == 'staging' ? ' · staging' : ''}';

/// The phone as one line: "Google Pixel 9 Pro · Android 16 (API 36)". The maker is left out when the model already
/// starts with it, and missing parts are skipped.
String deviceLine({String maker = '', String model = '', String android = '', int sdk = 0}) {
  final name = maker.isEmpty || model.toLowerCase().startsWith(maker.toLowerCase()) ? model : '$maker $model';
  final os = android.isEmpty ? '' : 'Android $android${sdk > 0 ? ' (API $sdk)' : ''}';
  return [name.trim(), os].where((s) => s.isNotEmpty).join(' · ');
}

enum Report { problem, idea }

/// The issue form each kind opens, a file in .github/ISSUE_TEMPLATE.
const reportTemplate = {Report.problem: 'bug.yml', Report.idea: 'feature.yml'};

/// The new-issue link for [kind]: its form in the browser with the build (and, for a problem, the phone) filled in, so
/// people only write what happened. Issues are public, so nothing else about them is added. The `version` and `device`
/// ids are text fields in the forms; test/logic_test.dart checks they still are.
Uri reportUrl(Report kind, {String version = '', String device = ''}) => Uri.https('github.com', '/$updateRepo/issues/new', {
      'template': reportTemplate[kind]!,
      if (version.isNotEmpty) 'version': version,
      if (kind == Report.problem && device.isNotEmpty) 'device': device,
    });
