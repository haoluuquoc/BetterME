import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';

/// Splash Screen với animation nước rót vào ly
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fillController;
  late AnimationController _waveController;
  late AnimationController _dropController;
  late AnimationController _fadeInController;

  late Animation<double> _fillAnimation;
  late Animation<double> _waveAnimation;
  late Animation<double> _dropAnimation;
  late Animation<double> _fadeInAnimation;

  // Water color palette (watercolor blue theme)
  static const Color _waterLight = Color(0xFF89CFF0);
  static const Color _waterMid = Color(0xFF5BB5E8);
  static const Color _waterDark = Color(0xFF3A9BD5);
  static const Color _waterDeep = Color(0xFF2980B9);
  static const Color _bgTop = Color(0xFFE8F4FD);
  static const Color _bgBottom = Color(0xFFB8DCF0);
  static const Color _glassColor = Color(0x40FFFFFF);
  static const Color _glassEdge = Color(0x80C8E6F5);

  @override
  void initState() {
    super.initState();

    // Fade in animation
    _fadeInController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeOut,
    );

    // Water fill animation (main progress)
    _fillController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
    _fillAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fillController, curve: Curves.easeInOut),
    );

    // Wave animation (looping)
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _waveAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      _waveController,
    );

    // Water drop animation (looping)
    _dropController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat();
    _dropAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _dropController, curve: Curves.easeIn),
    );

    _fadeInController.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _fillController.forward();
    });

    _fillController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          try {
            final authService = AuthService();
            if (authService.isLoggedIn) {
              Navigator.pushReplacementNamed(context, Routes.home);
            } else {
              Navigator.pushReplacementNamed(context, Routes.login);
            }
          } catch (e) {
            debugPrint('Auth check error: $e');
            Navigator.pushReplacementNamed(context, Routes.login);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _fillController.dispose();
    _waveController.dispose();
    _dropController.dispose();
    _fadeInController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeInAnimation,
            child: Column(
              children: [
                const Spacer(flex: 1),

                // App name
                Text(
                  'BETTERME',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    foreground: Paint()
                      ..shader = const LinearGradient(
                        colors: [_waterDark, _waterDeep],
                      ).createShader(const Rect.fromLTWH(0, 0, 200, 40)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nạp năng lượng...',
                  style: TextStyle(
                    fontSize: 14,
                    color: _waterDeep.withOpacity(0.6),
                    letterSpacing: 1,
                  ),
                ),

                const Spacer(flex: 1),

                // Glass with water animation
                AnimatedBuilder(
                  animation: Listenable.merge([
                    _fillController,
                    _waveController,
                    _dropController,
                  ]),
                  builder: (context, child) {
                    final progress = _fillAnimation.value;
                    return Column(
                      children: [
                        // Percentage text
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: _waterDeep,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Glass with water
                        SizedBox(
                          width: 160,
                          height: 280,
                          child: CustomPaint(
                            painter: _WaterGlassPainter(
                              fillProgress: progress,
                              wavePhase: _waveAnimation.value,
                              dropProgress: _dropAnimation.value,
                              waterLight: _waterLight,
                              waterMid: _waterMid,
                              waterDark: _waterDark,
                              waterDeep: _waterDeep,
                              glassColor: _glassColor,
                              glassEdge: _glassEdge,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const Spacer(flex: 1),

                // Loading text
                AnimatedBuilder(
                  animation: _fillController,
                  builder: (context, child) {
                    final progress = _fillAnimation.value;
                    String text;
                    if (progress < 0.3) {
                      text = 'Đang chuẩn bị...';
                    } else if (progress < 0.6) {
                      text = 'Đang tải dữ liệu...';
                    } else if (progress < 0.9) {
                      text = 'Sắp xong rồi...';
                    } else {
                      text = 'Hoàn tất! 💧';
                    }
                    return Text(
                      text,
                      style: TextStyle(
                        fontSize: 14,
                        color: _waterDeep.withOpacity(0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter vẽ ly nước với nước rót vào
class _WaterGlassPainter extends CustomPainter {
  final double fillProgress;
  final double wavePhase;
  final double dropProgress;
  final Color waterLight;
  final Color waterMid;
  final Color waterDark;
  final Color waterDeep;
  final Color glassColor;
  final Color glassEdge;

  _WaterGlassPainter({
    required this.fillProgress,
    required this.wavePhase,
    required this.dropProgress,
    required this.waterLight,
    required this.waterMid,
    required this.waterDark,
    required this.waterDeep,
    required this.glassColor,
    required this.glassEdge,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Glass dimensions
    final glassTop = h * 0.18;
    final glassBottom = h * 0.92;
    final glassHeight = glassBottom - glassTop;
    final glassTopWidth = w * 0.7;
    final glassBottomWidth = w * 0.5;
    final glassCenterX = w / 2;

    // Glass shape path (trapezoid)
    Path glassPath() {
      final path = Path();
      path.moveTo(glassCenterX - glassTopWidth / 2, glassTop);
      path.lineTo(glassCenterX - glassBottomWidth / 2, glassBottom);
      path.lineTo(glassCenterX + glassBottomWidth / 2, glassBottom);
      path.lineTo(glassCenterX + glassTopWidth / 2, glassTop);
      path.close();
      return path;
    }

    // Draw glass background (transparent glass effect)
    final glassBgPaint = Paint()
      ..color = glassColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(glassPath(), glassBgPaint);

    // --- Water fill ---
    if (fillProgress > 0) {
      canvas.save();
      canvas.clipPath(glassPath());

      // Water level
      final waterMaxHeight = glassHeight * 0.88;
      final waterTop = glassBottom - waterMaxHeight * fillProgress;

      // Calculate glass width at water level
      final t = (waterTop - glassTop) / glassHeight;
      final waterWidthAtTop =
          glassBottomWidth + (glassTopWidth - glassBottomWidth) * (1 - t);

      // Water body with gradient
      final waterRect = Rect.fromLTRB(
        glassCenterX - waterWidthAtTop / 2 - 10,
        waterTop,
        glassCenterX + waterWidthAtTop / 2 + 10,
        glassBottom + 5,
      );
      final waterPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            waterLight.withOpacity(0.7),
            waterMid.withOpacity(0.85),
            waterDark.withOpacity(0.95),
          ],
        ).createShader(waterRect);

      // Draw wave surface
      final wavePath = Path();
      final waveAmplitude = 3.0 + 4.0 * (1 - fillProgress).clamp(0.0, 1.0);
      final waveFrequency = 3.0;

      wavePath.moveTo(0, glassBottom + 5);
      wavePath.lineTo(0, waterTop);

      for (double x = 0; x <= w; x += 1) {
        final normalizedX = (x - (glassCenterX - waterWidthAtTop / 2)) /
            waterWidthAtTop;
        final y = waterTop +
            waveAmplitude *
                math.sin(normalizedX * waveFrequency * 2 * math.pi + wavePhase) +
            waveAmplitude *
                0.5 *
                math.sin(normalizedX * waveFrequency * 4 * math.pi +
                    wavePhase * 1.5 +
                    1.0);
        wavePath.lineTo(x, y);
      }

      wavePath.lineTo(w, glassBottom + 5);
      wavePath.close();

      canvas.drawPath(wavePath, waterPaint);

      // Second wave layer (lighter, for depth effect)
      final wave2Path = Path();
      wave2Path.moveTo(0, glassBottom + 5);
      wave2Path.lineTo(0, waterTop + waveAmplitude);

      for (double x = 0; x <= w; x += 1) {
        final normalizedX = (x - (glassCenterX - waterWidthAtTop / 2)) /
            waterWidthAtTop;
        final y = waterTop +
            waveAmplitude +
            waveAmplitude *
                0.6 *
                math.sin(
                    normalizedX * waveFrequency * 2 * math.pi + wavePhase + math.pi);
        wave2Path.lineTo(x, y);
      }

      wave2Path.lineTo(w, glassBottom + 5);
      wave2Path.close();

      final wave2Paint = Paint()
        ..color = waterLight.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawPath(wave2Path, wave2Paint);

      // Bubbles
      final bubbleRng = math.Random(42);
      final bubblePaint = Paint()
        ..color = Colors.white.withOpacity(0.4)
        ..style = PaintingStyle.fill;
      for (int i = 0; i < 8; i++) {
        final bx = glassCenterX +
            (bubbleRng.nextDouble() - 0.5) * glassBottomWidth * 0.6;
        final baseY = glassBottom - bubbleRng.nextDouble() * waterMaxHeight * fillProgress * 0.8;
        final by = baseY -
            (math.sin(wavePhase + i * 1.3) * 8);
        final br = 2.0 + bubbleRng.nextDouble() * 4;
        if (by > waterTop && by < glassBottom) {
          canvas.drawCircle(Offset(bx, by), br, bubblePaint);
          // Bubble highlight
          canvas.drawCircle(
            Offset(bx - br * 0.3, by - br * 0.3),
            br * 0.3,
            Paint()..color = Colors.white.withOpacity(0.6),
          );
        }
      }

      canvas.restore();
    }

    // --- Water stream pouring from top ---
    if (fillProgress > 0 && fillProgress < 0.98) {
      final waterLevel = glassBottom - glassHeight * 0.88 * fillProgress;
      final streamTop = 0.0;
      final streamBottom = waterLevel;

      // Main stream
      final streamPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            waterLight.withOpacity(0.5),
            waterMid.withOpacity(0.7),
            waterDark.withOpacity(0.4),
          ],
        ).createShader(Rect.fromLTRB(
            glassCenterX - 6, streamTop, glassCenterX + 6, streamBottom));
      
      // Wavy stream
      final streamPath = Path();
      final streamWidth = 4.0 + 3.0 * math.sin(wavePhase * 2);
      streamPath.moveTo(glassCenterX - streamWidth, streamTop);
      
      for (double y = streamTop; y <= streamBottom; y += 2) {
        final wobble = math.sin(y * 0.05 + wavePhase * 3) * 2;
        final widthAtY = streamWidth * (0.8 + 0.4 * (y / streamBottom));
        streamPath.lineTo(glassCenterX + wobble - widthAtY, y);
      }
      
      for (double y = streamBottom; y >= streamTop; y -= 2) {
        final wobble = math.sin(y * 0.05 + wavePhase * 3) * 2;
        final widthAtY = streamWidth * (0.8 + 0.4 * (y / streamBottom));
        streamPath.lineTo(glassCenterX + wobble + widthAtY, y);
      }
      
      streamPath.close();
      canvas.drawPath(streamPath, streamPaint);

      // Splash drops at water surface
      final splashPaint = Paint()
        ..color = waterLight.withOpacity(0.6)
        ..style = PaintingStyle.fill;
      
      for (int i = 0; i < 4; i++) {
        final angle = (i / 4) * math.pi + wavePhase * 2;
        final dist = 8 + 12 * dropProgress;
        final dx = glassCenterX + math.cos(angle) * dist;
        final dy = waterLevel - 4 + math.sin(angle + math.pi / 3) * 6 * dropProgress;
        final dropSize = 2.5 * (1 - dropProgress);
        if (dropSize > 0.5) {
          canvas.drawCircle(Offset(dx, dy), dropSize, splashPaint);
        }
      }
    }

    // --- Glass outline ---
    final glassOutlinePaint = Paint()
      ..color = glassEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(glassPath(), glassOutlinePaint);

    // Glass rim (top ellipse)
    final rimPaint = Paint()
      ..color = glassEdge.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(glassCenterX, glassTop),
        width: glassTopWidth,
        height: 14,
      ),
      rimPaint,
    );

    // Glass shine reflection (left side)
    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withOpacity(0.2),
          Colors.white.withOpacity(0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromLTRB(
        glassCenterX - glassTopWidth / 2,
        glassTop,
        glassCenterX - glassTopWidth / 2 + 20,
        glassBottom,
      ));

    final shinePath = Path();
    shinePath.moveTo(glassCenterX - glassTopWidth / 2 + 5, glassTop + 10);
    shinePath.lineTo(glassCenterX - glassBottomWidth / 2 + 8, glassBottom - 10);
    shinePath.lineTo(glassCenterX - glassBottomWidth / 2 + 18, glassBottom - 10);
    shinePath.lineTo(glassCenterX - glassTopWidth / 2 + 15, glassTop + 10);
    shinePath.close();
    canvas.drawPath(shinePath, shinePaint);

    // Glass base / bottom
    final basePaint = Paint()
      ..color = glassEdge.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawLine(
      Offset(glassCenterX - glassBottomWidth / 2 - 4, glassBottom),
      Offset(glassCenterX + glassBottomWidth / 2 + 4, glassBottom),
      basePaint,
    );
    // Base stand
    canvas.drawLine(
      Offset(glassCenterX - glassBottomWidth / 2 - 8, glassBottom + 3),
      Offset(glassCenterX + glassBottomWidth / 2 + 8, glassBottom + 3),
      Paint()
        ..color = glassEdge.withOpacity(0.3)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WaterGlassPainter oldDelegate) => true;
}
