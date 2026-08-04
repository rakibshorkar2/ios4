import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Apple Liquid Glass floating bottom navigation bar.
///
/// Renders the iOS 26-style floating glass pill with a frosted capsule
/// indicator, spring physics, subtle glow and magnification for the
/// selected tab. All five tabs, their order, labels and icons are
/// identical to the previous navigation bar.
class LiquidGlassNavBar extends StatelessWidget {
  const LiquidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  static const List<GlassTab> _tabs = [
    GlassTab(icon: Icon(Icons.explore), label: 'Browser'),
    GlassTab(icon: Icon(Icons.download), label: 'Downloads'),
    GlassTab(icon: Icon(Icons.security), label: 'Proxy'),
    GlassTab(icon: Icon(Icons.language), label: 'BRWSR'),
    GlassTab(icon: Icon(Icons.settings), label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedColor = scheme.primary;
    final unselectedColor = scheme.onSurface.withValues(alpha: 0.55);
    final indicatorColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.62);
    final backdropTint = isDark ? scheme.surfaceContainerHighest : Colors.white;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            backdropTint.withValues(alpha: 0.0),
            backdropTint.withValues(alpha: 0.0),
            backdropTint.withValues(alpha: 0.30),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: GlassTabBar.bottom(
        tabs: _tabs,
        selectedIndex: currentIndex,
        onTabSelected: onTabSelected,
        barHeight: 62,
        barBorderRadius: 31,
        spacing: 8,
        horizontalPadding: 20,
        verticalPadding: 20,
        iconSize: 24,
        iconLabelSpacing: 4,
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        selectedIconColor: selectedColor,
        selectedLabelColor: selectedColor,
        unselectedIconColor: unselectedColor,
        unselectedLabelColor: unselectedColor,
        indicatorColor: indicatorColor,
        indicatorExpansion:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        indicatorPinchStrength: 0.3,
        innerBlur: 10,
        magnification: 1.12,
        glowDuration: const Duration(milliseconds: 240),
        glowBlurRadius: 26,
        glowSpreadRadius: 6,
        glowOpacity: 0.30,
        interactionGlowColor: selectedColor.withValues(alpha: 0.12),
        interactionGlowRadius: 1.2,
        pressScale: 1.03,
        enableBlend: true,
        blendAmount: 10,
        quality: GlassQuality.standard,
        settings: const LiquidGlassSettings(
          blur: 12,
          thickness: 24,
          saturation: 1.35,
          lightIntensity: 0.55,
          fresnelStrength: 1.15,
          chromaticAberration: 0.015,
          specularSharpness: GlassSpecularSharpness.medium,
          shadowElevation: 1.8,
        ),
        indicatorSettings: const LiquidGlassSettings(
          blur: 6,
          thickness: 18,
          fresnelStrength: 1.3,
          specularSharpness: GlassSpecularSharpness.soft,
        ),
      ),
    );
  }
}
