import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class AgentPulseIcon extends StatefulWidget {
  const AgentPulseIcon({super.key, this.size = 28});

  final double size;

  @override
  State<AgentPulseIcon> createState() => _AgentPulseIconState();
}

class _AgentPulseIconState extends State<AgentPulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.size * 1.7, widget.size),
      painter: _PulsePainter(animation: _controller),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.animation}) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .04, size.height * .55)
      ..lineTo(size.width * .27, size.height * .55)
      ..lineTo(size.width * .33, size.height * .34)
      ..lineTo(size.width * .39, size.height * .55)
      ..lineTo(size.width * .48, size.height * .55)
      ..lineTo(size.width * .52, size.height * .68)
      ..lineTo(size.width * .60, size.height * .16)
      ..lineTo(size.width * .68, size.height * .84)
      ..lineTo(size.width * .75, size.height * .55)
      ..lineTo(size.width * .83, size.height * .55)
      ..lineTo(size.width * .90, size.height * .48)
      ..lineTo(size.width * .96, size.height * .55);

    final revealWidth = size.width * animation.value;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, revealWidth, size.height));

    final glowPaint = Paint()
      ..color = AppColors.accent.withOpacity( 0.35)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) => true;
}
