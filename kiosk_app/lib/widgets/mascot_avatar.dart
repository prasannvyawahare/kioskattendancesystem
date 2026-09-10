import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Emotion the mascot leans toward -- driven by the scan result in
/// CameraScreen (happy on check-in/check-out, confused on "not
/// recognized", neutral otherwise/idle). The painter doesn't snap between
/// these; MascotAvatar eases a continuous mood value toward whichever one
/// is current, so expression changes morph rather than cut.
enum MascotExpression { neutral, happy, confused }

/// A simple hand-drawn (CustomPainter, no image assets) school-boy
/// character that sits on the camera screen, animated rather than static:
/// it breathes/bobs and blinks continuously, and while GreetingService is
/// speaking it talks (mouth opens on the beat), nods more, and -- if happy
/// -- waves, so it visibly performs whatever greeting is shown in the
/// paired [MascotSpeechBubble].
class MascotAvatar extends StatefulWidget {
  const MascotAvatar({
    super.key,
    required this.expression,
    required this.isTalking,
    this.size = 84,
  });

  final MascotExpression expression;
  final bool isTalking;
  final double size;

  @override
  State<MascotAvatar> createState() => _MascotAvatarState();
}

class _MascotAvatarState extends State<MascotAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _loop;
  final _random = Random();
  Timer? _blinkTimer;
  double _blink = 0;
  double _mood = 0;

  @override
  void initState() {
    super.initState();
    _mood = _moodFor(widget.expression);
    _loop = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _scheduleBlink();
  }

  double _moodFor(MascotExpression e) => switch (e) {
        MascotExpression.happy => 1,
        MascotExpression.confused => -1,
        MascotExpression.neutral => 0,
      };

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 2200 + _random.nextInt(2200)), () async {
      if (!mounted) return;
      setState(() => _blink = 1);
      await Future<void>.delayed(const Duration(milliseconds: 110));
      if (!mounted) return;
      setState(() => _blink = 0);
      _scheduleBlink();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        // Ease the mood toward whatever expression is current, each tick,
        // instead of the painter jumping between shapes instantly.
        _mood += (_moodFor(widget.expression) - _mood) * 0.06;

        final speed = widget.isTalking ? 2.6 : 1.0;
        final phase = _loop.value * speed * 2 * pi;

        final bob = sin(phase) * (widget.isTalking ? 4.5 : 2.0);
        final tilt = sin(phase * 0.5) * (widget.isTalking ? 0.06 : 0.02);
        final mouthOpen =
            widget.isTalking ? (0.5 + 0.5 * sin(phase * 3)).clamp(0.0, 1.0) : 0.0;
        final waveAmount =
            (widget.isTalking && _mood > 0.3) ? (0.5 + 0.5 * sin(phase * 1.4)) : 0.0;

        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform.rotate(
            angle: tilt,
            child: SizedBox(
              width: widget.size,
              height: widget.size * 1.15,
              child: CustomPaint(
                painter: _MascotPainter(
                  mood: _mood,
                  blink: _blink,
                  mouthOpen: mouthOpen,
                  waveAmount: waveAmount,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Speech-bubble caption anchored to the mascot's mouth, showing whatever
/// text GreetingService is currently speaking (see GreetingService.caption).
class MascotSpeechBubble extends StatelessWidget {
  const MascotSpeechBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.2),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Piecewise-linear interpolation across three keyframes at mood = -1, 0, 1
/// -- lets every feature (brows, mouth shape) morph continuously with
/// [_MascotPainter.mood] instead of switching on a discrete enum.
double _lerp3(double atNeg, double atZero, double atPos, double mood) {
  final m = mood.clamp(-1.0, 1.0);
  return m >= 0 ? lerpDouble(atZero, atPos, m)! : lerpDouble(atZero, atNeg, -m)!;
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.mood,
    required this.blink,
    required this.mouthOpen,
    required this.waveAmount,
  });

  /// -1 (confused) .. 0 (neutral) .. 1 (happy), continuous.
  final double mood;

  /// 0 (eyes open) .. 1 (eyes fully closed), for the blink animation.
  final double blink;

  /// 0 (mouth closed, shows the mood shape) .. 1 (mouth fully open, talking).
  final double mouthOpen;

  /// 0 (arm down) .. 1 (arm raised mid-wave); only driven while happy+talking.
  final double waveAmount;

  static const _skin = Color(0xFFE8B48A);
  static const _hair = Color(0xFF3B2A20);
  static const _mouthColor = Color(0xFF8A3B2E);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final r = size.width * 0.42;

    _paintArm(canvas, size, center, r);
    _paintCollar(canvas, size, center, r);
    _paintHead(canvas, center, r);
    _paintHair(canvas, center, r);
    _paintEars(canvas, center, r);
    _paintBrows(canvas, center, r);
    _paintEyes(canvas, center, r);
    _paintMouth(canvas, center, r);
  }

  void _paintArm(Canvas canvas, Size size, Offset center, double r) {
    if (waveAmount <= 0.02) return;
    final shoulder = Offset(center.dx + r * 0.85, center.dy + r * 1.15);
    final angle = -0.9 - waveAmount * 0.6;
    final hand = shoulder + Offset(cos(angle), sin(angle)) * r * 1.1;

    final armPaint = Paint()
      ..color = _skin
      ..strokeWidth = r * 0.22
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(shoulder, hand, armPaint);
    canvas.drawCircle(hand, r * 0.16, Paint()..color = _skin);
  }

  void _paintCollar(Canvas canvas, Size size, Offset center, double r) {
    final collar = Paint()..color = Colors.white;
    final collarPath = Path()
      ..moveTo(center.dx - r * 0.9, size.height)
      ..lineTo(center.dx - r * 0.28, center.dy + r * 0.95)
      ..lineTo(center.dx, center.dy + r * 1.15)
      ..lineTo(center.dx + r * 0.28, center.dy + r * 0.95)
      ..lineTo(center.dx + r * 0.9, size.height)
      ..close();
    canvas.drawPath(collarPath, collar);

    final tie = Paint()..color = const Color(0xFFB33A3A);
    final tiePath = Path()
      ..moveTo(center.dx - r * 0.12, center.dy + r * 1.05)
      ..lineTo(center.dx + r * 0.12, center.dy + r * 1.05)
      ..lineTo(center.dx + r * 0.07, size.height * 0.94)
      ..lineTo(center.dx, size.height)
      ..lineTo(center.dx - r * 0.07, size.height * 0.94)
      ..close();
    canvas.drawPath(tiePath, tie);
  }

  void _paintHead(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(center, r, Paint()..color = _skin);
  }

  void _paintEars(Canvas canvas, Offset center, double r) {
    final ear = Paint()..color = _skin;
    canvas.drawCircle(Offset(center.dx - r * 0.95, center.dy + r * 0.05), r * 0.16, ear);
    canvas.drawCircle(Offset(center.dx + r * 0.95, center.dy + r * 0.05), r * 0.16, ear);
  }

  void _paintHair(Canvas canvas, Offset center, double r) {
    final hair = Paint()..color = _hair;
    final top = center.dy - r;
    final path = Path()..moveTo(center.dx - r * 0.95, center.dy - r * 0.1);
    path.quadraticBezierTo(center.dx - r * 1.05, top - r * 0.1, center.dx - r * 0.5, top - r * 0.15);
    for (var i = -3; i <= 3; i++) {
      final x = center.dx + i * r * 0.22;
      final spike = i.isEven ? 0.32 : 0.2;
      path.lineTo(x, top - r * spike);
      path.lineTo(x + r * 0.11, top - r * 0.05);
    }
    path.quadraticBezierTo(center.dx + r * 1.05, top - r * 0.1, center.dx + r * 0.95, center.dy - r * 0.1);
    path.quadraticBezierTo(center.dx, center.dy - r * 0.55, center.dx - r * 0.95, center.dy - r * 0.1);
    path.close();
    canvas.drawPath(path, hair);
  }

  void _paintBrows(Canvas canvas, Offset center, double r) {
    final brow = Paint()
      ..color = _hair
      ..strokeWidth = r * 0.07
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final y = center.dy - r * 0.32;

    // Each brow's outer/inner endpoint y-offset morphs continuously with
    // mood: confused keeps the original asymmetric angled-in look, happy
    // is a relaxed upward tilt, neutral is flat.
    final leftOuterY = _lerp3(-0.06, 0, 0.02, mood);
    final leftInnerY = _lerp3(0.08, 0, -0.08, mood);
    final rightInnerY = _lerp3(0.02, 0, -0.08, mood);
    final rightOuterY = _lerp3(-0.12, 0, 0.02, mood);

    canvas.drawLine(
      Offset(center.dx - r * 0.45, y + r * leftOuterY),
      Offset(center.dx - r * 0.15, y + r * leftInnerY),
      brow,
    );
    canvas.drawLine(
      Offset(center.dx + r * 0.15, y + r * rightInnerY),
      Offset(center.dx + r * 0.45, y + r * rightOuterY),
      brow,
    );
  }

  void _paintEyes(Canvas canvas, Offset center, double r) {
    final white = Paint()..color = Colors.white;
    final pupil = Paint()..color = const Color(0xFF2B2118);
    final y = center.dy - r * 0.05;
    final eyeRx = r * 0.17;
    final eyeRy = eyeRx * (1 - blink * 0.92);

    for (final dx in [-r * 0.28, r * 0.28]) {
      final eyeCenter = Offset(center.dx + dx, y);
      final rect = Rect.fromCenter(center: eyeCenter, width: eyeRx * 2, height: eyeRy * 2);
      canvas.drawOval(rect, white);
      if (blink < 0.7) {
        canvas.drawCircle(eyeCenter, eyeRx * 0.5 * (1 - blink), pupil);
      } else {
        canvas.drawLine(
          Offset(eyeCenter.dx - eyeRx * 0.6, eyeCenter.dy),
          Offset(eyeCenter.dx + eyeRx * 0.6, eyeCenter.dy),
          Paint()
            ..color = const Color(0xFF2B2118)
            ..strokeWidth = r * 0.03,
        );
      }
    }
  }

  void _paintMouth(Canvas canvas, Offset center, double r) {
    final mouthCenter = Offset(center.dx, center.dy + r * 0.42);

    if (mouthOpen > 0.15) {
      final h = r * (0.1 + 0.26 * mouthOpen);
      canvas.drawOval(
        Rect.fromCenter(center: mouthCenter, width: r * 0.32, height: h),
        Paint()..color = _mouthColor,
      );
      return;
    }

    // Mouth shape morphs continuously with mood: a crooked, off-center
    // curve at confused, a flat line at neutral, a full smile at happy.
    final startY = _lerp3(0.05, 0, -0.05, mood);
    final endY = _lerp3(-0.02, 0, -0.05, mood);
    final cx = _lerp3(-0.12, 0, 0, mood);
    final cy = _lerp3(-0.12, 0, 0.32, mood);

    final path = Path()
      ..moveTo(mouthCenter.dx - r * 0.3, mouthCenter.dy + r * startY)
      ..quadraticBezierTo(
        mouthCenter.dx + r * cx,
        mouthCenter.dy + r * cy,
        mouthCenter.dx + r * 0.3,
        mouthCenter.dy + r * endY,
      );

    canvas.drawPath(
      path,
      Paint()
        ..color = _mouthColor
        ..strokeWidth = r * 0.07
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.blink != blink ||
      oldDelegate.mouthOpen != mouthOpen ||
      oldDelegate.waveAmount != waveAmount;
}
