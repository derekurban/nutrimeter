import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/model.dart';
import '../data/store.dart';
import '../logic/barcode.dart';
import '../services/backend.dart';
import '../services/submissions.dart';
import 'theme.dart';
import 'widgets.dart';

/// Adds a product that is not in the catalogue yet, from photos of its package. Returns its provisional food, which
/// can be logged by weight straight away and fills in under the same id once reviewed; null if cancelled.
Future<Food?> captureProduct(BuildContext context, {Gtin? barcode, String? nameHint}) =>
    Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => CapturePage(barcode: barcode, nameHint: nameHint)));

class CapturePage extends StatefulWidget {
  const CapturePage({super.key, this.barcode, this.nameHint});

  final Gtin? barcode;
  final String? nameHint;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final _picker = ImagePicker();
  late final _name = TextEditingController(text: widget.nameHint ?? '');
  final _brand = TextEditingController();
  final _photos = <PhotoRole, XFile>{};
  final _others = <XFile>[];
  bool _noTable = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    super.dispose();
  }

  bool get _ready => _photos[PhotoRole.front] != null && (_photos[PhotoRole.nutrition] != null || _noTable);

  Future<XFile?> _pick(ImageSource source) async {
    try {
      return await _picker.pickImage(source: source, maxWidth: 2048, imageQuality: 85);
    } catch (e) {
      if (mounted) showToast(context, 'Could not open the ${source == ImageSource.camera ? 'camera' : 'photos'}: $e');
      return null;
    }
  }

  Future<void> _take(PhotoRole role, ImageSource source) async {
    final x = await _pick(source);
    if (x == null || !mounted) return;
    setState(() {
      if (role == PhotoRole.other) {
        _others.add(x);
      } else {
        _photos[role] = x;
      }
    });
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = uuidV4();
      final dir = state.dataDir;
      final photos = <PendingPhoto>[];
      if (dir != null) {
        for (final (role, x) in [
          for (final e in _photos.entries) (e.key, e.value),
          for (final x in _others) (PhotoRole.other, x),
        ]) {
          final p = await storePhoto(bytes: await x.readAsBytes(), role: role, dataDir: dir, submissionId: id);
          if (!photos.any((q) => q.sha256 == p.sha256)) photos.add(p);
        }
      }
      final code = widget.barcode;
      final name = _name.text.trim();
      final brand = _brand.text.trim();
      final provisionalId = code?.id ?? 'pending:$id';
      final food = Food(
        id: provisionalId,
        source: FoodSource.provisional,
        name: name.isEmpty ? 'New product' : name,
        brand: brand.isEmpty ? null : brand,
        barcode: code?.gtin14,
        nutrients: const {},
      );
      state.addSubmission(
        PendingSubmission(
          id: id,
          provisionalId: provisionalId,
          rawBarcode: code?.raw,
          symbology: code?.symbology.name,
          gtin: code?.gtin14,
          nameHint: name.isEmpty ? null : name,
          brandHint: brand.isEmpty ? null : brand,
          note: _noTable ? 'The package has no nutrition table.' : null,
          photos: photos,
          createdAt: DateTime.now(),
        ),
        food,
      );
      await state.save();
      unawaited(Backend.uploadPending(state));
      if (!mounted) return;
      showToast(
        context,
        Backend.account.value != null
            ? 'Saved. Sending it for review.'
            : 'Saved on this phone. Sign in under Targets → Food review to send it for review.',
      );
      Navigator.of(context).pop(food);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save the photos: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.barcode;
    return Scaffold(
      appBar: AppBar(title: const Text('Add a product')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
        Text(
          code == null ? 'This product is not in your foods yet.' : 'No food has the barcode ${code.raw} yet.',
          style: context.text.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Photograph the package. It is reviewed from these photos and its nutrition fills in later; '
          'you can log it by weight straight away.',
          style: TextStyle(color: context.muted),
        ),
        const SizedBox(height: 16),
        _PhotoSlot(
          title: 'Front',
          hint: 'Name, brand and net quantity',
          photo: _photos[PhotoRole.front],
          onTake: (s) => _take(PhotoRole.front, s),
          onRemove: () => setState(() => _photos.remove(PhotoRole.front)),
        ),
        _PhotoSlot(
          title: 'Nutrition Facts table',
          hint: _noTable ? 'Not needed: this product has no table' : 'The whole table, flat and in focus',
          photo: _photos[PhotoRole.nutrition],
          enabled: !_noTable,
          onTake: (s) => _take(PhotoRole.nutrition, s),
          onRemove: () => setState(() => _photos.remove(PhotoRole.nutrition)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('This product has no nutrition table'),
          value: _noTable,
          onChanged: (v) => setState(() {
            _noTable = v ?? false;
            if (_noTable) _photos.remove(PhotoRole.nutrition);
          }),
        ),
        _PhotoSlot(
          title: 'Ingredients',
          hint: 'Optional',
          photo: _photos[PhotoRole.ingredients],
          onTake: (s) => _take(PhotoRole.ingredients, s),
          onRemove: () => setState(() => _photos.remove(PhotoRole.ingredients)),
        ),
        for (var i = 0; i < _others.length; i++)
          _PhotoSlot(
            title: 'Other photo',
            hint: 'Optional',
            photo: _others[i],
            onTake: (s) async {
              final x = await _pick(s);
              if (x != null && mounted) setState(() => _others[i] = x);
            },
            onRemove: () => setState(() => _others.removeAt(i)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('Add another photo'),
            onPressed: () => _take(PhotoRole.other, ImageSource.camera),
          ),
        ),
        const SectionTitle('Optional hints'),
        TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 10),
        TextField(controller: _brand, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Brand')),
        ValueListenableBuilder(
          valueListenable: Backend.account,
          builder: (context, account, _) => account != null
              ? const SizedBox.shrink()
              : Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.du.warningSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.du.warningLine, width: 0.6),
                  ),
                  child: const Text('You are not signed in. The product is kept on this phone; sign in under '
                      'Targets → Food review to send it for review.'),
                ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: context.du.danger))),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _ready && !_saving ? _save : null,
            child: Text(_saving ? 'Saving…' : _ready ? 'Save and log' : 'Add the front and nutrition photos'),
          ),
        ),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.title, required this.hint, required this.photo, required this.onTake, required this.onRemove, this.enabled = true});

  final String title;
  final String hint;
  final XFile? photo;
  final bool enabled;
  final void Function(ImageSource) onTake;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final p = photo;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: du.sunk, borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: p == null
                ? Icon(LucideIcons.camera, color: enabled ? du.inkSecondary : du.line)
                : Image.file(File(p.path), fit: BoxFit.cover, cacheWidth: 192),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? null : context.muted)),
              Text(hint, style: TextStyle(color: context.muted, fontSize: 12.5)),
            ]),
          ),
          if (enabled) ...[
            IconButton(icon: const Icon(LucideIcons.image), tooltip: 'Choose from photos', onPressed: () => onTake(ImageSource.gallery)),
            if (p == null)
              IconButton(icon: const Icon(LucideIcons.camera), tooltip: 'Take photo', onPressed: () => onTake(ImageSource.camera))
            else ...[
              IconButton(icon: const Icon(LucideIcons.refreshCw), tooltip: 'Retake', onPressed: () => onTake(ImageSource.camera)),
              IconButton(icon: const Icon(LucideIcons.x), tooltip: 'Remove', onPressed: onRemove),
            ],
          ],
        ]),
      ),
    );
  }
}
