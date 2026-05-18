import 'package:flutter/material.dart';

/// True when the OS-level "Reduce Motion" / animation toggle is **off**.
/// Use to gate non-essential animations — repeating pulses, looping spinners,
/// auto-playing carousels. Required for WCAG 2.3.3 / 2.2.2.
bool shouldAnimate(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  return mq == null ? true : !mq.disableAnimations;
}

/// Drop-in for `onPlay: (c) => c.repeat(...)` on `.animate(...)`.
/// Returns `null` when reduced motion is active, which leaves the animation
/// at its initial frame instead of looping.
void Function(AnimationController)? repeatIfMotion(
  BuildContext context, {
  bool reverse = false,
}) {
  if (!shouldAnimate(context)) return null;
  return (controller) => controller.repeat(reverse: reverse);
}
