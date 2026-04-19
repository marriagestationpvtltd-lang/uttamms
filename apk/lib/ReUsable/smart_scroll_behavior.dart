// Smart Scrolling Behavior for Registration Forms
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Mixin to provide smart scrolling capabilities for form pages
/// Automatically scrolls to focused fields with smooth animations
mixin SmartScrollBehavior<T extends StatefulWidget> on State<T> {
  final ScrollController scrollController = ScrollController();
  final Map<FocusNode, GlobalKey> _fieldKeys = {};

  @override
  void dispose() {
    scrollController.dispose();
    // Remove listeners from all focus nodes
    for (final focusNode in _fieldKeys.keys) {
      focusNode.removeListener(() => _onFocusChange(focusNode));
    }
    super.dispose();
  }

  /// Register a form field for smart scrolling
  /// Call this for each field that should trigger auto-scroll
  void registerField(FocusNode focusNode, GlobalKey fieldKey) {
    _fieldKeys[focusNode] = fieldKey;
    focusNode.addListener(() => _onFocusChange(focusNode));
  }

  /// Unregister a form field
  void unregisterField(FocusNode focusNode) {
    focusNode.removeListener(() => _onFocusChange(focusNode));
    _fieldKeys.remove(focusNode);
  }

  /// Called when any registered field gains or loses focus
  void _onFocusChange(FocusNode focusNode) {
    if (focusNode.hasFocus) {
      _scrollToField(focusNode);
    }
  }

  /// Scroll to a specific field with smooth animation
  void _scrollToField(FocusNode focusNode) {
    final fieldKey = _fieldKeys[focusNode];
    if (fieldKey == null || fieldKey.currentContext == null) return;

    // Delay scroll until after the keyboard finishes animating (~300 ms).
    // Running a competing animation while the keyboard slides up causes jank.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (fieldKey.currentContext == null) return;

      final RenderBox? renderBox =
          fieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final RenderAbstractViewport? viewport =
          RenderAbstractViewport.of(renderBox);
      if (viewport == null) return;

      // Get the scroll offset needed to show the field
      final double fieldTop = viewport.getOffsetToReveal(renderBox, 0.0).offset;
      final double fieldBottom = viewport.getOffsetToReveal(renderBox, 1.0).offset;

      // Calculate the ideal position (field at 1/4 from top of viewport)
      final double viewportHeight = scrollController.position.viewportDimension;
      final double idealOffset = fieldTop - (viewportHeight * 0.25);

      // Calculate the keyboard height (approximate)
      final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

      // Adjust for keyboard if it's visible
      double targetOffset = idealOffset;
      if (keyboardHeight > 0) {
        // Position field above keyboard with some padding
        final double fieldHeight = fieldBottom - fieldTop;
        targetOffset = fieldTop - (viewportHeight - keyboardHeight - fieldHeight - 20);
      }

      // Ensure we don't scroll beyond bounds
      final double minScroll = scrollController.position.minScrollExtent;
      final double maxScroll = scrollController.position.maxScrollExtent;
      targetOffset = targetOffset.clamp(minScroll, maxScroll);

      // Only scroll if the field is not fully visible
      final double currentScroll = scrollController.offset;
      final double visibleTop = currentScroll;
      final double visibleBottom = currentScroll + viewportHeight - keyboardHeight;

      final bool isFullyVisible =
          fieldTop >= visibleTop && fieldBottom <= visibleBottom;

      if (!isFullyVisible) {
        scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Scroll to the first field with an error
  /// Useful for validation feedback
  void scrollToFirstError(List<FocusNode> errorFields) {
    if (errorFields.isEmpty) return;

    // Find the first error field that's registered
    for (final focusNode in errorFields) {
      if (_fieldKeys.containsKey(focusNode)) {
        _scrollToField(focusNode);
        // Optionally focus the field
        focusNode.requestFocus();
        break;
      }
    }
  }

  /// Scroll to a specific position smoothly
  void scrollToPosition(double offset) {
    scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Scroll to top of the form
  void scrollToTop() {
    scrollToPosition(0.0);
  }

  /// Scroll to bottom of the form
  void scrollToBottom() {
    scrollToPosition(scrollController.position.maxScrollExtent);
  }
}

/// Enhanced form field wrapper that automatically registers with smart scrolling
class SmartScrollField extends StatefulWidget {
  final Widget child;
  final FocusNode? focusNode;
  final GlobalKey? fieldKey;

  const SmartScrollField({
    Key? key,
    required this.child,
    this.focusNode,
    this.fieldKey,
  }) : super(key: key);

  @override
  State<SmartScrollField> createState() => _SmartScrollFieldState();
}

class _SmartScrollFieldState extends State<SmartScrollField> {
  late final GlobalKey _internalKey;
  late final FocusNode _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalKey = widget.fieldKey ?? GlobalKey();
    _internalFocusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _internalKey,
      child: widget.child,
    );
  }
}
