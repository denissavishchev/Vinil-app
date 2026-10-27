import 'package:flutter/material.dart';

import 'theme.dart';

/// A vertical slider in the plugin's look: rounded frame, track, ball. value is 0..1.
class VSlider extends StatelessWidget {
  final double value, defaultValue;
  final ValueChanged<double> onChanged;
  const VSlider({
    super.key,
    required this.value,
    required this.defaultValue,
    required this.onChanged,
  });

  static const double pad =
      26.0; // room between the frame and the ball at both ends

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        double at(double dy) =>
            (1.0 - (dy - pad) / (h - 2 * pad)).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onChanged(at(d.localPosition.dy)),
          onVerticalDragUpdate: (d) => onChanged(at(d.localPosition.dy)),
          onDoubleTap: () => onChanged(defaultValue), // back to the default
          child: CustomPaint(
            size: Size(box.maxWidth, h),
            painter: _SliderPainter(value),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  final double value;
  _SliderPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = VSlider.pad;
    final cx = size.width / 2;
    final a = Offset(cx, size.height - pad), b = Offset(cx, pad);
    final thumb = Offset(
      cx,
      size.height - pad - value * (size.height - 2 * pad),
    );

    final frame = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    ).deflate(0.7).deflate(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(12)),
      stroke(gold.withValues(alpha: 0.75), 1.4),
    );
    canvas.drawLine(
      a,
      b,
      stroke(gold.withValues(alpha: 0.3), 3)..strokeCap = StrokeCap.butt,
    );
    canvas.drawLine(a, thumb, stroke(goldHi, 3));
    canvas.drawCircle(thumb, 6.5, fill(navy));
    canvas.drawCircle(thumb, 6.5, stroke(goldHi, 2));
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) => old.value != value;
}

/// Toggle button (SNAP / SMOOTH) and plain outlined button (REC).
class LineButton extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;
  final double fontSize;
  const LineButton({
    super.key,
    required this.text,
    required this.on,
    required this.onTap,
    this.fontSize = 10.5,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CustomPaint(
        painter: _ButtonPainter(text, on, fontSize),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ButtonPainter extends CustomPainter {
  final String text;
  final bool on;
  final double fontSize;
  _ButtonPainter(this.text, this.on, this.fontSize);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.7),
      const Radius.circular(9),
    );
    if (on) canvas.drawRRect(r, fill(gold));
    canvas.drawRRect(r, stroke(gold, 1.4));
    drawText(
      canvas,
      text,
      size.center(Offset.zero),
      sans(fontSize, on ? navy : gold),
    );
  }

  @override
  bool shouldRepaint(covariant _ButtonPainter old) =>
      old.text != text || old.on != on;
}

/// MPC style pad: reacts on touch-down.
class PadButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  const PadButton({super.key, required this.text, required this.onPressed});
  @override
  State<PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<PadButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        setState(() => _down = true);
        widget.onPressed();
      },
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: CustomPaint(
        painter: _PadPainter(widget.text, _down),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  final String text;
  final bool down;
  _PadPainter(this.text, this.down);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(10)),
      fill(down ? gold : gold.withValues(alpha: 0.06)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(10)),
      stroke(gold, 1.5),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(4), const Radius.circular(7)),
      stroke(gold.withValues(alpha: 0.4), 0.8),
    );
    drawText(
      canvas,
      text,
      size.center(Offset.zero),
      sans(text.length > 6 ? 8.5 : 10.5, down ? navy : gold),
    );
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) =>
      old.down != down || old.text != text;
}

/// Square button with an icon instead of text: play (triangle) or stop (square).
class IconSquareButton extends StatelessWidget {
  final bool play;
  final VoidCallback onTap;
  const IconSquareButton({super.key, required this.play, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: CustomPaint(
      painter: _IconPainter(play),
      child: const SizedBox.expand(),
    ),
  );
}

class _IconPainter extends CustomPainter {
  final bool play;
  _IconPainter(this.play);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.7),
      const Radius.circular(10),
    );
    canvas.drawRRect(r, fill(gold.withValues(alpha: 0.06)));
    canvas.drawRRect(r, stroke(gold, 1.5));
    final c = size.center(Offset.zero);
    final u = size.shortestSide * 0.17;
    if (play) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - u * 0.8, c.dy - u * 1.2)
          ..lineTo(c.dx + u * 1.3, c.dy)
          ..lineTo(c.dx - u * 0.8, c.dy + u * 1.2)
          ..close(),
        fill(goldHi),
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: u * 2, height: u * 2),
          const Radius.circular(2),
        ),
        fill(goldHi),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.play != play;
}
