import 'package:flutter/material.dart';

import '../services/broker_search_service.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

class EnhancedSettingsScreen extends StatefulWidget {
  const EnhancedSettingsScreen({super.key});

  @override
  State<EnhancedSettingsScreen> createState() => _EnhancedSettingsScreenState();
}

class _EnhancedSettingsScreenState extends State<EnhancedSettingsScreen> {
  int _settingsRevision = 0;

  Future<void> _openBrokerSearch() async {
    final selectedServer = await showDialog<String>(
      context: context,
      builder: (_) => const _BrokerServerSearchDialog(),
    );

    if (!mounted || selectedServer == null || selectedServer.trim().isEmpty) {
      return;
    }

    final storage = SecureStorageService();
    final login = await storage.getMt5Login() ?? '';
    await storage.saveMt5Connection(login: login, server: selectedServer);

    if (!mounted) return;
    setState(() => _settingsRevision++);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Broker server selected: $selectedServer')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SettingsScreen(key: ValueKey(_settingsRevision)),
        const _SettingsBrandOverlay(),
        Positioned(
          top: 91,
          right: 18,
          child: _BrokerSearchButton(onPressed: _openBrokerSearch),
        ),
      ],
    );
  }
}

class _SettingsBrandOverlay extends StatelessWidget {
  const _SettingsBrandOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 82,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          color: AppTheme.darkBg,
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.accentColor.withOpacity(.30)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/pips_miner_pro_icon.png', fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pips-Miner', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                  SizedBox(height: 2),
                  Text('life changing pips', style: TextStyle(color: AppTheme.accentColor, fontSize: 9.5, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrokerSearchButton extends StatelessWidget {
  const _BrokerSearchButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.darkSurfaceVariant,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.accentColor.withOpacity(.35)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded, size: 17, color: AppTheme.accentColor),
              SizedBox(width: 6),
              Text('FIND BROKER SERVER', style: TextStyle(color: AppTheme.accentColor, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: .5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrokerServerSearchDialog extends StatefulWidget {
  const _BrokerServerSearchDialog();

  @override
  State<_BrokerServerSearchDialog> createState() => _BrokerServerSearchDialogState();
}

class _BrokerServerSearchDialogState extends State<_BrokerServerSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  final BrokerSearchService _service = BrokerSearchService.instance;
  bool _loading = false;
  String? _error;
  List<BrokerServerGroup> _results = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) {
      setState(() => _error = 'Enter at least 2 characters of the broker name.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });
    try {
      final results = await _service.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        _error = results.isEmpty ? 'No known MT5 servers matched "$query".' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = error.toString().replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverCount = _results.fold<int>(0, (sum, group) => sum + group.servers.length);
    return AlertDialog(
      title: const Text('Find MT5 broker server'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(labelText: 'BROKER NAME', hintText: 'e.g. IC Markets, Exness, XM', prefixIcon: Icon(Icons.business_rounded)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _search,
                icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search_rounded),
                label: Text(_loading ? 'SEARCHING...' : 'SEARCH SERVERS'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: AppTheme.warningColor, fontSize: 11))),
            ],
            if (serverCount > 0) ...[
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: serverCount,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    var offset = 0;
                    for (final group in _results) {
                      if (index < offset + group.servers.length) {
                        final server = group.servers[index - offset];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(server, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(group.broker),
                          leading: const Icon(Icons.dns_outlined),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).pop(server),
                        );
                      }
                      offset += group.servers.length;
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCEL'))],
    );
  }
}
