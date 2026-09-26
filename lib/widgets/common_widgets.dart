import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/app_config.dart';

ImageProvider? getAvatarImageProvider(String? rawUrl) {
  if (rawUrl == null) return null;
  final url = rawUrl.trim();
  if (url.isEmpty) return null;

  if (url.startsWith('data:image') && url.contains('base64,')) {
    try {
      final base64String = url.split('base64,').last.trim();
      final Uint8List bytes = base64Decode(base64String);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    return NetworkImage(url);
  }

  if (url.startsWith('/')) {
    final origin = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/api/v1/?$'), '');
    return NetworkImage('$origin$url');
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
  if (rawUrl == null || rawUrl.trim().isEmpty) {
    if (errorBuilder != null) return Builder(builder: (ctx) => errorBuilder(ctx, 'empty', null));
    return const SizedBox();
  }

  final url = rawUrl.trim();

  if (url.startsWith('data:image') && url.contains('base64,')) {
    try {
      final base64String = url.split('base64,').last.trim();
      final Uint8List bytes = base64Decode(base64String);
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

  if (url.startsWith('/')) {
    final origin = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/api/v1/?$'), '');
    return Image.network(
      '$origin$url',
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }

  if (errorBuilder != null) return Builder(builder: (ctx) => errorBuilder(ctx, 'invalid url', null));
  return const SizedBox();
}

class RemoteAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final String fallback;
  const RemoteAvatar({super.key, this.url, this.radius = 28, this.fallback = 'U'});

  @override
  Widget build(BuildContext context) {
    final provider = getAvatarImageProvider(url);
    if (provider != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: provider,
        backgroundColor: const Color(0xFFFFECE5),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFF95B3D),
      child: Text(
        fallback.trim().isEmpty ? 'U' : fallback.trim().substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.75,
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

Future<bool> confirm(BuildContext context, String title, String message) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      ) ??
      false;
}

class LoadingBody extends StatelessWidget {
  final String label;
  const LoadingBody({super.key, this.label = 'Loading…'});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 12), Text(label)]));
}
