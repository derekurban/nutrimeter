import React, { useState } from 'react';
import { Button, Card, Input, Select } from '@derekurban/design-system';
import { api } from './api.js';
import { go } from './App.jsx';

const ROLES = [
  ['front', 'Front', 'Name, brand and net quantity.'],
  ['nutrition', 'Nutrition Facts', 'The whole table, flat and in focus.'],
  ['ingredients', 'Ingredients', 'Optional.'],
  ['other', 'Other', 'Optional: preparation instructions, extra columns.'],
];

/** Downscales a photo to at most 2048 px on its long side as JPEG, like the app does. */
async function encode(file) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 2048 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise((r) => canvas.toBlob(r, 'image/jpeg', 0.85));
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return { contentType: 'image/jpeg', data: btoa(binary), width: canvas.width, height: canvas.height, preview: URL.createObjectURL(blob) };
}

export function NewSubmission() {
  const [barcode, setBarcode] = useState('');
  const [symbology, setSymbology] = useState('unknown');
  const [nameHint, setNameHint] = useState('');
  const [brandHint, setBrandHint] = useState('');
  const [note, setNote] = useState('');
  const [photos, setPhotos] = useState([]); // { role, contentType, data, width, height, preview }
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function add(role, files) {
    setError('');
    try {
      const encoded = await Promise.all([...files].map(encode));
      setPhotos((p) => [...p, ...encoded.map((x) => ({ ...x, role }))]);
    } catch (e) {
      setError(`Could not read that image: ${e.message}`);
    }
  }

  async function submit() {
    setBusy(true);
    setError('');
    try {
      const { id } = await api.create({
        barcode: barcode.trim() || null, symbology, nameHint, brandHint, note,
        photos: photos.map(({ preview, ...p }) => p),
      });
      go(`/s/${id}`);
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  }

  const has = (role) => photos.some((p) => p.role === role);
  return (
    <section className="stack narrow">
      <h1>Add a product</h1>
      <p className="muted">For products photographed outside the app. The submission joins the queue like one from the phone.</p>
      <Card padding="md" className="stack">
        <div className="grid2">
          <Input label="Barcode" value={barcode} onChange={(e) => setBarcode(e.target.value)} hint="Leave empty for food without one." inputMode="numeric" />
          <Select label="Barcode type" value={symbology} onChange={(e) => setSymbology(e.target.value)}
            options={[{ value: 'unknown', label: 'Work it out' }, { value: 'ean13', label: 'EAN-13' }, { value: 'upca', label: 'UPC-A' },
              { value: 'upce', label: 'UPC-E (8 digits)' }, { value: 'ean8', label: 'EAN-8' }, { value: 'itf14', label: 'ITF-14' }]} />
          <Input label="Name" value={nameHint} onChange={(e) => setNameHint(e.target.value)} hint="Optional." />
          <Input label="Brand" value={brandHint} onChange={(e) => setBrandHint(e.target.value)} hint="Optional." />
        </div>
        <Input label="Note for the reviewer" multiline rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
      </Card>
      {ROLES.map(([role, label, hint]) => (
        <Card key={role} padding="md" variant={has(role) ? 'raised' : 'sunk'}>
          <div className="row between">
            <div>
              <strong>{label}</strong>
              <div className="small muted">{hint}</div>
            </div>
            <label className="file">
              <input type="file" accept="image/*" multiple onChange={(e) => add(role, e.target.files)} />
              <span>Choose photos</span>
            </label>
          </div>
          <div className="thumbs">
            {photos.map((p, i) => p.role === role && (
              <button key={i} className="thumb" title="Remove" onClick={() => setPhotos((all) => all.filter((_, j) => j !== i))}>
                <img src={p.preview} alt="" />
              </button>
            ))}
          </div>
        </Card>
      ))}
      {error && <p className="error">{error}</p>}
      <div className="row end">
        <Button variant="primary" disabled={busy || !has('front') || !has('nutrition')} onClick={submit}>
          {busy ? 'Uploading…' : 'Add to the queue'}
        </Button>
      </div>
    </section>
  );
}
