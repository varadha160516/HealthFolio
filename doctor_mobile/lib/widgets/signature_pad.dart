import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme.dart';

/// A draw-with-your-finger signature capture, rasterized to a PNG and returned as base64.
/// Deliberately no third-party signature package -- this app has no image-handling
/// dependencies at all yet, and a finger-drawn stroke capture is simple enough to do directly
/// with a CustomPainter + RepaintBoundary.toImage() rather than pulling one in.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key});
  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;

  void _start(Offset p) => setState(() {
        _current = [p];
        _strokes.add(_current!);
      });
  void _extend(Offset p) => setState(() => _current?.add(p));
  void _end() => setState(() => _current = null);
  void _clear() => setState(() => _strokes.clear());

  Future<void> _save() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draw a signature first')));
      return;
    }
    final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null || !mounted) return;
    final base64Png = base64Encode(byteData.buffer.asUint8List());
    Navigator.of(context).pop(base64Png);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Draw your signature'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        RepaintBoundary(
          key: _boundaryKey,
          child: Container(
            width: 300,
            height: 160,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(docRadiusSm), border: Border.all(color: docBorder)),
            child: GestureDetector(
              onPanStart: (d) => _start(d.localPosition),
              onPanUpdate: (d) => _extend(d.localPosition),
              onPanEnd: (_) => _end(),
              child: CustomPaint(painter: _SignaturePainter(_strokes), size: const Size(300, 160)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _clear, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Clear'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = docTextPrimary
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

/// Renders a stored base64 signature image, or a muted placeholder if none is set yet.
class SignaturePreview extends StatelessWidget {
  final String? base64Png;
  const SignaturePreview({super.key, required this.base64Png});

  @override
  Widget build(BuildContext context) {
    if (base64Png == null || base64Png!.isEmpty) {
      return Container(
        width: 160,
        height: 80,
        decoration: BoxDecoration(color: docSurfaceRaised, borderRadius: BorderRadius.circular(docRadiusSm)),
        child: const Center(child: Text('No signature yet', style: TextStyle(fontSize: 11, color: docMutedDim))),
      );
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(base64Png!);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return Container(
      width: 160,
      height: 80,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(docRadiusSm), border: Border.all(color: docBorder)),
      child: Image.memory(bytes, fit: BoxFit.contain),
    );
  }
}
