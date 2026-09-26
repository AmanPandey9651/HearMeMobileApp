import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';

class ScheduleConsultationScreen extends StatefulWidget {
  final ListenerCardModel listener;
  final double audioRate;
  final double videoRate;

  const ScheduleConsultationScreen({
    super.key,
    required this.listener,
    required this.audioRate,
    required this.videoRate,
  });

  @override
  State<ScheduleConsultationScreen> createState() => _ScheduleConsultationScreenState();
}

class _ScheduleConsultationScreenState extends State<ScheduleConsultationScreen> {
  DateTime date = DateTime.now().add(const Duration(days: 1));
  int duration = 30;
  String type = 'AUDIO';
  List<dynamic> slots = [];
  Map<String, dynamic>? selectedSlot;
  WalletModel? wallet;
  final agenda = TextEditingController();
  bool loading = true;
  bool submitting = false;

  double get rate => type == 'VIDEO' ? widget.videoRate : widget.audioRate;
  double get estimatedHold => rate * duration;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    agenda.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final api = context.read<AppController>().api;
      final day = DateFormat('yyyy-MM-dd').format(date);
      final result = await Future.wait<dynamic>([
        api.availableSlots(widget.listener.id, day, 'Asia/Kolkata', duration: duration),
        api.wallet(),
      ]);
      if (!mounted) return;
      setState(() {
        slots = List<dynamic>.from(result[0] as List).where((raw) {
          if (raw is! Map) return false;
          final m = Map<String, dynamic>.from(raw);
          return m['available'] != false;
        }).toList();
        selectedSlot = null;
        wallet = result[1] as WalletModel;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showError(context, e);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: date.isBefore(now) ? now : date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() => date = picked);
    await _load();
  }

  String _slotLabel(Map<String, dynamic> slot) {
    final local = '${slot['startTimeLocal'] ?? ''}'.trim();
    if (local.isNotEmpty) return local;
    final dt = DateTime.tryParse('${slot['startTimeUtc'] ?? ''}')?.toLocal();
    if (dt != null) return DateFormat('h:mm a').format(dt);
    return '${slot['startTimeUtc'] ?? 'Available slot'}';
  }

  Future<void> _confirm() async {
    final slot = selectedSlot;
    if (slot == null) {
      showError(context, 'Choose an available time slot.');
      return;
    }
    if (agenda.text.trim().isEmpty) {
      showError(context, 'Please provide a short consultation objective.');
      return;
    }
    final start = '${slot['startTimeUtc'] ?? ''}';
    if (start.isEmpty) {
      showError(context, 'The selected slot does not contain a valid start time.');
      return;
    }
    setState(() => submitting = true);
    try {
      final booking = await context.read<AppController>().api.createBooking(
            expertId: widget.listener.id,
            startTime: start,
            durationMinutes: duration,
            consultationType: type,
            agenda: agenda.text.trim(),
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Consultation booked'),
          content: Text('Reference: ${booking.bookingReference}\n${widget.listener.displayName}\n${_slotLabel(slot)} • $duration min • $type'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule consultation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: RemoteAvatar(url: widget.listener.avatarUrl, fallback: widget.listener.displayName),
              title: Text(widget.listener.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(widget.listener.professionalTitle),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'AUDIO', icon: const Icon(Icons.call), label: Text('Audio ₹${widget.audioRate.toStringAsFixed(0)}/min')),
              ButtonSegment(value: 'VIDEO', icon: const Icon(Icons.videocam), label: Text('Video ₹${widget.videoRate.toStringAsFixed(0)}/min')),
            ],
            selected: {type},
            onSelectionChanged: (v) => setState(() => type = v.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(DateFormat('EEE, dd MMM yyyy').format(date)),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 135,
              child: DropdownButtonFormField<int>(
                value: duration,
                decoration: const InputDecoration(labelText: 'Duration'),
                items: const [15, 30, 45, 60].map((m) => DropdownMenuItem(value: m, child: Text('$m min'))).toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => duration = v);
                  await _load();
                },
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Available times', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (slots.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No available slots for this date and duration. Try another date.')))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: slots.map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                final selected = selectedSlot != null && '${selectedSlot!['startTimeUtc']}' == '${m['startTimeUtc']}';
                return ChoiceChip(
                  label: Text(_slotLabel(m)),
                  selected: selected,
                  onSelected: (_) => setState(() => selectedSlot = m),
                );
              }).toList(),
            ),
          const SizedBox(height: 18),
          TextField(
            controller: agenda,
            minLines: 4,
            maxLines: 7,
            decoration: InputDecoration(
              labelText: 'Consultation objective / questions *',
              helperText: 'This is shared with ${widget.listener.displayName} before the scheduled consultation.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.account_balance_wallet_outlined),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Prepaid wallet balance', style: TextStyle(fontWeight: FontWeight.bold))),
                  Text(wallet?.formattedBalance ?? '—', style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 7),
                const Text('The backend applies authoritative connected-time billing and releases any unused authorization according to the booking rules.'),
                const SizedBox(height: 7),
                Text('Estimated maximum for $duration min: ₹${estimatedHold.toStringAsFixed(2)}'),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: submitting || loading ? null : _confirm,
            icon: const Icon(Icons.lock_outline),
            label: Text(submitting ? 'Confirming…' : 'Confirm scheduled consultation'),
          ),
          const SizedBox(height: 70),
        ],
      ),
    );
  }
}
