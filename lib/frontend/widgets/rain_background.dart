import 'dart:math' as math;
import 'package:flutter/material.dart';

class RainBackground extends StatefulWidget {
  final Widget child;
  const RainBackground({super.key, required this.child});

  @override
  State<RainBackground> createState() => _RainBackgroundState();
}

class _RainBackgroundState extends State<RainBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Drop> _drops = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    // Khởi tạo các giọt nước
    for (int i = 0; i < 60; i++) {
      _drops.add(_Drop(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.1 + _random.nextDouble() * 0.4,
        size: 1.0 + _random.nextDouble() * 2.5,
        opacity: 0.1 + _random.nextDouble() * 0.4,
      ));
    }

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
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
        // Lớp nền gradient bầu trời đêm/ẩm ướt
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF2C194D), // Tím đậm
                Color(0xFF1B1B3A), // Xanh đen
                Color(0xFF0F1223), // Đêm đen
              ],
            ),
          ),
        ),
        
        // Mưa
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _RainPainter(_drops, _controller.value),
              size: Size.infinite,
            );
          },
        ),

        // Lớp content nằm trên
        widget.child,
      ],
    );
  }
}

class _Drop {
  final double x;
  double y;
  final double speed;
  final double size;
  final double opacity;

  _Drop({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
  });
}

class _RainPainter extends CustomPainter {
  final List<_Drop> drops;
  final double progress;

  _RainPainter(this.drops, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (var drop in drops) {
      final paint = Paint()
        ..color = Colors.white.withOpacity(drop.opacity)
        ..strokeWidth = drop.size
        ..strokeCap = StrokeCap.round;

      // Tính toán toạ độ Y giọt mưa rơi
      double yPos = (drop.y + progress * drop.speed) % 1.0;
      double actualX = drop.x * size.width;
      double actualY = yPos * size.height;

      // Vệt mưa chéo nhẹ
      canvas.drawLine(
        Offset(actualX, actualY),
        Offset(actualX - drop.size * 0.5, actualY + drop.size * 5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) => true;
}
