import 'dart:ui';
import 'package:flutter/material.dart';

class TruthLensColors {
  static const Color bgDeep = Color(0xFF050814);
  static const Color bgMid = Color(0xFF0B1026);
  static const Color surfaceGlass = Color(0xCC111936);
  static const Color surfaceCard = Color(0xFF121A36);
  static const Color neonPurple = Color(0xFFA855F7);
  static const Color neonCyan = Color(0xFF22D3EE);
  static const Color neonPink = Color(0xFFEC4899);
  static const Color neonEmerald = Color(0xFF34D399);
  static const Color neonAmber = Color(0xFFFBBF24);
  static const Color neonRose = Color(0xFFFB7185);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color borderPurple = Color(0x55A855F7);
  static const Color borderCyan = Color(0x5522D3EE);
}

ThemeData buildTruthLensTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: TruthLensColors.bgDeep,
    colorScheme: const ColorScheme.dark(
      primary: TruthLensColors.neonCyan,
      secondary: TruthLensColors.neonPurple,
      surface: TruthLensColors.surfaceCard,
      error: TruthLensColors.neonRose,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xE6060A1A),
      foregroundColor: TruthLensColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xCC070C1F),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TruthLensColors.borderPurple),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x4494A3B8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TruthLensColors.neonCyan, width: 1.5),
      ),
      labelStyle: const TextStyle(color: TruthLensColors.textMuted),
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF141C3A),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TruthLensColors.borderCyan),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class CyberBackground extends StatelessWidget {
  final Widget child;
  const CyberBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF050814),
            Color(0xFF0C102B),
            Color(0xFF061322),
          ],
        ),
      ),
      child: child,
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor = TruthLensColors.borderPurple,
    this.borderRadius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: TruthLensColors.surfaceGlass,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class NeonGradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final List<Color> colors;
  final bool loading;

  const NeonGradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.colors = const [TruthLensColors.neonPurple, TruthLensColors.neonCyan],
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(
                colors.first.red,
                colors.first.green,
                colors.first.blue,
                0.38,
              ),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF040712),
                      ),
                    )
                  else
                    Icon(icon, color: const Color(0xFF040712), size: 20),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF040712),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
