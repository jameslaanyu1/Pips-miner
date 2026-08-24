import 'package:flutter/material.dart';

import 'package:pips_miner_app/providers/bot_provider.dart';
import 'package:pips_miner_app/services/broker_search_service.dart';
import 'package:pips_miner_app/services/secure_storage_service.dart';
import 'package:pips_miner_app/theme/app_theme.dart';

class BrokerServerSelection {
  const BrokerServerSelection({required this.broker, required this.server});

  final String broker;
  final String server;
}

class BrokerConnectionSection extends StatelessWidget {
  final BotProvider bot;
  final SecureStorageService storage;
  final Future<void> Function(BotProvider) onConnect;
  final TextEditingController brokerController;
  final TextEditingController loginController;
  final TextEditingController serverController;
  final TextEditingController passwordController;

  const BrokerConnectionSection({
    super.key,
    required this.bot,
    required this.storage,
    required this.onConnect,
    required this.brokerController,
    required this.loginController,
    required this.serverController,
    required this.passwordController,
  });

  Future<void> _selectBrokerServer(BuildContext context) async {
    if (bot.isBotRunning) return;

    final selection = await showDialog<BrokerServerSelection>(
      context: context,
      builder: (_) => _BrokerServerSearchDialog(
        initialQuery: brokerController.text.trim(),
      ),
    );

    if (selection == null) return;

    brokerController.text = selection.broker;
    serverController.text = selection.server;
  }

  @override
  Widget build(BuildContext context) {
    final selectedServer = serverController.text.trim();
    final selectedBroker = brokerController.text.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'MT5 CONNECTION', icon: Icons.link_rounded),
            const SizedBox(height: 7),
            const Text(
              'Search a broker, choose its MT5 server, then enter your account credentials.',
              style: TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
            const SizedBox(height: 17),
            InkWell(
              onTap: bot.isBotRunning ? null : () => _selectBrokerServer(context),
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'BROKER SERVER',
                  prefixIcon: const Icon(Icons.dns_outlined),
                  suffixIcon: Icon(
                    bot.isBotRunning
                        ? Icons.lock_outline_rounded
                        : Icons.search_rounded,
                  ),
                ),
                child: selectedServer.isEmpty
                    ? const Text(
                        'Tap to search for your broker',
                        style: TextStyle(color: Colors.white38),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedServer,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (selectedBroker.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              selectedBroker,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
            _Field(
              controller: loginController,
              label: 'MT5 ACCOUNT NUMBER',
              icon: Icons.account_balance_wallet_outlined,
              keyboardType: TextInputType.number,
              enabled: !bot.isBotRunning,
            ),
            const SizedBox(height: 10),
            _Field(
              controller: passwordController,
              label: 'MT5 TRADING PASSWORD',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              enabled: !bot.isBotRunning,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: bot.isBotRunning ? null : () => onConnect(bot),
                icon: const Icon(Icons.link_rounded),
                label: const Text(
                  'CONNECT MT5 ACCOUNT',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ),
            if (bot.isConnected) ...[
              const SizedBox(height: 12),
              const _ConnectionStatus(
                connected: true,
                message: 'MT5 CONNECTED • PIPS-MINER READY',
              ),
            ],
            if (bot.connectionError != null) ...[
              const SizedBox(height: 12),
              _ConnectionStatus(
                connected: false,
                message: bot.connectionError!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BrokerServerSearchDialog extends StatefulWidget {
  const _BrokerServerSearchDialog({this.initialQuery = ''});

  final String initialQuery;

  @override
  State<_BrokerServerSearchDialog> createState() => _BrokerServerSearchDialogState();
}

class _BrokerServerSearchDialogState extends State<_BrokerServerSearchDialog> {
  late final TextEditingController _controller;
  final BrokerSearchService _service = BrokerSearchService.instance;
  bool _loading = false;
  String? _error;
  List<BrokerServerGroup> _results = const [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) {
      setState(() {
        _error = 'Enter at least 2 characters of the broker name.';
        _results = const [];
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
    });

    try {
      final results = await _service.search(query);
      if (!mounted) return;

      setState(() {
        _results = results;
        _loading = false;
        _error = results.isEmpty
            ? 'No MT5 servers were found for "$query".'
            : null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverCount = _results.fold<int>(
      0,
      (sum, group) => sum + group.servers.length,
    );

    return AlertDialog(
      title: const Text('Search broker server'),
      content: SizedBox(
        width: double.maxFinite,
        height: serverCount > 0 ? 380 : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(
                labelText: 'BROKER NAME',
                hintText: 'e.g. HFM, Exness, XM',
                prefixIcon: Icon(Icons.business_rounded),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: Text(_loading ? 'SEARCHING...' : 'SEARCH SERVERS'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTheme.warningColor,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            if (serverCount > 0) ...[
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
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
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(
                            server,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(group.broker),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).pop(
                              BrokerServerSelection(
                                broker: group.broker,
                                server: server,
                              ),
                            );
                          },
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool enabled;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 9.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  final bool connected;
  final String message;

  const _ConnectionStatus({required this.connected, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppTheme.successColor : AppTheme.errorColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.20)),
      ),
      child: Row(
        children: [
          Icon(
            connected
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
