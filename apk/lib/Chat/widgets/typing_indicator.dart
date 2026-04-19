import 'dart:async';
import 'package:flutter/material.dart';

/// Animated three-dot typing indicator.
/// The three dots pulse sequentially to simulate someone typing.
class TypingIndicatorWidget extends StatefulWidget {
  final Color dotColor;
  final double dotSize;

  const TypingIndicatorWidget({
    super.key,
    this.dotColor = Colors.white,
    this.dotSize = 7.0,
  });

  @override
  State<TypingIndicatorWidget> createState() => _TypingIndicatorWidgetState();
}

class _TypingIndicatorWidgetState extends State<TypingIndicatorWidget> {
  static const Duration _kAnimationInterval = Duration(milliseconds: 400);
  static const Duration _kFadeDuration = Duration(milliseconds: 250);

  // Which dot is currently "active" (enlarged + opaque)
  int _activeDot = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_kAnimationInterval, (_) {
      if (mounted) {
        setState(() {
          _activeDot = (_activeDot + 1) % 3;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final isActive = index == _activeDot;
        return AnimatedContainer(
          duration: _kFadeDuration,
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: isActive ? widget.dotSize + 2 : widget.dotSize,
          height: isActive ? widget.dotSize + 2 : widget.dotSize,
          decoration: BoxDecoration(
            color: widget.dotColor.withOpacity(isActive ? 1.0 : 0.45),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}
