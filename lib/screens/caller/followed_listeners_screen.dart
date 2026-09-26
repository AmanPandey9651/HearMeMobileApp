import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import 'listener_detail_screen.dart';

class FollowedListenersScreen extends StatefulWidget {
  const FollowedListenersScreen({super.key});

  @override
  State<FollowedListenersScreen> createState() => _FollowedListenersScreenState();
}

class _FollowedListenersScreenState extends State<FollowedListenersScreen> {
  List<ListenerCardModel> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppController>().api;
      final results = await Future.wait<dynamic>([api.followedListeners(), api.allListeners()]);
      final followed = List<dynamic>.from(results[0] as List);
      final all = List<ListenerCardModel>.from(results[1] as List<ListenerCardModel>);
      final ids = followed
          .whereType<Map>()
          .map((e) => e['listenerId']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();
      if (mounted) {
        setState(() {
          items = all.where((e) => ids.contains(e.id)).toList();
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Favourite listeners')),
        body: loading
            ? const LoadingBody()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  children: [
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No favourites yet. Follow a listener to receive online alerts.')),
                      ),
                    ...items.map(
                      (listener) => ListTile(
                        leading: RemoteAvatar(url: listener.avatarUrl, fallback: listener.displayName),
                        title: Text(listener.displayName),
                        subtitle: Text('${listener.professionalTitle}\n${listener.presence.replaceAll('_', ' ')}'),
                        isThreeLine: true,
                        trailing: Text('₹${listener.audioRate.toStringAsFixed(0)}/min'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ListenerDetailScreen(listener: listener)),
                        ).then((_) => _load()),
                      ),
                    ),
                  ],
                ),
              ),
      );
}
