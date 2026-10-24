import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

/// Which Supabase project the app talks to. Publishable keys are meant to ship in apps: they only identify the
/// project, and row-level security decides what a signed-in user may do (`supabase/migrations/`).
class BackendConfig {
  const BackendConfig._(this.name, this.url, this.publishableKey);

  final String name;
  final String url;
  final String publishableKey;

  /// The `dev` branch: debug builds.
  static const dev = BackendConfig._(
    'dev',
    'https://enbylsacypvbzzdoapyg.supabase.co',
    'sb_publishable_p--uF-f56h9mJK-lCcc8_A_2JF_1Is8',
  );

  /// The `staging` branch: release builds of the staging flavour.
  static const staging = BackendConfig._(
    'staging',
    'https://xtcutyizsdmswptesyaq.supabase.co',
    'sb_publishable_x8jWKQxuXXi6P5hUAOpvdA_nuFXVYXm',
  );

  /// The main project: release builds of the prod flavour.
  static const prod = BackendConfig._(
    'prod',
    'https://vkhnbxizgnyfmnfphrmk.supabase.co',
    'sb_publishable_nV4WTRfWbs7W7p969Az7dQ_HDe0vgtv',
  );

  static const all = [dev, staging, prod];

  /// `--dart-define=NUTRIMETER_BACKEND=dev|staging|prod`: picks the project whatever the flavour and build mode, e.g. a
  /// debug build pointed at staging for an end-to-end test.
  static const defined = String.fromEnvironment('NUTRIMETER_BACKEND');

  /// This build's project, from [defined], else `--flavor` ([appFlavor]) and the build mode.
  static BackendConfig get current => forBuild(flavor: appFlavor, debug: kDebugMode, override: defined);

  /// [override] (when not empty) wins; otherwise debug builds use dev, and release builds their flavour's project
  /// (dev when the flavour is unknown). An unknown [override] is a build mistake and throws [ArgumentError].
  static BackendConfig forBuild({required String? flavor, required bool debug, String? override}) {
    final o = override?.trim().toLowerCase() ?? '';
    if (o.isNotEmpty) {
      return all.where((c) => c.name == o).firstOrNull ??
          (throw ArgumentError.value(override, 'NUTRIMETER_BACKEND', 'must be dev, staging or prod'));
    }
    if (debug) return dev;
    return switch (flavor) { 'prod' => prod, 'staging' => staging, _ => dev };
  }

  /// A public object's URL, e.g. a taxonomy picture in `taxonomy-art`.
  String publicUrl(String bucket, String path) =>
      '$url/storage/v1/object/public/$bucket/${path.split('/').map(Uri.encodeComponent).join('/')}';

  @override
  String toString() => 'BackendConfig($name)';
}
