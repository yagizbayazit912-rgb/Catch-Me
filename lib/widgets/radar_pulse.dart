import 'package:flutter/material.dart';

/// Green player marker with an expanding-and-fading radar wave.
/// Represents the user's current location at the center of the map.
class RadarPulse extends StatefulWidget {
  const RadarPulse({
    super.key,
    this.color = const Color(0xFF3C7650),
    this.dotSize = 16,
    this.maxRadius = 60,
    this.duration = const Duration(milliseconds: 1500),
  });

  final Color color;
  final double dotSize;
  final double maxRadius;
  final Duration duration;

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.maxRadius * 2,
      height: widget.maxRadius * 2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value; // 0.0 -> 1.0
          final radius = widget.maxRadius * progress;
          final opacity = (1.0 - progress).clamp(0.0, 1.0);

          return Stack(
            alignment: Alignment.center,
            children: [
              // Expanding radar wave.
              Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: opacity * 0.4),
                    width: 2,
                  ),
                  color: widget.color.withValues(alpha: opacity * 0.15),
                ),
              ),
              // Fixed center dot representing the user's location.
              child!,
            ],
          );
        },
        child: Container(
          width: widget.dotSize,
          height: widget.dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.2),
                blurRadius: 5,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
