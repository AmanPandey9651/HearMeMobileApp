import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

void showShareAppSheet(BuildContext context, {String? referralCode}) {
  const appUrl = 'https://feelback.in';
  final shareMessage = referralCode != null && referralCode.isNotEmpty
      ? 'Hey! Check out FeelBack for confidential emotional support and conversations with empathetic listeners. Use my invite code $referralCode on signup to get free welcome coins: $appUrl'
      : 'Hey! Check out FeelBack for confidential emotional wellness and conversations with compassionate listeners: $appUrl';

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Share FeelBack with Friends',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Help friends discover a safe space to share their feelings.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // WhatsApp Option
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF25D366)),
              ),
              title: const Text('Share via WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Send directly to your WhatsApp chats', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(shareMessage)}');
                final webUri = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(shareMessage)}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  await launchUrl(webUri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            const Divider(height: 1),

            // Copy Link Option
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF95B3D).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.copy_rounded, color: Color(0xFFF95B3D)),
              ),
              title: const Text('Copy Invite Link', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Copy text to clipboard for SMS or social apps', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: shareMessage));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite message copied to clipboard!')),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
