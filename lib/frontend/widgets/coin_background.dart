import 'dart:math' as math;
import 'package:flutter/material.dart';

class CoinBackground extends StatefulWidget {
  final Widget child;
  const CoinBackground({super.key, required this.child});

  @override
  State<CoinBackground> createState() => _CoinBackgroundState();
}

class _CoinBackgroundState extends State<CoinBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Coin> _coins = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 20; i++) {
      _coins.add(_Coin(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.05 + _random.nextDouble() * 0.15,
        size: 15.0 + _random.nextDouble() * 20.0,
        rotationSpeed: (_random.nextDouble() - 0.5) * 5.0,
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
        // Nền tối
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
            ),
          ),
        ),
        
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _CoinPainter(_coins, _controller.value),
              size: Size.infinite,
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _Coin {
  final double x;
  final double y;
  final double speed;
  final double size;
  final double rotationSpeed;

  _Coin({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.rotationSpeed,
  });
}

class _CoinPainter extends CustomPainter {
  final List<_Coin> coins;
  final double progress;

  _CoinPainter(this.coins, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (var coin in coins) {
      double yPos = (coin.y + progress * coin.speed) % 1.0;
      double actualX = coin.x * size.width;
      double actualY = yPos * size.height;
      double rotation = progress * coin.rotationSpeed * math.pi * 2;

      canvas.save();
      canvas.translate(actualX, actualY);
      canvas.rotate(rotation);

      // Vẽ hình đồng xu mờ
      final paint = Paint()
        ..color = Colors.amber.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = Colors.amberAccent.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Làm cho đồng xu trông dẹt đi theo rotation để tạo cảm giác 3D
      double squeeze = math.cos(rotation).abs();
      // Vẽ vòng ngoài
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: coin.size, height: coin.size * squeeze), paint);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: coin.size, height: coin.size * squeeze), borderPaint);
      
      // Vẽ vòng trong
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: coin.size * 0.6, height: coin.size * 0.6 * squeeze), borderPaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CoinPainter oldDelegate) => true;
}
