// Food review from the app's side: the Settings card to sign in (which publishes the products reviewed on this phone
// and syncs the catalogue), and the history of submissions sent from this account with their status.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/label_review.dart';
import '../data/store.dart';
import '../services/backend.dart';
import '../services/backend_config.dart';
import '../services/submissions.dart';
import 'theme.dart';
import 'widgets.dart';

/// How a submission's status reads to the user.
String submissionStatusLabel(String status) => switch (status) {
      'uploading' => 'Uploading',
      'queued' => 'Queued',
      'claimed' || 'drafted' => 'In review',
      'accepted' => 'Accepted',
      'rejected' => 'Rejected',
      // The desktop review queue was retired: a submission still waiting in it was closed, unreviewed.
      'closed' => 'Closed',
      _ => status,
    };

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]}${t.year == DateTime.now().year ? '' : ' ${t.year}'}';
}

/// Settings → Food review: sign in or out, the catalogue's sync state, and the way to the submissions list.
class FoodReviewCard extends StatelessWidget {
  const FoodReviewCard({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: Backend.ready,
        builder: (context, ready, _) => ValueListenableBuilder(
          valueListenable: Backend.account,
          builder: (context, account, _) => ready != true
              ? Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(ready == null ? 'Connecting to food review…' : 'Food review is not available in this build.',
                        style: TextStyle(color: context.muted)),
                  ),
                )
              : account == null
                  ? const _SignIn()
                  : _SignedIn(account: account),
        ),
      );
}

class _SignIn extends StatefulWidget {
  const _SignIn();

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Backend.signIn(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = Backend.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _unpublished(AppScope.of(context));
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Sign in to get the reviewed catalogue on this phone and to publish the products you add from their labels. '
            'Everything else works without an account.',
            style: TextStyle(color: context.muted),
          ),
          if (Backend.config != BackendConfig.prod)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('This build uses the ${Backend.config.name} backend, which has its own accounts.',
                  style: TextStyle(color: context.muted)),
            ),
          if (waiting > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('$waiting ${waiting == 1 ? 'product you added is' : 'products you added are'} in your foods, waiting to be published.',
                  style: TextStyle(color: context.du.warning)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: context.du.danger))),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Signing in…' : 'Sign in')),
          ),
        ]),
      ),
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.account});

  final String account;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final synced = state.catalogue.syncedAt;
    final count = state.catalogue.records.length;
    return Panel(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          leading: const Icon(LucideIcons.user),
          title: Text(account, maxLines: 1, overflow: TextOverflow.ellipsis),
          // Any project but the real one is named, so a test build is never mistaken for it.
          subtitle: Text(Backend.config == BackendConfig.prod ? 'Signed in' : 'Signed in · ${Backend.config.name} backend'),
          trailing: TextButton(
            onPressed: () async {
              try {
                await Backend.signOut();
              } catch (e) {
                if (context.mounted) showToast(context, 'Could not sign out: ${Backend.describeError(e)}');
              }
            },
            child: const Text('Sign out'),
          ),
        ),
        ListTile(
          leading: const Icon(LucideIcons.inbox),
          title: const Text('Submissions'),
          subtitle: const Text('What was sent from this account, with its status'),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubmissionsPage())),
        ),
        ValueListenableBuilder(
          valueListenable: Backend.syncing,
          builder: (context, syncing, _) => ValueListenableBuilder(
            valueListenable: Backend.syncError,
            builder: (context, error, _) => ListTile(
              leading: const Icon(LucideIcons.refreshCw),
              title: Text('$count reviewed ${count == 1 ? 'food' : 'foods'}'),
              subtitle: Text(
                syncing
                    ? 'Syncing…'
                    : error != null
                        ? 'Sync failed: $error'
                        : synced == null
                            ? 'Not synced yet'
                            : 'Synced ${_ago(synced)}',
                style: error != null && !syncing ? TextStyle(color: context.du.danger) : null,
              ),
              trailing: OutlinedButton(
                onPressed: syncing ? null : () => Backend.sync(state, force: true),
                child: const Text('Sync'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Accepted label reviews not published yet (they publish on the next sync while signed in).
int _unpublished(AppState state) => state.labelReviews.values.where((r) => r.stage == ReviewStage.accepted && !r.published).length;

/// The history of what was sent from this account, newest first, with its status: products published from the phone's
/// label review, and those sent to the retired desktop review queue (closed if they were still waiting in it).
class SubmissionsPage extends StatefulWidget {
  const SubmissionsPage({super.key});

  @override
  State<SubmissionsPage> createState() => _SubmissionsPageState();
}

class _SubmissionsPageState extends State<SubmissionsPage> {
  List<SubmissionView>? _remote;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = Backend.client;
    if (c == null || Backend.account.value == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final got = await fetchSubmissions(c);
      if (mounted) setState(() => _remote = got);
    } catch (e) {
      if (mounted) setState(() => _error = Backend.describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = _remote ?? const <SubmissionView>[];
    final signedIn = Backend.account.value != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Submissions')),
      body: RefreshIndicator(
        onRefresh: signedIn ? _load : () async {},
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 40), children: [
          if (_loading && _remote == null) const LinearProgressIndicator(),
          if (!signedIn)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Sign in under Targets → Food review to see what was sent and its status.', style: TextStyle(color: context.muted)),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: context.du.danger))),
          if (remote.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                'Products now reach the catalogue from your label review on this phone. The desktop review queue is retired: '
                'what was still waiting in it is closed.',
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ),
            Panel(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [for (final s in remote) _RemoteTile(submission: s)]),
            ),
          ],
          if (signedIn && remote.isEmpty && !_loading && _error == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Nothing yet. When a scan or search finds nothing, add the product from its label and it shows up here once it is sent.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted),
              ),
            ),
        ]),
      ),
    );
  }
}

class _RemoteTile extends StatelessWidget {
  const _RemoteTile({required this.submission});

  final SubmissionView submission;

  @override
  Widget build(BuildContext context) {
    final s = submission;
    final state = AppScope.of(context);
    final food = state.resolve(s.recordId ?? s.provisionalId);
    final name = s.status == 'accepted' && food != null ? food.name : s.nameHint ?? food?.name ?? 'New product';
    final brand = s.status == 'accepted' && food != null ? food.brand : s.brandHint;
    final du = context.du;
    final colour = switch (s.status) {
      'accepted' => du.accentText,
      'rejected' => du.danger,
      _ => context.muted,
    };
    return ListTile(
      leading: Icon(switch (s.status) {
        'accepted' => LucideIcons.circleCheck,
        'rejected' => LucideIcons.circleX,
        'closed' => LucideIcons.circleMinus,
        'claimed' || 'drafted' => LucideIcons.eye,
        _ => LucideIcons.clock,
      }, color: colour),
      title: Text([name, ?brand].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          [submissionStatusLabel(s.status), ?s.gtin, _ago(s.createdAt)].join(' · '),
          style: TextStyle(color: colour),
        ),
        if (s.status == 'rejected' && (s.comment?.isNotEmpty ?? false))
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${s.comment}”', style: TextStyle(color: du.ink))),
      ]),
    );
  }
}
