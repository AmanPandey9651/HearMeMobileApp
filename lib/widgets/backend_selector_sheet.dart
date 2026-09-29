import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_config.dart';
import '../core/app_controller.dart';

Future<void> showBackendSelectorSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const BackendSelectorSheet(),
  );
}

class BackendSelectorSheet extends StatefulWidget {
  const BackendSelectorSheet({super.key});

  @override
  State<BackendSelectorSheet> createState() => _BackendSelectorSheetState();
}

class _BackendSelectorSheetState extends State<BackendSelectorSheet> {
  late AppEnvironment _selectedEnv;
  late TextEditingController _customUrlController;
  final Map<AppEnvironment, HealthResult?> _healthMap = {};
  final Map<AppEnvironment, bool> _testingMap = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedEnv = AppConfig.currentEnvironment;
    _customUrlController = TextEditingController(text: AppConfig.customUrl ?? '');
    // Auto-test current active environment
    _testHealth(_selectedEnv);
  }

  @override
  void dispose() {
    _customUrlController.dispose();
    super.dispose();
  }

  String _getHostForEnv(AppEnvironment env) {
    if (env == AppEnvironment.custom) {
      final text = _customUrlController.text.trim();
      return text.isEmpty ? 'http://192.168.1.x:8080' : text;
    }
    return env.defaultHost;
  }

  Future<void> _testHealth(AppEnvironment env) async {
    setState(() => _testingMap[env] = true);
    final host = _getHostForEnv(env);
    final result = await AppConfig.checkHealth(host);
    if (!mounted) return;
    setState(() {
      _healthMap[env] = result;
      _testingMap[env] = false;
    });
  }

  Future<void> _saveAndSwitch() async {
    setState(() => _saving = true);
    try {
      final custom = _selectedEnv == AppEnvironment.custom ? _customUrlController.text.trim() : null;
      await AppConfig.setEnvironment(_selectedEnv, customUrl: custom);

      if (!mounted) return;
      final controller = context.read<AppController>();
      await controller.reconnectBackend();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${_selectedEnv.displayName} (${AppConfig.currentHost})'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to switch backend: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFAF5EE),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF95B3D).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.dns_rounded, color: Color(0xFFF95B3D), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Backend Connection',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                    ),
                    Text(
                      'Current: ${AppConfig.currentHost}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Environment Cards
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildEnvCard(
                    env: AppEnvironment.local,
                    title: '1. Local Development',
                    url: !kIsWeb && Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080',
                    subtitle: !kIsWeb && Platform.isAndroid
                        ? 'Host machine: http://10.0.2.2:8080 (Android Emulator)'
                        : 'Local machine: http://localhost:8080',
                    icon: Icons.computer_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildEnvCard(
                    env: AppEnvironment.netlify,
                    title: '2. Netlify / Render (Staging)',
                    url: 'https://hearmebackendd.onrender.com',
                    subtitle: 'Live cloud backend (health: /health)',
                    icon: Icons.cloud_done_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildEnvCard(
                    env: AppEnvironment.production,
                    title: '3. Production',
                    url: 'https://www.feelback.in',
                    subtitle: 'Main feelback.in service',
                    icon: Icons.public_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildCustomCard(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveAndSwitch,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 20),
                  label: Text(_saving ? 'Connecting...' : 'Apply & Reconnect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF95B3D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnvCard({
    required AppEnvironment env,
    required String title,
    required String url,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedEnv == env;
    final health = _healthMap[env];
    final isTesting = _testingMap[env] == true;

    return InkWell(
      onTap: () {
        setState(() => _selectedEnv = env);
        if (_healthMap[env] == null) _testHealth(env);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFFF95B3D) : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFF95B3D).withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? const Color(0xFFF95B3D) : const Color(0xFF9CA3AF),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 20, color: const Color(0xFF4B5563)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Test Connection',
                  icon: isTesting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 18),
                  onPressed: isTesting ? null : () => _testHealth(env),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    url,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 6),
                  _buildHealthBadge(health, isTesting),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomCard() {
    final isSelected = _selectedEnv == AppEnvironment.custom;
    final health = _healthMap[AppEnvironment.custom];
    final isTesting = _testingMap[AppEnvironment.custom] == true;

    return InkWell(
      onTap: () {
        setState(() => _selectedEnv = AppEnvironment.custom);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFFF95B3D) : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? const Color(0xFFF95B3D) : const Color(0xFF9CA3AF),
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Icon(Icons.settings_ethernet_rounded, size: 20, color: Color(0xFF4B5563)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Custom Server (IP/Host)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                ),
                IconButton(
                  tooltip: 'Test Connection',
                  icon: isTesting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 18),
                  onPressed: isTesting ? null : () => _testHealth(AppEnvironment.custom),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _customUrlController,
                      decoration: InputDecoration(
                        hintText: 'e.g. http://192.168.1.100:8080',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      onChanged: (_) {
                        setState(() {
                          _healthMap[AppEnvironment.custom] = null;
                        });
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildHealthBadge(health, isTesting),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthBadge(HealthResult? health, bool isTesting) {
    if (isTesting) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
          SizedBox(width: 6),
          Text('Testing connection...', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        ],
      );
    }
    if (health == null) {
      return const Text('Tap refresh to test health', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)));
    }

    final isOk = health.isHealthy;
    final color = isOk ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final bg = isOk ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOk ? Icons.check_circle : Icons.error_outline, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            isOk ? '${health.status} (${health.latencyMs}ms)' : health.status,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
          if (isOk && health.message.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text('• ${health.message}', style: TextStyle(fontSize: 11, color: color)),
          ],
        ],
      ),
    );
  }
}
