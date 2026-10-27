import 'package:flutter/material.dart';

// palette of the reference: navy blueprint with gold line-art
const navy = Color(0xFF262C3B);
const navyHi = Color(0xFF2D3547);
const navyLo = Color(0xFF1F2433);
const gold = Color(0xFFBB8C52);
const goldHi = Color(0xFFD9AA6C);

TextStyle sans(double size, Color color) => TextStyle(
  fontSize: size,
  color: color,
  fontWeight: FontWeight.w700,
  decoration: TextDecoration.none,
);

TextStyle mono(double size, Color color, {bool bold = false}) => TextStyle(
  fontSize: size,
  color: color,
  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  fontFamily: 'Menlo',
  fontFamilyFallback: const ['Roboto Mono', 'monospace'],
  decoration: TextDecoration.none,
);

/// Draws [s] on a canvas anchored at [at]. [align]: -1 starts at [at], 0 centres on it, 1 ends at it; [valign] likewise on dy.
void drawText(
  Canvas c,
  String s,
  Offset at,
  TextStyle style, {
  double align = 0,
  double valign = 0,
}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(
    c,
    Offset(
      at.dx - tp.width * (align + 1) / 2,
      at.dy - tp.height * (valign + 1) / 2,
    ),
  );
}

Paint stroke(Color color, double w) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

Paint fill(Color color) => Paint()..color = color;

void panelOutline(Canvas c, Size size, {bool inner = true}) {
  final f = (Offset.zero & size).deflate(1.0);
  c.drawRRect(
    RRect.fromRectAndRadius(f, const Radius.circular(18)),
    stroke(gold, 2.2),
  );
  if (inner) {
    c.drawRRect(
      RRect.fromRectAndRadius(f.deflate(5), const Radius.circular(14)),
      stroke(gold.withValues(alpha: 0.35), 1.0),
    );
  }
}

class PanelPainter extends CustomPainter {
  final bool inner;
  const PanelPainter({this.inner = true});
  @override
  void paint(Canvas canvas, Size size) => panelOutline(canvas, size, inner: inner);
  @override
  bool shouldRepaint(covariant PanelPainter old) => old.inner != inner;
}

/// An outlined panel (double gold line) around [child].
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.inner = true, // the thin second line
  });
  final bool inner;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: PanelPainter(inner: inner),
    child: Padding(padding: padding, child: child),
  );
}

/// Rebuilds every frame: the engine state lives outside the widget tree.
class Frames extends StatefulWidget {
  final WidgetBuilder builder;
  const Frames({super.key, required this.builder});
  @override
  State<Frames> createState() => _FramesState();
}

class _FramesState extends State<Frames> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (ctx, _) => widget.builder(ctx));
}
