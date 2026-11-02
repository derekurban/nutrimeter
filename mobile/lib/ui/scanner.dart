import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../logic/barcode.dart';
import 'theme.dart';

/// Full-screen camera that returns the first retail barcode (EAN-13, UPC-A, EAN-8, UPC-E, ITF-14) it reads with a
/// valid check digit in two frames, normalised to a GTIN-14, or null if closed. Misreads are ignored and scanning goes
/// on.
Future<Gtin?> scanBarcode(BuildContext context) =>
    Navigator.of(context).push<Gtin>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ScannerPage()));

Symbology symbologyOf(BarcodeFormat f) => switch (f) {
      BarcodeFormat.ean13 => Symbology.ean13,
      BarcodeFormat.ean8 => Symbology.ean8,
      BarcodeFormat.upcA => Symbology.upca,
      BarcodeFormat.upcE => Symbology.upce,
      BarcodeFormat.itf14 => Symbology.itf14,
      _ => Symbology.unknown,
    };

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  // No scanWindow and no DetectionSpeed.noDuplicates: on Android the plugin records a code as already seen before it
  // checks the scan window, and it only lets a code through the window when all four corners are inside it. A
  // barcode that came into view at the edge of the frame, or was held too close to fit the box, was then dropped for
  // as long as the screen stayed open, so scanning only worked in the moment before the window was applied. Every
  // frame is reported instead, the centremost valid code in it is taken and a ScanConfirmer settles it.
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.itf14],
    detectionTimeoutMs: 50,
  );
  final _confirmer = ScanConfirmer();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  // The MobileScanner widget leaves the app lifecycle to whoever owns the controller: release the camera when the app
  // goes to the background and take it back on return, or the preview comes back frozen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.start().ignore();
      case AppLifecycleState.inactive:
        _controller.stop().ignore();
      case AppLifecycleState.detached || AppLifecycleState.hidden || AppLifecycleState.paused:
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final read = _centremost(capture);
    final code = read == null ? null : _confirmer.add(read, DateTime.now());
    if (code == null) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(code);
  }

  /// The valid retail code nearest the middle of the frame, when the camera sees more than one.
  Gtin? _centremost(BarcodeCapture capture) {
    Gtin? best;
    var bestDistance = double.infinity;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      final code = raw == null ? null : normalizeBarcode(raw, symbologyOf(b.format));
      if (code == null) continue;
      final d = _offCentre(b.corners, capture.size);
      if (d < bestDistance) {
        best = code;
        bestDistance = d;
      }
    }
    return best;
  }

  static double _offCentre(List<Offset> corners, Size frame) {
    if (corners.isEmpty || frame.isEmpty) return 0;
    final c = corners.reduce((a, b) => a + b) / corners.length.toDouble();
    return (Offset(c.dx / frame.width, c.dy / frame.height) - const Offset(0.5, 0.5)).distance;
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
          errorBuilder: (context, error) => _Message(
            switch (error.errorCode) {
              MobileScannerErrorCode.permissionDenied => 'Camera permission was denied. Allow it in Settings to scan barcodes.',
              MobileScannerErrorCode.unsupported => 'This device has no usable camera.',
              _ => 'Could not start the camera (${error.errorCode.name}).',
            },
            onRetry: switch (error.errorCode) {
              MobileScannerErrorCode.permissionDenied || MobileScannerErrorCode.unsupported => null,
              _ => () => _controller.start().ignore(),
            },
          ),
        ),
        // Dim everything outside the box. The box is only something to aim at: a barcode anywhere in view is read.
        IgnorePointer(
          child: CustomPaint(size: size, painter: _WindowPainter(window)),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Expanded(child: Text('Scan a barcode', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
              ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, state, _) => switch (state.torchState) {
                  TorchState.unavailable => const SizedBox.shrink(),
                  final torch => IconButton(
                      icon: Icon(torch == TorchState.on ? LucideIcons.flashlight : LucideIcons.flashlightOff, color: Colors.white),
                      tooltip: 'Torch',
                      onPressed: () => _controller.toggleTorch().ignore(),
                    ),
                },
              ),
            ]),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: window.bottom + 24,
          child: const Text('Point the camera at the barcode', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
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
      ..color = Du.dark.accentStrong);
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ]),
          ),
        ),
      );
}
