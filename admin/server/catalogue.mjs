// Every read and write the admin makes, through the service-role client. Writes go through the database
// functions so each one is checked and logged with its actor.
import crypto from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

export function createCatalogue(config) {
  const db = createClient(config.supabaseUrl, config.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const must = ({ data, error }, what) => {
    if (error) throw new Error(`${what}: ${error.message}`);
    return data;
  };
  const rpc = async (fn, args) => must(await db.rpc(fn, args), fn);

  async function listSubmissions({ status } = {}) {
    let q = db
      .from('submissions')
      .select('*, photos:submission_photos(id, role, object_path), extractions(id, attempt, created_at), reviews(id, decision, comment, created_at)')
      .order('created_at', { ascending: false })
      .limit(200);
    if (status) q = q.in('status', status.split(','));
    return must(await q, 'list submissions');
  }

  async function getSubmission(id) {
    const s = must(await db.from('submissions').select('*').eq('id', id).single(), 'submission');
    const [photos, extractions, reviews, events] = await Promise.all([
      db.from('submission_photos').select('*').eq('submission_id', id).order('created_at'),
      db.from('extractions').select('*').eq('submission_id', id).order('attempt'),
      db.from('reviews').select('*').eq('submission_id', id).order('created_at'),
      db.from('events').select('*').or(`entity_id.eq.${id},data->>submission_id.eq.${id}`).order('id'),
    ]);
    return {
      submission: s,
      photos: must(photos, 'photos'),
      extractions: must(extractions, 'extractions'),
      reviews: must(reviews, 'reviews'),
      events: must(events, 'events'),
    };
  }

  /** The whole taxonomy, plus categories flattened with their path for prompts and pickers. */
  async function taxonomy() {
    const [g, sg, c] = await Promise.all([
      db.from('food_groups').select('id, name, position, image_path, image_alt').order('position'),
      db.from('food_subgroups').select('id, group_id, name, position, image_path, image_alt').order('position'),
      db.from('food_categories').select('id, subgroup_id, name, position, note, image_path, image_alt').order('position'),
    ]);
    const groups = must(g, 'groups');
    const subgroups = must(sg, 'subgroups');
    const raw = must(c, 'categories');
    const groupById = new Map(groups.map((x) => [x.id, x]));
    const subById = new Map(subgroups.map((x) => [x.id, x]));
    const categories = raw.map((x) => {
      const sub = subById.get(x.subgroup_id);
      const group = groupById.get(sub.group_id);
      return { ...x, subgroup: sub.name, group_id: group.id, group: group.name, path: `${group.name} › ${sub.name} › ${x.name}` };
    });
    return { groups, subgroups, categories };
  }

  /** Every published record, flattened from its current revision for lists and search. */
  async function listRecords() {
    const rows = must(await db
      .from('records')
      .select('id, role, category_id, created_at, updated_at, current:record_revisions!records_current_revision_id_fkey(id, data, created_at), revisions:record_revisions!record_revisions_record_id_fkey(count)')
      .order('updated_at', { ascending: false })
      .limit(10000), 'records');
    return rows.map((r) => ({
      id: r.id,
      role: r.role,
      category_id: r.category_id,
      created_at: r.created_at,
      updated_at: r.updated_at,
      revisions: r.revisions?.[0]?.count ?? 0,
      name: r.current?.data?.name ?? null,
      brand: r.current?.data?.brand ?? null,
      barcodes: r.current?.data?.barcodes ?? [],
      package: r.current?.data?.package ?? null,
      kcal: r.current?.data?.profiles?.find((p) => p.id === r.current?.data?.default_profile)?.per_100g?.energy
        ?? r.current?.data?.profiles?.[0]?.per_100g?.energy ?? null,
    }));
  }

  /** One record with its revisions, the submissions behind it, the ids that alias to it and its event log. */
  async function getRecord(id) {
    const record = must(await db.from('records').select('*').eq('id', id).maybeSingle(), 'record');
    if (!record) return null;
    const [revisions, submissions, aliases, events] = await Promise.all([
      db.from('record_revisions').select('*, review:reviews(id, reviewer, comment, edits, created_at)').eq('record_id', id).order('created_at', { ascending: false }),
      db.from('submissions').select('id, status, source, raw_barcode, name_hint, created_at, photos:submission_photos(id, role)').eq('record_id', id).order('created_at', { ascending: false }),
      db.from('aliases').select('*').eq('to_id', id),
      db.from('events').select('*').eq('entity', 'records').eq('entity_id', id).order('id'),
    ]);
    return {
      record,
      revisions: must(revisions, 'revisions'),
      submissions: must(submissions, 'submissions'),
      aliases: must(aliases, 'aliases'),
      events: must(events, 'events'),
    };
  }

  /** Illustrations, newest first: by status, by node, or both. */
  async function listArt({ status, level, nodeId, limit = 500 } = {}) {
    let q = db.from('taxonomy_art').select('*').order('created_at', { ascending: false }).limit(limit);
    if (status) q = q.in('status', status.split(','));
    if (level) q = q.eq('level', level);
    if (nodeId) q = q.eq('node_id', nodeId);
    return must(await q, 'illustrations');
  }

  async function uploadArt(objectPath, bytes, contentType) {
    const { error } = await db.storage.from('taxonomy-art').upload(objectPath, bytes, { contentType, upsert: false, cacheControl: '31536000' });
    if (error && !/exists|Duplicate/i.test(error.message)) throw new Error(`upload illustration: ${error.message}`);
  }

  async function artBytes(objectPath) {
    const blob = must(await db.storage.from('taxonomy-art').download(objectPath), 'download illustration');
    return Buffer.from(await blob.arrayBuffer());
  }

  const publicUrl = (bucket, objectPath) =>
    `${config.supabaseUrl}/storage/v1/object/public/${bucket}/${objectPath.split('/').map(encodeURIComponent).join('/')}`;

  async function photoBytes(photo) {
    const blob = must(await db.storage.from('label-photos').download(photo.object_path), 'download photo');
    return Buffer.from(await blob.arrayBuffer());
  }

  /** A submission created from the admin (photos dropped into the browser). */
  async function createAdminSubmission({ barcode, nameHint, brandHint, note, photos, actor }) {
    const id = crypto.randomUUID();
    const provisional = barcode ? `gtin:${barcode.gtin}` : `pending:${crypto.randomUUID()}`;
    const rows = [];
    for (const p of photos) {
      const sha = crypto.createHash('sha256').update(p.bytes).digest('hex');
      const ext = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }[p.contentType];
      if (!ext) throw new Error(`Unsupported photo type ${p.contentType}.`);
      const objectPath = `admin/${id}/${sha}.${ext}`;
      const { error } = await db.storage.from('label-photos').upload(objectPath, p.bytes, { contentType: p.contentType, upsert: false });
      if (error && !/exists|Duplicate/i.test(error.message)) throw new Error(`upload photo: ${error.message}`);
      rows.push({ submission_id: id, role: p.role, object_path: objectPath, sha256: sha, content_type: p.contentType,
        width: p.width ?? null, height: p.height ?? null, bytes: p.bytes.length });
    }
    await rpc('create_admin_submission', {
      p_actor: actor,
      p_submission: {
        id, source: 'admin', raw_barcode: barcode?.raw ?? null, symbology: barcode?.symbology ?? null,
        gtin: barcode?.gtin ?? null, provisional_id: provisional, name_hint: nameHint || null,
        brand_hint: brandHint || null, note: note || null,
      },
      p_photos: rows,
    });
    return id;
  }

  return {
    db,
    rpc,
    listSubmissions,
    getSubmission,
    taxonomy,
    listRecords,
    getRecord,
    listArt,
    uploadArt,
    artBytes,
    publicUrl,
    photoBytes,
    createAdminSubmission,
    claim: (id, actor) => rpc('claim_submission', { p_submission: id, p_actor: actor }),
    release: (id, actor, reason) => rpc('release_submission', { p_submission: id, p_actor: actor, p_reason: reason }),
    recordExtraction: (args) => rpc('record_extraction', args),
    reject: (extractionId, reviewer, comment) =>
      rpc('reject_extraction', { p_extraction: extractionId, p_reviewer: reviewer, p_comment: comment }),
    accept: (extractionId, reviewer, comment, edits, publish) =>
      rpc('accept_extraction', { p_extraction: extractionId, p_reviewer: reviewer, p_comment: comment || null,
        p_edits: edits, p_publish: publish }),
    setRecordCategory: (recordId, categoryId, reviewer, reason) =>
      rpc('set_record_category', { p_record: recordId, p_category: categoryId, p_reviewer: reviewer, p_reason: reason }),
    recordArt: (actor, art) => rpc('record_taxonomy_art', { p_actor: actor, p_art: art }),
    decideArt: (id, decision, reviewer, comment, alt) =>
      rpc('decide_taxonomy_art', { p_art: id, p_decision: decision, p_reviewer: reviewer, p_comment: comment || null, p_alt: alt || null }),
    clearImage: (level, nodeId, reviewer, reason) =>
      rpc('clear_taxonomy_image', { p_level: level, p_node: nodeId, p_reviewer: reviewer, p_reason: reason }),
    createAppUser: async (email, password) =>
      must(await db.auth.admin.createUser({ email, password, email_confirm: true }), 'create user').user,
    listUsers: async () => must(await db.auth.admin.listUsers(), 'list users').users.map((u) => ({ id: u.id, email: u.email, created_at: u.created_at })),
  };
}
