// Barcode → GTIN-14, the same rules as the app (mobile/lib/logic/barcode.dart) and the database's gtin_valid.

export function checkDigit(body) {
  // body: the digits without the check digit; weights 3,1,3,… from the right.
  let sum = 0;
  for (let i = 0; i < body.length; i++) {
    const digit = Number(body[body.length - 1 - i]);
    sum += digit * (i % 2 === 0 ? 3 : 1);
  }
  return (10 - (sum % 10)) % 10;
}

export const validGtin = (code) => /^\d{8,14}$/.test(code) && checkDigit(code.slice(0, -1)) === Number(code.at(-1));

/** UPC-E (8 digits: number system, 6 digits, check) → UPC-A (12 digits). */
export function expandUpcE(code) {
  if (!/^[01]\d{7}$/.test(code)) return null;
  const ns = code[0], d = code.slice(1, 7), check = code[7];
  const [d1, d2, d3, d4, d5, d6] = d;
  let body;
  if ('012'.includes(d6)) body = `${d1}${d2}${d6}0000${d3}${d4}${d5}`;
  else if (d6 === '3') body = `${d1}${d2}${d3}00000${d4}${d5}`;
  else if (d6 === '4') body = `${d1}${d2}${d3}${d4}00000${d5}`;
  else body = `${d1}${d2}${d3}${d4}${d5}0000${d6}`;
  const upca = `${ns}${body}${check}`;
  return validGtin(upca) ? upca : null;
}

/**
 * Normalises a scanned or typed code. symbology: ean13 | ean8 | upca | upce | itf14 | unknown.
 * Returns { raw, symbology, gtin } or null when the code is not a valid GTIN. An 8-digit code with an unknown
 * symbology is ambiguous (EAN-8 or UPC-E): it is treated as EAN-8 only when it is not a valid UPC-E.
 */
export function normalizeBarcode(raw, symbology = 'unknown') {
  const code = String(raw || '').replace(/\D/g, '');
  let sym = symbology;
  let full = null;
  if (sym === 'upce' || (sym === 'unknown' && code.length === 8 && expandUpcE(code))) {
    full = expandUpcE(code);
    sym = 'upce';
  } else if (code.length >= 8 && code.length <= 14 && validGtin(code)) {
    full = code;
    if (sym === 'unknown') sym = { 8: 'ean8', 12: 'upca', 13: 'ean13', 14: 'itf14' }[code.length] || 'unknown';
  }
  if (!full) return null;
  return { raw: code, symbology: sym, gtin: full.padStart(14, '0') };
}
