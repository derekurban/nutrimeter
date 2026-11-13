import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimeter/logic/update.dart';
import 'package:nutrimeter/version.dart';

void main() {
  group('updates', () {
    test('versions parse from tags, pubspec strings and flavour suffixes', () {
      expect(versionParts('v0.13.5'), [0, 13, 5]);
      expect(versionParts('0.13.5+19'), [0, 13, 5]);
      expect(versionParts('0.13.5-staging'), [0, 13, 5]);
      expect(versionParts('nope'), isEmpty);
    });

    test('newer means a higher part, left to right, with missing parts as zero', () {
      expect(compareVersions('0.14.0', '0.13.9'), greaterThan(0));
      expect(compareVersions('0.13.5', '0.13.5+19'), 0);
      expect(compareVersions('0.13', '0.13.0'), 0);
      expect(compareVersions('v0.13.4', '0.13.5-staging'), lessThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
    });

    test('a GitHub release gives the version, notes and one URL per asset', () {
      final r = parseRelease('{"tag_name":"v0.13.5","body":"notes\\n","published_at":"2026-10-16T14:00:00Z",'
          '"assets":[{"name":"nutrimeter.apk","browser_download_url":"https://x/n.apk"},{"name":"nutrimeter-staging.apk","browser_download_url":"https://x/s.apk"}]}')!;
      expect(r.version, '0.13.5');
      expect(r.notes, 'notes');
      expect(r.assets[assetFor('prod')], 'https://x/n.apk');
      expect(r.assets[assetFor('staging')], 'https://x/s.apk');
      expect(r.at!.year, 2026);
      expect(parseRelease('{"message":"Not Found"}'), isNull);
      expect(parseRelease('not json'), isNull);
    });

    test('a CI tag carries its build number, and a later build of the same version is newer', () {
      expect(tagBuild('v0.13.6-staging.100042'), 100042);
      expect(tagBuild('v0.13.6'), isNull);
      expect(tagBuild('v0.13.7-prod.100043'), 100043);
      final p = parseRelease('{"tag_name":"v0.13.7-prod.100043","assets":[]}')!;
      expect(isNewer(p, '0.13.7', 100042), isTrue);
      expect(isNewer(p, '0.13.7', 100043), isFalse);
      expect(isNewer(p, '0.13.6', 20), isTrue);
      expect(releaseLabel(p), '0.13.7 (build 100043)');
      expect(releaseLabel(parseRelease('{"tag_name":"v0.13.6","assets":[]}')!), '0.13.6');
      final r = parseRelease('{"tag_name":"v0.13.6-staging.100042","assets":[]}')!;
      expect(r.build, 100042);
      expect(isNewer(r, '0.13.6-staging', 100041), isTrue);
      expect(isNewer(r, '0.13.6-staging', 100042), isFalse);
      expect(isNewer(r, '0.13.7-staging', 1), isFalse);
    });

    test('each flavour picks the newest release with its own APK from the list, skipping drafts', () {
      String rel(String tag, String at, List<String> names, {bool draft = false}) =>
          '{"tag_name":"$tag","published_at":"$at","draft":$draft,"assets":[${names.map((n) => '{"name":"$n","browser_download_url":"https://x/$n"}').join(',')}]}';
      final body = '[${[
        rel('v0.13.8-staging.100103', '2026-10-19T10:00:00Z', ['nutrimeter-staging.apk']),
        rel('v0.13.7-prod.100102', '2026-10-18T10:00:00Z', ['nutrimeter.apk']),
        rel('v0.13.6-staging.100101', '2026-10-17T10:00:00Z', ['nutrimeter-staging.apk'], draft: true),
        rel('v0.13.6-staging.100100', '2026-10-17T09:00:00Z', ['nutrimeter-staging.apk']),
      ].join(',')}]';
      expect(pickRelease(body, 'staging')!.tag, 'v0.13.8-staging.100103');
      expect(pickRelease(body, 'prod')!.tag, 'v0.13.7-prod.100102');
      expect(pickRelease('[]', 'staging'), isNull);
      expect(pickRelease('{"message":"x"}', 'staging'), isNull);
    });

    test('version.dart says the version pubspec.yaml builds', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec)!.group(1);
      expect(appVersion, version, reason: 'bump lib/version.dart with pubspec.yaml');
    });
  });

  group('feedback', () {
    test('the build and the phone read as one line each', () {
      expect(buildLine('0.13.7-staging', 100042, 'staging'), '0.13.7 (build 100042) · staging');
      expect(buildLine('0.13.7', 100043, 'prod'), '0.13.7 (build 100043)');
      expect(buildLine('0.13.7', 0, 'prod'), '0.13.7');
      expect(deviceLine(maker: 'Google', model: 'Pixel 9 Pro', android: '16', sdk: 36), 'Google Pixel 9 Pro · Android 16 (API 36)');
      expect(deviceLine(maker: 'OnePlus', model: 'ONEPLUS A6003', android: '11', sdk: 30), 'ONEPLUS A6003 · Android 11 (API 30)');
      expect(deviceLine(), '');
    });

    test('a report opens its form with the build and the phone filled in', () {
      final u = reportUrl(Report.problem, version: '0.1.0 (build 100001)', device: 'Google Pixel 9 Pro · Android 16 (API 36)');
      expect(u.toString(), startsWith('https://github.com/$updateRepo/issues/new?'));
      expect(u.queryParameters, {'template': 'bug.yml', 'version': '0.1.0 (build 100001)', 'device': 'Google Pixel 9 Pro · Android 16 (API 36)'});
      expect(reportUrl(Report.idea, version: '0.1.0', device: 'x').queryParameters, {'template': 'feature.yml', 'version': '0.1.0'});
      expect(u.toString(), isNot(contains(' ')));
    });

    test('every field the app fills is a text field in its issue form', () {
      // URLs can only fill inputs and textareas, so a field renamed or made a dropdown would silently stay empty.
      final filled = {Report.problem: ['version', 'device'], Report.idea: ['version']};
      for (final MapEntry(key: kind, value: ids) in filled.entries) {
        final form = File('../.github/ISSUE_TEMPLATE/${reportTemplate[kind]}').readAsStringSync();
        for (final id in ids) {
          expect(RegExp('- type: (input|textarea)\\s+id: $id\\s').hasMatch(form), isTrue, reason: '$id in ${reportTemplate[kind]}');
        }
      }
    });
  });
}
