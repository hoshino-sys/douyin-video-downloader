import 'dart:async';

import 'package:flutter/material.dart';

class AppToast {
  static OverlayEntry? _entry;
  static Timer? _timer;
  static final GlobalKey<_ToastCardState> _cardKey = GlobalKey();

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
    bool success = true,
  }) {
    _timer?.cancel();
    _entry?.remove();
    _entry = null;
    final entry = OverlayEntry(
      builder: (_) => _ToastCard(
        key: _cardKey,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        success: success,
        onExit: () {
          _timer?.cancel();
          _timer = null;
          _entry?.remove();
          _entry = null;
        },
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _timer = Timer(duration, () => _cardKey.currentState?.requestExit());
  }
}

class _ToastCard extends StatefulWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool success;
  final VoidCallback onExit;

  const _ToastCard({
    super.key,
    required this.message,
    required this.onExit,
    this.actionLabel,
    this.onAction,
    this.success = true,
  });

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.6),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void requestExit() => _exit();

  void _exit() {
    if (_exiting) return;
    _exiting = true;
    _controller.reverse().whenCompleteOrCancel(widget.onExit);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 56,
      child: SafeArea(
        child: Center(
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: _exit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xF0202020),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.success
                              ? Icons.check_circle_rounded
                              : Icons.info_rounded,
                          size: 18,
                          color: widget.success
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (widget.actionLabel != null &&
                            widget.onAction != null) ...[
                          const SizedBox(width: 14),
                          GestureDetector(
                            onTap: () {
                              widget.onAction!();
                              _exit();
                            },
                            child: Text(
                              widget.actionLabel!,
                              style: const TextStyle(
                                color: Color(0xFFFF7A9C),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
