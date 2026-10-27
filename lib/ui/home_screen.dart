import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../dsp/curve.dart';
import '../dsp/engine.dart';
import 'controls.dart';
import 'curve_view.dart';
import 'deck.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  final AppController app;
  const HomeScreen({super.key, required this.app});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _names = ['WEIGHT', 'DRAG', 'PREROLL'];
  static const _hints = [
    'WEIGHT: how heavy the record feels under your finger. Low follows it at once, high is lazy and smooth.',
    'DRAG: inertia of the platter when it follows the curve. Low reacts at once, high eases in slowly.',
    'PREROLL: how far behind live the head restarts each loop, so the curve can also speed things up.',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // the app is being left or closed: write the settings now
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      widget.app.engine.motorOn = false; // leaving the app: back to stop
      widget.app.saveSettings();
    } else {
      setState(() {}); // the play / stop button shows the stopped state again
    }
  }

  AppController get app => widget.app;

  void _applyShape(int idx) {
    app.engine.curve.pts = Shapes.make(idx, VinilEngine.speedRange);
    app.curveEdited();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: LayoutBuilder(
              builder: (context, box) {
                final deckW = box.maxWidth * 0.62;
                final deckH = Deck.heightFor(deckW);
                return Column(
                  children: [
                    Expanded(child: _topPanel()),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: deckH,
                      child: Row(
                        children: [
                          SizedBox(
                            width: deckW,
                            child: Deck(engine: app.engine),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: _sliders()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(height: 156, child: _pads()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _topPanel() {
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          Expanded(child: CurveView(app: app)),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const Expanded(child: _NamePlate()),
                const SizedBox(width: 8),
                SizedBox(
                  width: 92,
                  child: LineButton(
                    text: app.recording ? '■  STOP' : '●  REC',
                    on: app.recording,
                    onTap: app.toggleRecording,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliders() {
    return Panel(
      inner: false,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; ++i)
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: VSlider(
                      value: app.sliders[i],
                      defaultValue: AppController.sliderDefaults[i],
                      hint: _hints[i],
                      onChanged: (v) => app.setSlider(i, v),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 14,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _names[i],
                        style: sans(9, gold.withValues(alpha: 0.85)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pads() {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (var row = 0; row < 3; ++row) ...[
            if (row > 0) const SizedBox(height: 7),
            Expanded(
              child: Row(
                children: [
                  for (var col = 0; col < 5; ++col) ...[
                    if (col > 0) const SizedBox(width: 7),
                    Expanded(
                      child: PadButton(
                        text: Shapes.names[Shapes.padShapes[row * 5 + col]],
                        onPressed: () =>
                            _applyShape(Shapes.padShapes[row * 5 + col]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NamePlate extends StatelessWidget {
  const _NamePlate();
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PlatePainter(),
    child: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('DEVIS LABORATORY VINIL', style: sans(12.5, gold)),
      ),
    ),
  );
}

class _PlatePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      const Radius.circular(10),
    ),
    stroke(gold, 1.4),
  );
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
