import 'package:flutter/widgets.dart';

class ChatScrollPolicy {
  const ChatScrollPolicy._();

  static const double nearBottomThreshold = 96;
  static const double bottomSnapTolerance = 0.5;
  static const int bottomSnapFrameBudget = 12;

  static bool isNearBottom({
    required double pixels,
    required double maxExtent,
  }) {
    return maxExtent - pixels <= nearBottomThreshold;
  }

  static bool shouldAutoScrollOnNewLastMessage({
    required bool wasNearBottom,
    required bool newestFromOwner,
  }) {
    return wasNearBottom || newestFromOwner;
  }

  static double offsetAfterPrepend({
    required double oldMaxExtent,
    required double oldOffset,
    required double newMaxExtent,
    required double minExtent,
    required double maxExtent,
  }) {
    final delta = newMaxExtent - oldMaxExtent;
    return (oldOffset + delta).clamp(minExtent, maxExtent).toDouble();
  }

  static void scheduleBottomSnap({
    required ScrollController controller,
    required bool Function() isActive,
    required bool animated,
    int remainingFrames = bottomSnapFrameBudget,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isActive() || !controller.hasClients) {
        return;
      }

      final target = controller.position.maxScrollExtent;
      final distance = (target - controller.position.pixels).abs();
      if (distance > bottomSnapTolerance) {
        if (animated && remainingFrames == bottomSnapFrameBudget) {
          controller.animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        } else {
          controller.jumpTo(target);
        }
      }

      if (remainingFrames <= 1) {
        return;
      }
      scheduleBottomSnap(
        controller: controller,
        isActive: isActive,
        animated: false,
        remainingFrames: remainingFrames - 1,
      );
    });
  }
}
