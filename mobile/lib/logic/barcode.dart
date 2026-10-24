/// Barcodes as the catalogue keys them: every retail code becomes a GTIN-14 (`gtin:<14 digits>`), with the raw code
/// and its symbology kept beside it. EAN-13, UPC-A, EAN-8 and ITF-14 are check-digit validated and left-padded with
/// zeros; an 8-digit UPC-E is first expanded to its UPC-A, never zero-padded as it stands.
library;

/// The symbologies the backend accepts (`submissions.symbology`).
enum Symbology { ean13, ean8, upca, upce, itf14, unknown }

class Gtin {
  const Gtin({required this.raw, required this.symbology, required this.gtin14});

  /// Digits as read or typed.
  final String raw;
  final Symbology symbology;

  /// The canonical 14-digit code.
  final String gtin14;

  /// The record id a product with this barcode has, before and after review.
  String get id => 'gtin:$gtin14';

  @override
  bool operator ==(Object other) => other is Gtin && other.raw == raw && other.symbology == symbology && other.gtin14 == gtin14;

  @override
  int get hashCode => Object.hash(raw, symbology, gtin14);

  @override
  String toString() => '$raw (${symbology.name}) → $gtin14';
}

final _digits = RegExp(r'^\d+$');

/// Something typed into search that should be treated as a barcode.
bool looksLikeBarcode(String s) => RegExp(r'^\d{8,14}$').hasMatch(s.trim());

/// The GTIN mod-10 check digit for [body] (every digit but the check digit): weights 3, 1, 3, … from the right.
int gtinCheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    final d = body.codeUnitAt(body.length - 1 - i) - 48;
    sum += i.isEven ? d * 3 : d;
  }
  return (10 - sum % 10) % 10;
}

/// True for an 8- to 14-digit code whose last digit is its GTIN check digit.
bool gtinValid(String code) =>
    code.length >= 8 && code.length <= 14 && _digits.hasMatch(code) && gtinCheckDigit(code.substring(0, code.length - 1)) == code.codeUnitAt(code.length - 1) - 48;

/// Expands a UPC-E code to its 12-digit UPC-A. Accepts 6 digits (number system 0, check digit computed), 7 (number
/// system + 6) or 8 (number system + 6 + check digit, which must match). Null when it is not a valid UPC-E.
String? expandUpcE(String code) {
  if (!_digits.hasMatch(code)) return null;
  final String ns, six;
  String? check;
  switch (code.length) {
    case 6:
      ns = '0';
      six = code;
    case 7:
      ns = code[0];
      six = code.substring(1);
    case 8:
      ns = code[0];
      six = code.substring(1, 7);
      check = code[7];
    default:
      return null;
  }
  if (ns != '0' && ns != '1') return null;
  final d = six.split('');
  final String body = switch (d[5]) {
    '0' || '1' || '2' => '${d[0]}${d[1]}${d[5]}0000${d[2]}${d[3]}${d[4]}',
    '3' => '${d[0]}${d[1]}${d[2]}00000${d[3]}${d[4]}',
    '4' => '${d[0]}${d[1]}${d[2]}${d[3]}00000${d[4]}',
    _ => '${d[0]}${d[1]}${d[2]}${d[3]}${d[4]}0000${d[5]}',
  };
  final upcA = '$ns$body${gtinCheckDigit('$ns$body')}';
  if (check != null && upcA[11] != check) return null;
  return upcA;
}

/// Normalises a scanned or typed code to a GTIN-14, or null when it is not a valid retail barcode (wrong length,
/// non-digits, a bad check digit).
///
/// With [Symbology.unknown] (a code typed into search) the length decides; an 8-digit code is read as UPC-E when it
/// expands with a matching check digit (common on North American cans and small packs) and as EAN-8 otherwise.
Gtin? normalizeBarcode(String raw, Symbology symbology) {
  final code = raw.trim();
  if (!_digits.hasMatch(code)) return null;
  String? full;
  switch (symbology) {
    case Symbology.upce:
      full = expandUpcE(code);
    case Symbology.ean13:
    case Symbology.upca:
    case Symbology.ean8:
    case Symbology.itf14:
      // Scanners sometimes report a UPC-A as a 13-digit EAN-13 with a leading 0, or the reverse; the padding and
      // check digit are the same for all of them, so only the length range matters.
      full = const {8, 12, 13, 14}.contains(code.length) ? code : null;
    case Symbology.unknown:
      if (code.length == 8) {
        full = expandUpcE(code);
        if (full == null && gtinValid(code)) full = code;
      } else if (const {12, 13, 14}.contains(code.length)) {
        full = code;
      }
  }
  if (full == null || !gtinValid(full)) return null;
  return Gtin(raw: code, symbology: symbology, gtin14: full.padLeft(14, '0'));
}

/// The GTIN-14 inside a `gtin:` id, or null for any other id.
String? gtinOfId(String id) => id.startsWith('gtin:') ? id.substring(5) : null;
