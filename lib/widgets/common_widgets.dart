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

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: const Color(0xFF10B981),
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
