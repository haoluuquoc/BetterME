import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';

/// Splash Screen với animation loading giọt nước
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Nếu đã đăng nhập → Home, chưa → Login
        final authService = AuthService();
        if (authService.isLoggedIn) {
          Navigator.pushReplacementNamed(context, Routes.home);
        } else {
          Navigator.pushReplacementNamed(context, Routes.login);
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            
            // Logo / App Name
            const Icon(
              Icons.water_drop,
              size: 48,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              'BetterME',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const Spacer(flex: 2),
            
            // Water Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Column(
                    children: [
                      // Progress percentage
                      Text(
                        '${(_progressAnimation.value * 100).toInt()}%',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Water progress bar
                      Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            // Water fill
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _progressAnimation.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primaryLight,
                                      AppColors.accent,
                                    ],
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CustomPaint(
                                    painter: WavePainter(
                                      wavePhase: _waveAnimation.value * 2 * math.pi,
                                    ),
                                    size: const Size(double.infinity, 24),
                                  ),
                                ),
                              ),
                            ),
                            
                            // Water drops effect
                            if (_progressAnimation.value > 0.1)
                              Positioned(
                                left: (_progressAnimation.value * 
                                    (MediaQuery.of(context).size.width - 96)) - 8,
                                top: 4,
                                child: AnimatedOpacity(
                                  opacity: (_waveAnimation.value * 10 % 1) > 0.5 ? 1 : 0.5,
                                  duration: const Duration(milliseconds: 100),
                                  child: const Icon(
                                    Icons.water_drop,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      Text(
                        'Đang tải...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// Custom painter để vẽ hiệu ứng sóng nước
class WavePainter extends CustomPainter {
  final double wavePhase;

  WavePainter({required this.wavePhase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height);

    for (double x = 0; x <= size.width; x++) {
      final y = size.height * 0.5 + 
          4 * math.sin(x / size.width * 2 * math.pi + wavePhase);
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) {
    return oldDelegate.wavePhase != wavePhase;
  }
}
