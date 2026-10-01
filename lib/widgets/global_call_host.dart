import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/active_call_manager.dart';
import '../screens/session/session_screen.dart';
import 'minimized_call_bar.dart';

class GlobalCallHost extends StatefulWidget {
  final Widget child;

  const GlobalCallHost({super.key, required this.child});

  @override
  State<GlobalCallHost> createState() => _GlobalCallHostState();
}

class _GlobalCallHostState extends State<GlobalCallHost> {
  final ActiveCallManager _manager = ActiveCallManager.instance;
  Widget? _activeSessionWidget;
  String? _lastSessionId;
  GlobalKey<NavigatorState>? _callNavigatorKey;

  Offset? _pipOffset;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _manager,
      builder: (context, _) {
        final session = _manager.activeSession;
        final hasCall = _manager.hasActiveCall;

        if (hasCall && session != null) {
          if (_lastSessionId != session.id || _activeSessionWidget == null) {
            _lastSessionId = session.id;
            _callNavigatorKey = GlobalKey<NavigatorState>();
            _activeSessionWidget = SessionScreen(
              key: ValueKey('call_${session.id}'),
              initialSession: session,
              callerSide: _manager.isCaller,
              isHostedInGlobalManager: true,
            );
          }
        } else {
          _activeSessionWidget = null;
          _lastSessionId = null;
          _callNavigatorKey = null;
          _pipOffset = null;
        }

        final mediaQuery = MediaQuery.of(context);
        final screenWidth = mediaQuery.size.width;
        final screenHeight = mediaQuery.size.height;
        final topPadding = mediaQuery.padding.top;
        final bottomPadding = mediaQuery.padding.bottom;

        // Dynamic width that fits phone screens while allowing horizontal movement & sticky docking
        final barWidth = screenWidth > 380 ? 340.0 : (screenWidth - 24.0);
        const barHeight = 68.0;

        // Default resting position (just above the bottom navigation bar)
        final defaultY = screenHeight - bottomPadding - 74.0 - barHeight;
        final defaultX = 12.0;

        final currentX = _pipOffset?.dx ?? defaultX;
        final currentY = _pipOffset?.dy ?? defaultY;

        return Stack(
          children: [
            // Underlying application content (fully interactive)
            widget.child,

            // Active Call Screen (Full Screen or Offstage when minimized)
            if (hasCall && _activeSessionWidget != null)
              Positioned.fill(
                child: Offstage(
                  offstage: _manager.isMinimized,
                  child: TickerMode(
                    enabled: !_manager.isMinimized,
                    child: HeroControllerScope.none(
                      child: Navigator(
                        key: _callNavigatorKey,
                        onGenerateRoute: (settings) => PageRouteBuilder(
                          pageBuilder: (ctx, anim1, anim2) => Material(
                            type: MaterialType.transparency,
                            child: _activeSessionWidget!,
                          ),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Draggable & Sticky Minimized Call Widget (when minimized)
            if (hasCall && _manager.isMinimized)
              AnimatedPositioned(
                duration: _isDragging ? Duration.zero : const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: currentX,
                top: currentY,
                width: barWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _manager.maximize();
                  },
                  onPanStart: (details) {
                    setState(() {
                      _isDragging = true;
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      final newX = (currentX + details.delta.dx).clamp(
                        8.0,
                        screenWidth - barWidth - 8.0,
                      );
                      final newY = (currentY + details.delta.dy).clamp(
                        topPadding + 10.0,
                        screenHeight - bottomPadding - barHeight - 12.0,
                      );
                      _pipOffset = Offset(newX, newY);
                    });
                  },
                  onPanEnd: (details) {
                    HapticFeedback.lightImpact();
                    final midPoint = (screenWidth - barWidth) / 2;
                    final stickyLeft = 12.0;
                    final stickyRight = screenWidth - barWidth - 12.0;

                    // Sticky to both sides: snaps cleanly to nearest side edge
                    final targetX = (currentX < midPoint) ? stickyLeft : stickyRight;
                    final targetY = currentY.clamp(
                      topPadding + 10.0,
                      screenHeight - bottomPadding - barHeight - 12.0,
                    );

                    setState(() {
                      _isDragging = false;
                      _pipOffset = Offset(targetX, targetY);
                    });
                  },
                  child: MinimizedCallBar(
                    callManager: _manager,
                    isDragging: _isDragging,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
