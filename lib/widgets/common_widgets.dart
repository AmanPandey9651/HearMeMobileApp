import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/app_config.dart';
import '../main.dart';

String? normalizeAvatarUrl(String? rawUrl) {
  if (rawUrl == null) return null;
  var url = rawUrl.trim();
  if (url.isEmpty || url.toLowerCase() == 'null' || url.toLowerCase() == 'undefined') {
    return null;
  }

  // Prepend host if it is a relative API path
  if (url.startsWith('/')) {
    final origin = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/api/v1/?$'), '');
    url = '$origin$url';
  }

  // DiceBear dynamic raster format support:
  // Convert any DiceBear SVG requests to PNG because Flutter Android ImageDecoder does not support SVG format
  if (url.contains('dicebear.com')) {
    url = url.replaceAll('/svg?', '/png?');
    url = url.replaceAll('/svg/', '/png/');
    url = url.replaceAll(RegExp(r'/svg(?=[\?#]|$)'), '/png');
    url = url.replaceAll(RegExp(r'\.svg(?=[\?#]|$)'), '.png');
  }

  // Reject unhandled SVGs to prevent native Android ImageDecoderDecodeException
  final lower = url.toLowerCase();
  if (lower.startsWith('data:image/svg') ||
      lower.contains('.svg?') ||
      lower.endsWith('.svg')) {
    return null;
  }

  return url;
}

ImageProvider? getAvatarImageProvider(String? rawUrl) {
  final url = normalizeAvatarUrl(rawUrl);
  if (url == null || url.isEmpty) return null;

  if (url.startsWith('data:image') && url.contains('base64,')) {
    try {
      final base64String = url.split('base64,').last.trim();
      if (base64String.isEmpty) return null;
      final Uint8List bytes = base64Decode(base64String);
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    return NetworkImage(url);
  }

  return null;
}

Widget buildAvatarImage(
  String? rawUrl, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  final url = normalizeAvatarUrl(rawUrl);
  if (url == null || url.isEmpty) {
    if (errorBuilder != null) return Builder(builder: (ctx) => errorBuilder(ctx, 'empty or unsupported', null));
    return const SizedBox();
  }

  if (url.startsWith('data:image') && url.contains('base64,')) {
    try {
      final base64String = url.split('base64,').last.trim();
      if (base64String.isEmpty) {
        if (errorBuilder != null) return Builder(builder: (ctx) => errorBuilder(ctx, 'empty base64', null));
        return const SizedBox();
      }
      final Uint8List bytes = base64Decode(base64String);
      if (bytes.isEmpty) {
        if (errorBuilder != null) return Builder(builder: (ctx) => errorBuilder(ctx, 'empty bytes', null));
        return const SizedBox();
      }
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    } catch (e, stack) {
      if (errorBuilder != null) return Builder(builder: (ctx) => errorBuilder(ctx, e, stack));
      return const SizedBox();
    }
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }

  if (errorBuilder != null) return Builder(builder: (ctx) => errorBuilder(ctx, 'invalid url', null));
  return const SizedBox();
}

class RemoteAvatar extends StatefulWidget {
  final String? url;
  final double radius;
  final String fallback;
  const RemoteAvatar({super.key, this.url, this.radius = 28, this.fallback = 'U'});

  @override
  State<RemoteAvatar> createState() => _RemoteAvatarState();
}

class _RemoteAvatarState extends State<RemoteAvatar> {
  bool _loadFailed = false;

  @override
  void didUpdateWidget(covariant RemoteAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = normalizeAvatarUrl(widget.url);
    final provider = (_loadFailed || cleanUrl == null) ? null : getAvatarImageProvider(cleanUrl);
    final initial = widget.fallback.trim().isEmpty ? 'U' : widget.fallback.trim().substring(0, 1).toUpperCase();

    if (provider != null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundImage: provider,
        backgroundColor: const Color(0xFFFFECE5),
        onBackgroundImageError: (_, __) {
          if (mounted) setState(() => _loadFailed = true);
        },
        child: null,
      );
    }

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: const Color(0xFFF95B3D),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: widget.radius * 0.75,
        ),
      ),
    );
  }
}

String sanitizeErrorMessage(Object error) {
  final raw = error.toString().trim();
  final lower = raw.toLowerCase();

  if (lower.contains('cancelled by user') || lower.contains('payment processing cancelled')) {
    return 'You cancelled the checkout. No amount was debited from your account.';
  }
  if (lower.contains('no firebase app') || lower.contains('core/no-app')) {
    return 'Authentication service is initializing. Please try again or sign in with Google.';
  }
  if (lower.contains('minimum recharge amount') || lower.contains('less that 50') || lower.contains('less than 50')) {
    return 'Minimum recharge amount is ₹50.';
  }
  if (lower.contains('minimum withdrawal') || lower.contains('minimum withdrawal is')) {
    return 'Minimum withdrawal amount is ₹50.00.';
  }
  if (lower.contains('exceeds your available') || lower.contains('exceeds available balance')) {
    return 'Withdrawal amount exceeds your available balance.';
  }
  if (lower.contains('valid upi') || lower.contains('upi vpa')) {
    return 'Please enter a valid UPI ID (e.g. name@okhdfcbank or 9876543210@paytm).';
  }
  if (lower.contains('network_error') || lower.contains('failed host lookup') || lower.contains('socketexception')) {
    return 'Network connection issue. Please check your internet connection.';
  }

  // Remove technical prefixes
  var cleaned = raw
      .replaceAll(RegExp(r'^Exception:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^ApiException\s*(\[\d+\])?:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^Error:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^\[.*?\]\s*'), '');

  return cleaned.isNotEmpty ? cleaned : 'An unexpected issue occurred. Please try again.';
}

void showError(BuildContext context, Object error, {String? title}) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  // If this was a user cancellation, display as a friendly notice instead of an aggressive error
  if (lower.contains('cancelled by user') || lower.contains('payment processing cancelled')) {
    showNotice(
      context,
      title: 'Payment Cancelled',
      message: 'You cancelled the checkout. No amount was debited from your card or bank.',
      isWarning: true,
    );
    return;
  }

  final message = sanitizeErrorMessage(error);
  final displayTitle = title ?? 'Notice';

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: EdgeInsets.zero,
      elevation: 0,
      backgroundColor: Colors.transparent,
      duration: const Duration(seconds: 4),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF43F5E).withValues(alpha: 0.16),
                border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.error_outline_rounded, color: Color(0xFFFB7185), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showSuccess(BuildContext context, String message, {String? title}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: EdgeInsets.zero,
      elevation: 0,
      backgroundColor: Colors.transparent,
      duration: const Duration(seconds: 4),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withValues(alpha: 0.16),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ?? 'Success',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showNotice(BuildContext context, {required String title, required String message, bool isWarning = true}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final accentColor = isWarning ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8);

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: EdgeInsets.zero,
      elevation: 0,
      backgroundColor: Colors.transparent,
      duration: const Duration(seconds: 4),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.16),
                border: Border.all(color: accentColor.withValues(alpha: 0.4)),
              ),
              child: Icon(
                isWarning ? Icons.info_outline_rounded : Icons.lightbulb_outline_rounded,
                color: accentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

BuildContext getSafeNavigatorContext(BuildContext context) {
  if (Navigator.maybeOf(context) != null) {
    return context;
  }
  final overlayCtx = TalkStrangersApp.navigatorKey.currentState?.overlay?.context;
  if (overlayCtx != null && Navigator.maybeOf(overlayCtx) != null) {
    return overlayCtx;
  }
  return context;
}

Future<bool> confirm(BuildContext context, String title, String message) async {
  final targetContext = getSafeNavigatorContext(context);
  final hasLocalNav = Navigator.maybeOf(targetContext) != null;

  final res = await showDialog<bool>(
    context: targetContext,
    barrierDismissible: false,
    useRootNavigator: !hasLocalNav,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFFFAF5EE),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
      content: Text(
        message,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF64748B),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () {
            if (Navigator.of(dialogCtx).canPop()) {
              Navigator.of(dialogCtx).pop(false);
            }
          },
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF95B3D),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            if (Navigator.of(dialogCtx).canPop()) {
              Navigator.of(dialogCtx).pop(true);
            }
          },
          child: const Text(
            'Continue',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  return res ?? false;
}

class LoadingBody extends StatelessWidget {
  final String label;
  const LoadingBody({super.key, this.label = 'Loading…'});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 12), Text(label)]));
}
