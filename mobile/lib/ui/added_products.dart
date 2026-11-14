// Products added from their labels on this phone: the banner on the diary for those still being read or waiting for
// you, and the full list (Targets → Food review) with what was published.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/label_review.dart';
import '../data/store.dart';
import '../logic/label_reading.dart';
import '../services/backend.dart';
import '../services/label_pipeline.dart';
import '../services/reading_settings.dart';
import 'reading_settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Where a review stands, in a few words, and whether it needs the person.
({String text, bool needsYou}) reviewStatus(AppState state, LabelReview r) {
  final bar = state.readingSettings.bar;
  switch (r.stage) {
    case ReviewStage.photos:
      if (r.photos.isEmpty) return (text: 'Photos started', needsYou: true);
      return (text: ApiKeys.present.isEmpty ? 'Photos taken · add an API key to read it' : 'Photos taken · ready to read', needsYou: true);
    case ReviewStage.reading:
      return (text: 'Being read…', needsYou: false);
    case ReviewStage.rechecking:
      return (text: 'Reading your notes…', needsYou: false);
    case ReviewStage.paused:
      return (text: 'Waiting for you: a photo is hard to read', needsYou: true);
    case ReviewStage.stopped:
      return (text: 'Stopped: ${r.error ?? 'a step did not finish'}', needsYou: true);
    case ReviewStage.review:
      final lines = LabelPipeline.linesOf(state, r).lines;
      final open = lines.where((l) => l.needsYou(bar)).length;
      final conf = overallConfidence(lines);
      return (text: open == 0 ? 'Ready for you · $conf%, nothing in doubt' : 'Ready for you · $open to look at · $conf%', needsYou: true);
    case ReviewStage.accepted:
      return (
        text: r.published
            ? 'Published'
            : Backend.account.value == null
                ? 'In your foods · sign in to publish'
                : r.publishError != null
                    ? 'Not published yet: ${r.publishError}'
                    : 'Publishing…',
        needsYou: false,
      );
  }
}

/// On the diary: products still being read or waiting for the person.
class OpenReviewsBanner extends StatelessWidget {
  const OpenReviewsBanner({super.key, required this.onOpen});

  final void Function(LabelReview) onOpen;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final open = state.openReviews;
    if (open.isEmpty) return const SizedBox.shrink();
    final du = context.du;
    return ValueListenableBuilder(
      valueListenable: LabelPipeline.running,
      builder: (context, running, _) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Panel(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final r in open)
              Builder(builder: (context) {
                final s = reviewStatus(state, r);
                final busy = running.contains(r.id);
                return ListTile(
                  leading: busy
                      ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2, color: du.accentStrong))
                      : Icon(s.needsYou ? LucideIcons.scanEye : LucideIcons.hourglass, color: s.needsYou ? du.warning : du.inkSecondary),
                  title: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.needsYou ? du.warning : context.muted)),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => onOpen(r),
                );
              }),
          ]),
        ),
      ),
    );
  }
}

/// Every product added from its label on this phone.
class AddedProductsPage extends StatelessWidget {
  const AddedProductsPage({super.key, required this.onOpen});

  final void Function(BuildContext, LabelReview) onOpen;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final all = state.labelReviews.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final du = context.du;
    return Scaffold(
      appBar: AppBar(title: const Text('Added from labels')),
      body: RefreshIndicator(
        onRefresh: () => Backend.publishReviews(state),
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 40), children: [
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Nothing yet. When a scan finds nothing, add the product from its label and it shows up here.',
                  textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
            )
          else
            Panel(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final r in all)
                  Builder(builder: (context) {
                    final s = reviewStatus(state, r);
                    final accepted = r.stage == ReviewStage.accepted;
                    return ListTile(
                      leading: Icon(
                        accepted ? (r.published ? LucideIcons.circleCheck : LucideIcons.cloudUpload) : LucideIcons.scanEye,
                        color: accepted ? (r.published ? du.accentText : du.inkSecondary) : du.warning,
                      ),
                      title: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${s.text}\n${[?r.rawBarcode, formatUsd(r.costUsd)].join(' · ')}'),
                      isThreeLine: true,
                      onTap: accepted ? null : () => onOpen(context, r),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(LucideIcons.ellipsisVertical),
                        onSelected: (a) async {
                          if (a == 'publish') {
                            unawaited(Backend.publishReviews(state));
                          } else if (a == 'discard' &&
                              await confirmDialog(context, 'Discard ${r.displayName}?',
                                  accepted ? 'Its photos and readings are deleted from this phone. The product stays in your foods.' : 'Its photos and readings are deleted from this phone.',
                                  action: 'Discard')) {
                            state.removeReview(r.id);
                          }
                        },
                        itemBuilder: (_) => [
                          if (accepted && !r.published) const PopupMenuItem(value: 'publish', child: Text('Publish now')),
                          if (!accepted || r.published) const PopupMenuItem(value: 'discard', child: Text('Discard')),
                        ],
                      ),
                    );
                  }),
              ]),
            ),
        ]),
      ),
    );
  }
}
