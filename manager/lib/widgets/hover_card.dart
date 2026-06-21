import 'package:flutter/material.dart';

import '../theme.dart';

/// A card that lifts and highlights its border on hover, for a responsive
/// desktop feel. Tapping anywhere triggers [onTap].
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: _hover
              ? (Matrix4.identity()..translateByDouble(0.0, -3.0, 0.0, 1.0))
              : Matrix4.identity(),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFF13294A) : LanwayColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover ? LanwayColors.accent : const Color(0x1AFFFFFF),
              width: _hover ? 1.5 : 1,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
