// The food review backend (Supabase), from the app's side: signing in as the one user, syncing the published
// catalogue into the app's data file, and sending captured products to the review queue. Everything here is optional:
// without a session (or a connection) the app keeps working from its own data.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/store.dart';
import 'backend_config.dart';
import 'catalogue.dart';
import 'submissions.dart';

class Backend {
  Backend._();

  static final config = BackendConfig.current;

  static SupabaseClient? _client;

  /// Null until [start] has initialised Supabase (and always in tests).
  static SupabaseClient? get client => _client;

  /// Null while starting, true once [client] can be used, false if Supabase could not be initialised.
  static final ready = ValueNotifier<bool?>(null);

  /// The signed-in account's email, or null when signed out.
  static final account = ValueNotifier<String?>(null);

  /// A catalogue download is running.
  static final syncing = ValueNotifier<bool>(false);

  /// Why the last catalogue download failed, or null.
  static final syncError = ValueNotifier<String?>(null);

  /// How often the catalogue is downloaded on launch and resume, normally.
  static const every = Duration(minutes: 30);

  /// How often while products captured on this phone wait for review ([AppState.awaitingReview]): in effect every
  /// launch and resume, so an accepted product shows up when the app is reopened. The short floor only stops a burst
  /// of downloads while photos are being taken (the camera sends the app to the background and back).
  static const everyWhileAwaiting = Duration(seconds: 15);

  static DateTime? _synced;
  static Future<void>? _download;
  static bool _uploading = false;
  static bool _again = false;

  /// Signed in, so the catalogue can be downloaded.
  static bool get signedIn => _client?.auth.currentUser != null;

  /// Initialises Supabase (restoring a saved session) and syncs. Called once, after the first frame is up.
  static Future<void> start(AppState state) async {
    if (_client != null) return;
    try {
      await Supabase.initialize(url: config.url, publishableKey: config.publishableKey);
      _client = Supabase.instance.client;
    } catch (e) {
      debugPrint('Food review backend unavailable: $e');
      ready.value = false;
      return;
    }
    final auth = _client!.auth;
    account.value = auth.currentUser?.email;
    ready.value = true;
    auth.onAuthStateChange.listen((s) {
      account.value = s.session?.user.email;
      if (s.event == AuthChangeEvent.signedIn) sync(state, force: true);
    }, onError: (Object e) => debugPrint('Auth: $e'));
    await sync(state);
  }

  /// Signing in fires [AuthChangeEvent.signedIn], which syncs.
  static Future<void> signIn(String email, String password) async {
    final c = _client ?? (throw StateError('The food review service is not available.'));
    await c.auth.signInWithPassword(email: email.trim(), password: password);
    account.value = c.auth.currentUser?.email;
  }

  static Future<void> signOut() async {
    final c = _client;
    if (c == null) return;
    try {
      await c.auth.signOut();
    } finally {
      account.value = c.auth.currentUser?.email;
    }
  }

  /// On launch, on coming back to the front and after signing in: sends anything waiting to upload, and downloads the
  /// catalogue when it is [due]. A call during a download waits for that download instead of starting another. Never
  /// throws: a failure is in [syncError].
  static Future<void> sync(AppState state, {bool force = false}) {
    final c = _client;
    if (c == null || c.auth.currentUser == null) return Future.value();
    unawaited(uploadPending(state));
    final running = _download;
    if (running != null) return running;
    if (!due(last: _synced, now: DateTime.now(), force: force, awaitingReview: state.awaitingReview)) return Future.value();
    return _download = _fetch(c, state).whenComplete(() => _download = null);
  }

  /// Whether to download the catalogue now: when forced, when it never was, and otherwise [every] half hour, or every
  /// [everyWhileAwaiting] while products wait for review.
  @visibleForTesting
  static bool due({required DateTime? last, required DateTime now, bool force = false, bool awaitingReview = false}) =>
      force || last == null || now.difference(last) >= (awaitingReview ? everyWhileAwaiting : every);

  static Future<void> _fetch(SupabaseClient c, AppState state) async {
    syncing.value = true;
    try {
      state.setCatalogue(await fetchCatalogue(c, config));
      _synced = DateTime.now();
      syncError.value = null;
    } catch (e) {
      syncError.value = describeError(e);
    } finally {
      syncing.value = false;
    }
  }

  /// Uploads every pending submission, one at a time, saving progress after each step. Failures stay pending (with
  /// their reason) and are retried on the next sync.
  static Future<void> uploadPending(AppState state) async {
    final c = _client;
    final dir = state.dataDir;
    if (c == null || c.auth.currentUser == null || dir == null) return;
    if (_uploading) {
      _again = true;
      return;
    }
    _uploading = true;
    try {
      do {
        _again = false;
        for (final pending in [...state.pendingSubmissions]) {
          try {
            await uploadSubmission(c, pending.copyWith(error: () => null), dataDir: dir, onProgress: state.updateSubmission);
            state.removeSubmission(pending.id);
          } catch (e) {
            final current = state.pendingSubmissions.where((s) => s.id == pending.id).firstOrNull;
            if (current != null) state.updateSubmission(current.copyWith(error: () => describeError(e)));
            if (_offline(e)) return;
          }
        }
      } while (_again);
    } finally {
      _uploading = false;
    }
  }

  static bool _offline(Object e) => e is SocketException || e is TimeoutException || e.toString().contains('SocketException');

  /// A short, readable reason for a failed request.
  static String describeError(Object e) {
    if (_offline(e)) return 'Offline';
    return switch (e) {
      AuthException(:final message) => message,
      PostgrestException(:final message) => message,
      StorageException(:final message) => message,
      StateError(:final message) => message,
      _ => '$e',
    };
  }
}
