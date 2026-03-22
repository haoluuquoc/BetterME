import 'dart:math' as math;
import 'package:flutter/material.dart';

class HeartbeatBackground extends StatefulWidget {
  final Widget child;
  const HeartbeatBackground({super.key, required this.child});

  @override
  State<HeartbeatBackground> createState() => _HeartbeatBackgroundState();
}

class _HeartbeatBackgroundState extends State<HeartbeatBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Nền tối
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1E0E1B),
                Color(0xFF2A0D15),
                Color(0xFF380816),
              ],
            ),
          ),
        ),
        
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _HeartbeatPainter(_controller.value),
              size: Size.infinite,
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _HeartbeatPainter extends CustomPainter {
  final double progress;

  _HeartbeatPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    // Vẽ đường EKG qua giữa màn hình
    final paint = Paint()
      ..color = Colors.pinkAccent.withOpacity(0.4)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final blurPaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.8)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
      ..style = PaintingStyle.stroke;

    final path = Path();
    
    // Một EKG pattern
    // P Q R S T waves
    double startY = size.height * 0.4;
    double scaleX = 200.0;
    
    // Di chuyển màn hình dựa vào progress để tạo cảm giác vòng lặp liên tục
    double offset = progress * size.width * 2;
    
    path.moveTo(-scaleX * 4 + offset, startY);
    
    for (int i = -4; i < 20; i++) {
        double x = i * scaleX + offset;
        // Điểm đầu P Wave (nhịp chuẩn)
        path.lineTo(x + 20, startY);
        // P Wave
        path.quadraticBezierTo(x + 35, startY - 20, x + 50, startY);
        // Nối vào QRS
        path.lineTo(x + 60, startY);
        // Q dip
        path.lineTo(x + 65, startY + 15);
        // R (đỉnh nhọn)
        path.lineTo(x + 75, startY - 120);
        // S dip
        path.lineTo(x + 85, startY + 30);
        // Nối vào T wave
        path.lineTo(x + 90, startY);
        path.lineTo(x + 110, startY);
        // T wave
        path.quadraticBezierTo(x + 130, startY - 30, x + 150, startY);
        // Nối tới cuối block
        path.lineTo(x + scaleX, startY);
    }
    
    canvas.drawPath(path, blurPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HeartbeatPainter oldDelegate) => true;
}
