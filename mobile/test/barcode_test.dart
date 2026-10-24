import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimeter/logic/barcode.dart';

void main() {
  String? gtin(String raw, Symbology s) => normalizeBarcode(raw, s)?.gtin14;

  group('GTIN-14 normalisation', () {
    test('EAN-13 and UPC-A are validated and left-padded', () {
      final g = normalizeBarcode('0096619845774', Symbology.ean13)!;
      expect(g.gtin14, '00096619845774');
      expect(g.id, 'gtin:00096619845774');
      expect(g.raw, '0096619845774');
      expect(g.symbology, Symbology.ean13);
      // The same product read as a 12-digit UPC-A lands on the same id.
      expect(gtin('096619845774', Symbology.upca), '00096619845774');
    });

    test('UPC-E is expanded to UPC-A before padding, never padded as it stands', () {
      expect(expandUpcE('06782900'), '067000008290');
      final g = normalizeBarcode('06782900', Symbology.upce)!;
      expect(g.gtin14, '00067000008290');
      expect(g.raw, '06782900');
      expect(g.symbology, Symbology.upce);
      expect(g.gtin14, isNot('00000006782900'));
    });

    test('UPC-E expansion follows the last digit', () {
      expect(expandUpcE('04252614'), '042100005264'); // last digit 0–2: manufacturer keeps it
      expect(expandUpcE('123453')!.substring(0, 11), '01230000045'); // 3
      expect(expandUpcE('123454')!.substring(0, 11), '01234000005'); // 4
      expect(expandUpcE('123457')!.substring(0, 11), '01234500007'); // 5–9
      expect(expandUpcE('22345678'), isNull); // number system must be 0 or 1
    });

    test('EAN-8 and ITF-14', () {
      expect(gtin('96385074', Symbology.ean8), '00000096385074');
      expect(gtin('00012345600012', Symbology.itf14), '00012345600012');
    });

    test('invalid check digits are refused', () {
      expect(gtin('0096619845775', Symbology.ean13), isNull);
      expect(gtin('096619845775', Symbology.upca), isNull);
      expect(gtin('06782901', Symbology.upce), isNull);
      expect(gtin('96385075', Symbology.ean8), isNull);
      expect(gtin('00012345600013', Symbology.itf14), isNull);
    });

    test('wrong lengths and non-digits are refused', () {
      expect(gtin('09661984577', Symbology.ean13), isNull);
      expect(gtin('09661984577', Symbology.unknown), isNull);
      expect(gtin('000966198457740', Symbology.unknown), isNull);
      expect(gtin('12345', Symbology.unknown), isNull);
      expect(gtin('0096619a45774', Symbology.ean13), isNull);
      expect(gtin('', Symbology.unknown), isNull);
    });

    test('typed codes: the length decides, and 8 digits read as UPC-E when they expand', () {
      expect(gtin('0096619845774', Symbology.unknown), '00096619845774');
      expect(gtin('096619845774', Symbology.unknown), '00096619845774');
      expect(gtin('06782900', Symbology.unknown), '00067000008290');
      expect(gtin('96385074', Symbology.unknown), '00000096385074');
      expect(normalizeBarcode('06782900', Symbology.unknown)!.symbology, Symbology.unknown);
      expect(looksLikeBarcode(' 06782900 '), isTrue);
      expect(looksLikeBarcode('nutella'), isFalse);
    });

    test('the check digit matches the database rule (padded to 14)', () {
      expect(gtinCheckDigit('009661984577'), 4);
      expect(gtinValid('00096619845774'), isTrue);
      expect(gtinOfId('gtin:00096619845774'), '00096619845774');
      expect(gtinOfId('cnf:12'), isNull);
    });
  });
}
