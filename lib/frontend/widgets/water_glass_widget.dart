import 'dart:math';
import 'package:flutter/material.dart';

/// Widget hiển thị ly nước với hiệu ứng nước đổ vào và sóng
/// [progress] từ 0.0 đến 1.0+
class WaterGlassWidget extends StatefulWidget {
  final double progress; // 0.0 - 1.0+
  final int currentMl;
  final int goalMl;

  const WaterGlassWidget({
    super.key,
    required this.progress,
    required this.currentMl,
    required this.goalMl,
  });

  @override
  State<WaterGlassWidget> createState() => _WaterGlassWidgetState();
}

class _WaterGlassWidgetState extends State<WaterGlassWidget>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _pourController;
  late Animation<double> _pourAnimation;
  double _displayProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _pourController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _pourAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _pourController, curve: Curves.easeOutCubic),
    );
    
    _displayProgress = widget.progress.clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(WaterGlassWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      final oldP = _displayProgress;
      final newP = widget.progress.clamp(0.0, 1.0);
      _pourAnimation = Tween<double>(begin: oldP, end: newP).animate(
        CurvedAnimation(parent: _pourController, curve: Curves.easeOutCubic),
      );
      _pourAnimation.addListener(() {
        setState(() => _displayProgress = _pourAnimation.value);
      });
      _pourController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pourController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = widget.progress >= 1.0;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ly nước
        SizedBox(
          width: 160,
          height: 220,
          child: AnimatedBuilder(
            animation: _waveController, 
            builder: (context, child) {
              return CustomPaint(
                painter: _GlassPainter(
                  fillPercent: _displayProgress,
                  wavePhase: _waveController.value * 2 * pi,
                  isComplete: isComplete,
                ),
                size: const Size(160, 220),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Số liệu
        Text(
          '${widget.currentMl}ml',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isComplete ? const Color(0xFF00E676) : const Color(0xFF5BB5E8),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '/ ${widget.goalMl}ml',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[500],
          ),
        ),
        const SizedBox(height: 6),
        // Status text
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: isComplete 
                ? const Color(0xFF00E676).withOpacity(0.15)
                : const Color(0xFF3A9BD5).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isComplete 
                ? 'Hoàn thành mục tiêu!'
                : '💧 Còn ${widget.goalMl - widget.currentMl}ml nữa',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isComplete ? const Color(0xFF00E676) : const Color(0xFF5BB5E8),
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter vẽ ly nước với sóng và bọt khí
class _GlassPainter extends CustomPainter {
  final double fillPercent;
  final double wavePhase;
  final bool isComplete;
  
  _GlassPainter({
    required this.fillPercent,
    required this.wavePhase,
    required this.isComplete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    
    // Kích thước ly (hình thang ngược nhẹ)
    const topInset = 16.0;   // khoảng cách từ mép trên
    const botInset = 38.0;   // đáy hẹp hơn
    const glassTop = 20.0;   // vị trí miệng ly
    final glassBot = h - 10; // vị trí đáy ly
    final glassH = glassBot - glassTop;
    
    final topLeft = w / 2 - (w / 2 - topInset);
    final topRight = w / 2 + (w / 2 - topInset);
    final botLeft = w / 2 - (w / 2 - botInset);
    final botRight = w / 2 + (w / 2 - botInset);
    
    // --- Vẽ nước bên trong ly ---
    final fill = fillPercent.clamp(0.0, 1.0);
    if (fill > 0.001) {
      final waterTop = glassBot - (glassH * fill);
      
      // Tính vị trí trái/phải tại waterTop (nội suy tuyến tính)
      final t = (waterTop - glassTop) / glassH; // 0=top, 1=bottom
      final leftAtWater = topLeft + (botLeft - topLeft) * t;
      final rightAtWater = topRight + (botRight - topRight) * t;
      
      // Wave path
      final waterPath = Path();
      waterPath.moveTo(leftAtWater, waterTop);
      
      // Vẽ sóng ở mặt nước
      final waveWidth = rightAtWater - leftAtWater;
      const waveAmplitude = 3.5;
      const steps = 40;
      for (int i = 0; i <= steps; i++) {
        final px = leftAtWater + (waveWidth * i / steps);
        final waveY = waterTop + 
            sin(wavePhase + (i / steps) * 2 * pi) * waveAmplitude +
            sin(wavePhase * 1.5 + (i / steps) * 4 * pi) * (waveAmplitude * 0.4);
        waterPath.lineTo(px, waveY);
      }
      
      // Xuống đáy ly
      waterPath.lineTo(botRight, glassBot);
      waterPath.lineTo(botLeft, glassBot);
      waterPath.close();
      
      // Clip theo hình ly
      final glassClip = Path();
      glassClip.moveTo(topLeft, glassTop);
      glassClip.lineTo(topRight, glassTop);
      glassClip.lineTo(botRight, glassBot);
      glassClip.lineTo(botLeft, glassBot);
      glassClip.close();
      
      canvas.save();
      canvas.clipPath(glassClip);
      
      // Gradient nước
      final waterGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isComplete
            ? [
                const Color(0xFF00E676).withOpacity(0.6),
                const Color(0xFF00C853).withOpacity(0.85),
                const Color(0xFF00BFA5).withOpacity(0.95),
              ]
            : [
                const Color(0xFF5BB5E8).withOpacity(0.5),
                const Color(0xFF3A9BD5).withOpacity(0.75),
                const Color(0xFF1A6FA0).withOpacity(0.9),
              ],
      );
      
      final waterPaint = Paint()
        ..shader = waterGradient.createShader(
          Rect.fromLTRB(leftAtWater, waterTop, rightAtWater, glassBot),
        );
      
      canvas.drawPath(waterPath, waterPaint);
      
      // Bọt khí (bubbles)
      _drawBubbles(canvas, leftAtWater, rightAtWater, waterTop, glassBot);
      
      canvas.restore();
    }
    
    // --- Vẽ viền ly (glass outline) ---
    final glassBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withOpacity(0.35);
    
    final glassPath = Path();
    glassPath.moveTo(topLeft, glassTop);
    glassPath.lineTo(botLeft, glassBot);
    // Đáy bo tròn
    glassPath.quadraticBezierTo(w / 2, glassBot + 8, botRight, glassBot);
    glassPath.lineTo(topRight, glassTop);
    canvas.drawPath(glassPath, glassBorderPaint);
    
    // Miệng ly (viền trên)
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withOpacity(0.5);
    canvas.drawLine(
      Offset(topLeft - 2, glassTop),
      Offset(topRight + 2, glassTop),
      rimPaint,
    );
    
    // Highlight phản chiếu (bên trái ly)
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.15);
    final hlPath = Path();
    hlPath.moveTo(topLeft + 8, glassTop + 15);
    hlPath.lineTo(botLeft + 6, glassBot - 20);
    canvas.drawPath(hlPath, highlightPaint);
    
    // --- Dòng nước rót từ trên xuống (pouring stream) ---
    if (fill > 0 && fill < 1.0) {
      _drawPouringStream(canvas, w, glassTop, fill, glassH, glassBot);
    }
    
    // Phần trăm hiển thị
    final percentText = '${(fill * 100).toInt()}%';
    final textPainter = TextPainter(
      text: TextSpan(
        text: percentText,
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final textX = (w - textPainter.width) / 2;
    final textY = glassTop + glassH * 0.5 - textPainter.height / 2;
    textPainter.paint(canvas, Offset(textX, textY));
  }

  void _drawBubbles(Canvas canvas, double left, double right, double waterTop, double waterBot) {
    final bubblePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(0.2);
    
    final rng = Random(42); // deterministic random
    final count = 8;
    for (int i = 0; i < count; i++) {
      final bx = left + (right - left) * rng.nextDouble();
      final by = waterTop + (waterBot - waterTop) * rng.nextDouble();
      final br = 1.5 + rng.nextDouble() * 3;
      // Animate position slightly
      final offsetY = sin(wavePhase + i * 0.7) * 4;
      canvas.drawCircle(Offset(bx, by + offsetY), br, bubblePaint);
    }
  }

  void _drawPouringStream(Canvas canvas, double w, double glassTop, double fill, double glassH, double glassBot) {
    final streamPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isComplete 
          ? const Color(0xFF00E676).withOpacity(0.35)
          : const Color(0xFF5BB5E8).withOpacity(0.35);
    
    final streamX = w / 2;
    final streamTop = 0.0;
    final waterLevel = glassBot - (glassH * fill);
    
    // Dòng nước mỏng rót
    final streamPath = Path();
    streamPath.moveTo(streamX - 3, streamTop);
    streamPath.lineTo(streamX + 3, streamTop);
    streamPath.lineTo(streamX + 2, waterLevel);
    streamPath.lineTo(streamX - 2, waterLevel);
    streamPath.close();
    canvas.drawPath(streamPath, streamPaint);
    
    // Splash ở mặt nước
    final splashPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(0.25);
    for (int i = 0; i < 4; i++) {
      final angle = wavePhase + i * pi / 2;
      final dx = cos(angle) * (6 + i * 2);
      final dy = sin(angle) * 2;
      canvas.drawCircle(
        Offset(streamX + dx, waterLevel + dy), 
        1.5, 
        splashPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) {
    return oldDelegate.fillPercent != fillPercent ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.isComplete != isComplete;
  }
}
