import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a label photo shows (`submission_photos.role`).
enum PhotoRole { front, nutrition, ingredients, other }

/// A photo waiting on the device, copied into the app's storage so it survives restarts.
class PendingPhoto {
  const PendingPhoto({
    required this.role,
    required this.file,
    required this.sha256,
    required this.contentType,
    this.width,
    this.height,
    required this.bytes,
    this.uploaded = false,
  });

  final PhotoRole role;

  /// Path relative to the app's data directory, e.g. `submissions/<id>/<sha256>.jpg`.
  final String file;
  final String sha256;
  final String contentType;
  final int? width;
  final int? height;
  final int bytes;

  /// The object is in storage and its `submission_photos` row exists.
  final bool uploaded;

  String get extension => switch (contentType) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };

  /// Where it goes in the private `label-photos` bucket. Content-addressed, so a retry writes the same object.
  String objectPath(String uid, String submissionId) => '$uid/$submissionId/$sha256.$extension';

  PendingPhoto copyWith({bool? uploaded}) => PendingPhoto(
      role: role, file: file, sha256: sha256, contentType: contentType, width: width, height: height, bytes: bytes, uploaded: uploaded ?? this.uploaded);

  Map<String, Object?> toJson() => {
        'role': role.name,
        'file': file,
        'sha256': sha256,
        'contentType': contentType,
        'width': ?width,
        'height': ?height,
        'bytes': bytes,
        if (uploaded) 'uploaded': true,
      };

  factory PendingPhoto.fromJson(Map<String, dynamic> j) => PendingPhoto(
        role: PhotoRole.values.byName(j['role'] as String),
        file: j['file'] as String,
        sha256: j['sha256'] as String,
        contentType: j['contentType'] as String? ?? 'image/jpeg',
        width: j['width'] as int?,
        height: j['height'] as int?,
        bytes: j['bytes'] as int,
        uploaded: j['uploaded'] as bool? ?? false,
      );
}

/// A product captured on the device that has not reached the review queue yet. Its [id] is the submission's id,
/// minted here so every step of the upload can be retried without creating duplicates.
class PendingSubmission {
  const PendingSubmission({
    required this.id,
    required this.provisionalId,
    this.rawBarcode,
    this.symbology,
    this.gtin,
    this.nameHint,
    this.brandHint,
    this.note,
    this.photos = const [],
    this.created = false,
    required this.createdAt,
    this.error,
  });

  final String id;

  /// The food id the diary logs against meanwhile: `gtin:<14>` or `pending:<uuid>`.
  final String provisionalId;
  final String? rawBarcode;
  final String? symbology;
  final String? gtin;
  final String? nameHint;
  final String? brandHint;
  final String? note;
  final List<PendingPhoto> photos;

  /// The `submissions` row exists.
  final bool created;
  final DateTime createdAt;

  /// Why the last attempt stopped, for the submissions screen.
  final String? error;

  PendingSubmission copyWith({List<PendingPhoto>? photos, bool? created, String? Function()? error}) => PendingSubmission(
        id: id,
        provisionalId: provisionalId,
        rawBarcode: rawBarcode,
        symbology: symbology,
        gtin: gtin,
        nameHint: nameHint,
        brandHint: brandHint,
        note: note,
        photos: photos ?? this.photos,
        created: created ?? this.created,
        createdAt: createdAt,
        error: error != null ? error() : this.error,
      );

  /// The `submissions` insert. Owner, source and status are left to the database's defaults, which its
  /// row-level security checks.
  Map<String, Object?> toRow() => {
        'id': id,
        'raw_barcode': rawBarcode,
        'symbology': symbology,
        'gtin': gtin,
        'provisional_id': provisionalId,
        'name_hint': nameHint,
        'brand_hint': brandHint,
        'note': note,
      };

  Map<String, Object?> toJson() => {
        'id': id,
        'provisionalId': provisionalId,
        'rawBarcode': ?rawBarcode,
        'symbology': ?symbology,
        'gtin': ?gtin,
        'nameHint': ?nameHint,
        'brandHint': ?brandHint,
        'note': ?note,
        'photos': [for (final p in photos) p.toJson()],
        if (created) 'created': true,
        'createdAt': createdAt.toIso8601String(),
        'error': ?error,
      };

  factory PendingSubmission.fromJson(Map<String, dynamic> j) => PendingSubmission(
        id: j['id'] as String,
        provisionalId: j['provisionalId'] as String,
        rawBarcode: j['rawBarcode'] as String?,
        symbology: j['symbology'] as String?,
        gtin: j['gtin'] as String?,
        nameHint: j['nameHint'] as String?,
        brandHint: j['brandHint'] as String?,
        note: j['note'] as String?,
        photos: [for (final p in (j['photos'] as List? ?? const [])) PendingPhoto.fromJson((p as Map).cast<String, dynamic>())],
        created: j['created'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
        error: j['error'] as String?,
      );
}

/// JPEG, PNG or WebP from the file's first bytes; null for anything the bucket would refuse.
String? imageType(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length > 12 && String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') return 'image/webp';
  return null;
}

/// Copies a photo into `submissions/<submissionId>/` under [dataDir] and describes it. Throws [FormatException]
/// for a file that is not a JPEG, PNG or WebP.
Future<PendingPhoto> storePhoto({
  required Uint8List bytes,
  required PhotoRole role,
  required Directory dataDir,
  required String submissionId,
}) async {
  final type = imageType(bytes) ?? (throw const FormatException('Only JPEG, PNG and WebP photos can be sent.'));
  final hash = sha256.convert(bytes).toString();
  int? width, height;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    width = descriptor.width;
    height = descriptor.height;
    descriptor.dispose();
    buffer.dispose();
  } catch (_) {
    // Dimensions are optional in the database.
  }
  final photo = PendingPhoto(role: role, file: '', sha256: hash, contentType: type, width: width, height: height, bytes: bytes.length);
  final rel = 'submissions/$submissionId/$hash.${photo.extension}';
  final file = File('${dataDir.path}/$rel');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return PendingPhoto(role: role, file: rel, sha256: hash, contentType: type, width: width, height: height, bytes: bytes.length);
}

bool _duplicateRow(PostgrestException e) => e.code == '23505';

bool _duplicateObject(StorageException e) =>
    e.statusCode == '409' || e.error == 'Duplicate' || e.message.toLowerCase().contains('already exists');

/// Sends one submission to the review queue: the `submissions` row, then each photo (object, then its row), then
/// `queue_submission`. Every step is idempotent, so an interrupted upload simply runs again; [onProgress] gets the
/// submission after each step so the progress can be saved. Photos whose files are gone are dropped.
Future<PendingSubmission> uploadSubmission(
  SupabaseClient c,
  PendingSubmission submission, {
  required Directory dataDir,
  required void Function(PendingSubmission) onProgress,
}) async {
  final uid = c.auth.currentUser?.id;
  if (uid == null) throw StateError('Sign in to send products for review.');
  var s = submission;

  if (!s.created) {
    try {
      await c.from('submissions').insert(s.toRow());
    } on PostgrestException catch (e) {
      if (!_duplicateRow(e)) rethrow;
    }
    s = s.copyWith(created: true);
    onProgress(s);
  }

  for (final photo in s.photos.where((p) => !p.uploaded).toList()) {
    final file = File('${dataDir.path}/${photo.file}');
    if (!await file.exists()) {
      s = s.copyWith(photos: [for (final p in s.photos) if (p.sha256 != photo.sha256) p]);
      onProgress(s);
      continue;
    }
    final path = photo.objectPath(uid, s.id);
    try {
      await c.storage.from('label-photos').uploadBinary(path, await file.readAsBytes(),
          fileOptions: FileOptions(contentType: photo.contentType, upsert: false));
    } on StorageException catch (e) {
      if (!_duplicateObject(e)) rethrow;
    }
    try {
      await c.from('submission_photos').insert({
        'submission_id': s.id,
        'role': photo.role.name,
        'object_path': path,
        'sha256': photo.sha256,
        'content_type': photo.contentType,
        'width': photo.width,
        'height': photo.height,
        'bytes': photo.bytes,
      });
    } on PostgrestException catch (e) {
      if (!_duplicateRow(e)) rethrow;
    }
    s = s.copyWith(photos: [for (final p in s.photos) p.sha256 == photo.sha256 ? p.copyWith(uploaded: true) : p]);
    onProgress(s);
  }

  try {
    await c.rpc('queue_submission', params: {'p_submission': s.id});
  } on PostgrestException catch (e) {
    // An earlier attempt queued it and lost the answer.
    if (!(e.code == '23514' && e.message.contains('already'))) rethrow;
  }
  return s;
}

/// A submission as the backend sees it, for the submissions screen.
class SubmissionView {
  const SubmissionView({
    required this.id,
    required this.provisionalId,
    this.nameHint,
    this.brandHint,
    this.gtin,
    required this.status,
    this.recordId,
    required this.createdAt,
    this.comment,
  });

  final String id;
  final String provisionalId;
  final String? nameHint;
  final String? brandHint;
  final String? gtin;

  /// `uploading`, `queued`, `claimed`, `drafted`, `accepted` or `rejected`.
  final String status;
  final String? recordId;
  final DateTime createdAt;

  /// The reviewer's comment on the latest review, shown for rejected submissions.
  final String? comment;
}

/// Joins submissions with their latest review (rows ordered by `created_at`, newest first or not).
List<SubmissionView> submissionViews(List<Map<String, dynamic>> submissions, List<Map<String, dynamic>> reviews) {
  final latest = <String, Map<String, dynamic>>{};
  for (final r in reviews) {
    final id = r['submission_id'] as String;
    final seen = latest[id];
    if (seen == null || DateTime.parse(r['created_at'] as String).isAfter(DateTime.parse(seen['created_at'] as String))) latest[id] = r;
  }
  return [
    for (final s in submissions)
      SubmissionView(
        id: s['id'] as String,
        provisionalId: s['provisional_id'] as String,
        nameHint: s['name_hint'] as String?,
        brandHint: s['brand_hint'] as String?,
        gtin: s['gtin'] as String?,
        status: s['status'] as String,
        recordId: s['record_id'] as String?,
        createdAt: DateTime.parse(s['created_at'] as String),
        comment: latest[s['id']]?['comment'] as String?,
      ),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

/// The signed-in user's submissions with their latest review.
Future<List<SubmissionView>> fetchSubmissions(SupabaseClient c) async {
  final subs = await c
      .from('submissions')
      .select('id,provisional_id,name_hint,brand_hint,gtin,status,record_id,created_at')
      .order('created_at', ascending: false)
      .limit(300);
  final ids = [for (final s in subs) s['id'] as String];
  final reviews = <Map<String, dynamic>>[];
  for (var i = 0; i < ids.length; i += 100) {
    reviews.addAll(await c
        .from('reviews')
        .select('submission_id,decision,comment,created_at')
        .inFilter('submission_id', ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100)));
  }
  return submissionViews(subs, reviews);
}
