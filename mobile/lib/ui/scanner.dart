import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'theme.dart';

/// Full-screen camera that returns the first EAN/UPC barcode it reads, or null if closed.
Future<String?> scanBarcode(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ScannerPage()));

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final code = b.rawValue;
      if (code != null && RegExp(r'^\d{8,14}$').hasMatch(code)) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final window = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: size.width * 0.8, height: size.width * 0.45);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          scanWindow: window,
          errorBuilder: (context, error) => _Message(switch (error.errorCode) {
            MobileScannerErrorCode.permissionDenied => 'Camera permission was denied. Allow it in Settings to scan barcodes.',
            MobileScannerErrorCode.unsupported => 'This device has no usable camera.',
            _ => 'Could not start the camera (${error.errorCode.name}).',
          }),
        ),
        // Dim everything outside the scan window.
        IgnorePointer(
          child: CustomPaint(size: size, painter: _WindowPainter(window)),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Expanded(child: Text('Scan a barcode', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
              IconButton(
                icon: Icon(_torch ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                tooltip: 'Torch',
                onPressed: () async {
                  await _controller.toggleTorch();
                  setState(() => _torch = !_torch);
                },
              ),
            ]),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: window.bottom + 24,
          child: const Text('Line up the barcode inside the box', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
        ),
      ]),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(window, const Radius.circular(14));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r)),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Palette.accent);
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          ),
        ),
      );
}
