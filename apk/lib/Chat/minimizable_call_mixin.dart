import 'package:flutter/material.dart';
import 'call_overlay_manager.dart';

/// Mixin to add minimize functionality to call screens
mixin MinimizableCallMixin<T extends StatefulWidget> on State<T> {
  /// Build minimize button for the call screen
  Widget buildMinimizeButton({
    required VoidCallback onMinimize,
    Color color = Colors.white,
  }) {
    return IconButton(
      onPressed: onMinimize,
      icon: Icon(
        Icons.minimize,
        color: color,
        size: 28,
      ),
      tooltip: 'Minimize call',
    );
  }

  /// Minimize the current call
  void minimizeCall({
    required BuildContext context,
    required String callType,
    required String otherUserName,
    required String otherUserId,
    required String currentUserId,
    required String currentUserName,
  }) {
    CallOverlayManager().startCall(
      callType: callType,
      otherUserName: otherUserName,
      otherUserId: otherUserId,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      onMaximize: () {
        // When maximized, the call screen should be brought back
        // This will be handled by navigation
      },
      onEnd: () {
        // When ended from overlay, pop the screen if still mounted
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
    );

    // Minimize the call in the manager
    CallOverlayManager().minimizeCall();

    // Pop the current screen
    Navigator.of(context).pop();
  }
}

/// Wrapper widget to add minimize button to existing call screens
class MinimizableCallWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback onMinimize;
  final String title;

  const MinimizableCallWrapper({
    super.key,
    required this.child,
    required this.onMinimize,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black87,
        actions: [
          IconButton(
            onPressed: onMinimize,
            icon: const Icon(
              Icons.minimize,
              color: Colors.white,
              size: 28,
            ),
            tooltip: 'Minimize call',
          ),
        ],
      ),
      body: child,
    );
  }
}
