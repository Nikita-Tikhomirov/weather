class ChatScrollPolicy {
  const ChatScrollPolicy._();

  static const double nearBottomThreshold = 96;

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
}
