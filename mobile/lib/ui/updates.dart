// The Updates panel in Settings (which build this is, whether GitHub has a newer release, and the download and install
// flow for it), the AutoUpdater, which does the same on its own whenever the app opens, the trail that points at a
// waiting update (a dot on the Targets tab and a banner at the top of Settings), and the feedback links. The pure parts
// live in logic/update.dart; the platform calls in services/platform.dart.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/store.dart';
import '../logic/update.dart';
import '../services/platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// The newer release waiting to be installed, or null when the app is current or nothing has been checked yet. Set by
/// the AutoUpdater on launch and resume and by the Updates panel; the tab dot and the banner follow it.
final updateAvailable = ValueNotifier<ReleaseInfo?>(null);

enum _Phase { checking, upToDate, available, downloading, ready, installing, offline, none, unsupported }

class UpdatePanel extends StatefulWidget {
  const UpdatePanel({super.key});

  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> {
  AppInfo? info;
  ReleaseInfo? latest;
  _Phase phase = _Phase.checking;
  double progress = 0;
  String? path;
  String? error;

  StreamSubscription<({int status, String? message})>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = UpdateBridge.statuses.listen((s) {
      if (!mounted || s.status == 0 || s.status == -1) return;
      setState(() {
        phase = _Phase.available;
        error = 'Android did not install it${s.message == null ? '' : ': ${s.message}'}.';
      });
    });
    _check();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      phase = _Phase.checking;
      error = null;
    });
    info ??= await UpdateBridge.appInfo();
    if (!mounted) return;
    if (info == null) return setState(() => phase = _Phase.unsupported);
    final got = await UpdateBridge.latest(info!.flavor);
    if (!mounted) return;
    final r = got.release;
    if (r == null) {
      if (got.reachable) updateAvailable.value = null;
      setState(() => phase = got.reachable ? _Phase.none : _Phase.offline);
      return;
    }
    latest = r;
    final newer = isNewer(r, info!.versionName, info!.versionCode);
    updateAvailable.value = newer ? r : null;
    setState(() => phase = newer ? _Phase.available : _Phase.upToDate);
  }

  Future<void> _update() async {
    final r = latest;
    if (r == null || info == null) return;
    final url = r.assets[assetFor(info!.flavor)];
    if (url == null) return setState(() => error = 'This release has no ${assetFor(info!.flavor)}.');
    if (!await UpdateBridge.canInstall()) {
      await UpdateBridge.openInstallSettings();
      if (!mounted) return;
      setState(() => error = 'Allow installs from this app, then tap Update again.');
      return;
    }
    setState(() {
      phase = _Phase.downloading;
      progress = 0;
      error = null;
    });
    final file = await UpdateBridge.download(url, assetFor(info!.flavor), (p) {
      if (mounted) setState(() => progress = p);
    });
    if (!mounted) return;
    if (file == null) {
      setState(() {
        phase = _Phase.available;
        error = 'The download failed. Check the connection and try again.';
      });
      return;
    }
    path = file;
    await _install();
  }

  Future<void> _install() async {
    if (path == null) return;
    setState(() => phase = _Phase.installing);
    await AppScope.read(context).save();
    final ok = await UpdateBridge.install(path!);
    if (!mounted) return;
    setState(() {
      phase = ok ? _Phase.ready : _Phase.available;
      if (!ok) error = 'Android would not open the installer.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = info;
    final (String status, Widget? action) = switch (phase) {
      _Phase.checking => ('Checking GitHub for a newer build…', null),
      _Phase.unsupported => ('Updates come with the Android app.', null),
      _Phase.upToDate => ('Up to date.${latest?.at == null ? '' : ' Latest release ${_date(latest!.at!)}.'}', OutlinedButton(onPressed: _check, child: const Text('Check'))),
      _Phase.offline => ('Could not reach GitHub.', OutlinedButton(onPressed: _check, child: const Text('Retry'))),
      _Phase.none => ('No release published yet.', OutlinedButton(onPressed: _check, child: const Text('Check'))),
      _Phase.available => ('${releaseLabel(latest!)} is available.', FilledButton(onPressed: _update, child: const Text('Update'))),
      _Phase.downloading => ('Downloading ${releaseLabel(latest!)}… ${(progress * 100).round()} %', null),
      _Phase.ready => ('Installing ${releaseLabel(latest!)}. The app closes and the new version opens next time.', OutlinedButton(onPressed: _install, child: const Text('Install'))),
      _Phase.installing => ('Opening the installer…', null),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i == null ? 'Version …' : 'Version ${i.build}', style: context.text.bodyLarge),
                Text(status, style: context.text.bodySmall?.copyWith(color: context.muted)),
              ]),
            ),
            if (action != null) ...[const SizedBox(width: 12), action],
          ]),
          if (phase == _Phase.downloading)
            Padding(padding: const EdgeInsets.only(top: 10), child: LinearProgressIndicator(value: progress, minHeight: 4, borderRadius: BorderRadius.circular(2))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: context.text.bodySmall?.copyWith(color: context.du.danger))),
          if (phase == _Phase.available && latest!.notes.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(latest!.notes, style: context.text.bodySmall)),
        ]),
      ),
    );
  }

  String _date(DateTime d) => '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
}

/// Keeps the app current on its own: on launch, and whenever it comes back to the front (at most every half hour), it
/// asks GitHub for a newer build of this flavour, downloads it and installs it over itself, closing the app. It waits
/// while anything is open over the home tabs (logging a food, a dialog, the scanner), so nothing being typed is lost,
/// and saves first. Every check also sets [updateAvailable], so the trail shows whenever the install does not happen
/// on its own. Installing stays off in debug builds (they are signed with the debug key and cannot take a release
/// build), until installs from this app are allowed (the Settings panel asks for that), and for the rest of the run
/// once an install has failed.
class AutoUpdater extends StatefulWidget {
  const AutoUpdater({super.key, required this.child});

  final Widget child;

  @override
  State<AutoUpdater> createState() => _AutoUpdaterState();
}

class _AutoUpdaterState extends State<AutoUpdater> with WidgetsBindingObserver {
  static const every = Duration(minutes: 30);
  DateTime? checked;
  bool busy = false, failed = false;
  StreamSubscription<({int status, String? message})>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = UpdateBridge.statuses.listen((s) {
      if (s.status != 0 && s.status != -1) failed = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }

  /// Something is open over the home tabs.
  bool get _working => !(ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _run() async {
    if (busy || !mounted) return;
    if (checked != null && DateTime.now().difference(checked!) < every) return;
    busy = true;
    try {
      checked = DateTime.now();
      final info = await UpdateBridge.appInfo();
      if (info == null) return;
      final got = await UpdateBridge.latest(info.flavor);
      final r = got.release;
      if (r == null || !isNewer(r, info.versionName, info.versionCode)) {
        if (got.reachable) updateAvailable.value = null;
        return;
      }
      updateAvailable.value = r;
      if (!kReleaseMode || failed || !mounted || _working) return;
      final url = r.assets[assetFor(info.flavor)];
      if (url == null || !await UpdateBridge.canInstall()) return;
      final path = await UpdateBridge.download(url, assetFor(info.flavor), (_) {});
      if (path == null || !mounted || _working) return;
      showToast(context, 'Updating to ${releaseLabel(r)}. The app will close; open it again.');
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || _working) return;
      await AppScope.read(context).save();
      if (!await UpdateBridge.install(path)) failed = true;
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The small amber dot that marks the trail to a waiting update.
class UpdateDot extends StatelessWidget {
  const UpdateDot({super.key, this.size = 8});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: context.du.warning, shape: BoxShape.circle));
}

/// The top of Settings while a newer build waits: what it is, and a button that scrolls down to the Updates panel.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.onGo});

  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ReleaseInfo?>(
        valueListenable: updateAvailable,
        builder: (context, r, _) {
          if (r == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              decoration: BoxDecoration(
                color: context.du.warningSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.du.warningLine, width: 0.6),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(LucideIcons.circleArrowUp, size: 22, color: context.du.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('A new update is available', style: context.text.titleMedium?.copyWith(color: context.du.warning)),
                      Text('Version ${releaseLabel(r)} is ready. Update now to get the latest changes.', style: context.text.bodySmall),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onGo,
                    style: FilledButton.styleFrom(backgroundColor: context.du.warning, foregroundColor: context.du.surface),
                    icon: const Icon(LucideIcons.arrowDown, size: 18),
                    label: const Text('Go to update'),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}

/// Problems and ideas go to GitHub Issues: each opens its form in the browser with the build (and the phone) filled in.
class FeedbackCard extends StatelessWidget {
  const FeedbackCard({super.key});

  Future<void> _open(BuildContext context, Report kind) async {
    final info = await UpdateBridge.appInfo();
    final ok = await LinkBridge.open(reportUrl(kind, version: info?.build ?? '', device: info?.device ?? ''));
    if (!ok && context.mounted) showToast(context, 'Nothing on this phone can open the link');
  }

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          ListTile(
            leading: const Icon(LucideIcons.bug),
            title: const Text('Report a problem'),
            subtitle: const Text('Opens a GitHub issue with the version and phone filled in'),
            onTap: () => _open(context, Report.problem),
          ),
          ListTile(
            leading: const Icon(LucideIcons.lightbulb),
            title: const Text('Suggest a feature'),
            onTap: () => _open(context, Report.idea),
          ),
        ]),
      );
}
