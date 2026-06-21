import 'package:flutter/material.dart';

/// A faint dotted world map used as a subtle backdrop behind the connect button
/// and the speed test. [color] tints the dots; [opacity] dims the whole map.
class DottedWorld extends StatelessWidget {
  final Color color;
  final double opacity;
  const DottedWorld({super.key, this.color = Colors.white, this.opacity = 0.10});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: ColorFiltered(
            // Recolour the map's dots to [color] (keeps their alpha).
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: Image.asset(
              'assets/images/world_map.png',
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          ),
        ),
      ),
    );
  }
}
