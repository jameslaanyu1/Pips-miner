import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/bot_provider.dart';
import '../services/app_update_service.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/broker_aware_symbol_section.dart';
import '../widgets/broker_connection_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SecureStorageService _storage = SecureStorageService();
  final _brokerController = TextEditingController();
  final _loginController = TextEditingController();
  final _serverController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConnection();
  }

  @override
  void dispose() {
    _brokerController.dispose();
    _loginController.dispose();
    _serverController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadConnection() async {
    final broker = await _storage.getMt5Broker();
    final login = await _storage.getMt5Login();
    final server = await _storage.getMt5Server();
    final password = await _storage.getMt5Password();
    if (!mounted) return;
    setState(() {
      _brokerController.text = broker ?? '';
      _loginController.text = login ?? '';
      _serverController.text = server ?? '';
      _passwordController.text = password ?? '';
    });
  }

  Future<void> _connect(BotProvider bot) async {
    final broker = _brokerController.text.trim();
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    final server = _serverController.text.trim();
    if (login.isEmpty || password.isEmpty || server.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a broker server, then enter your MT5 account number and trading password.')),
      );
      return;
    }
    final success = await bot.connectMt5(login: login, password: password, server: server);
    if (success) {
      await _storage.saveMt5Connection(
        broker: broker,
        login: login,
        server: server,
        password: password,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'MT5 account connected successfully.' : bot.connectionError ?? 'MT5 connection failed.'),
        backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );
  }

  Future<void> _updateApp() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Expanded(child: Text('Checking GitHub for the latest Pips-Miner release…')),
          ],
        ),
      ),
    );
    final result = await AppUpdateService.instance.checkForUpdateDetailed();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (result.status == UpdateCheckStatus.updateAvailable) {
      await AppUpdateService.instance.promptIfUpdateAvailable(context);
      return;
    }
    final upToDate = result.status == UpdateCheckStatus.upToDate;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(upToDate ? 'Pips-Miner is up to date' : 'Update check failed'),
        content: Text(
          upToDate
              ? 'Current version: ${result.installedVersion}\n\nThe latest GitHub release is not newer than this version.'
              : result.message,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BotProvider>(
      builder: (context, bot, _) {
        return SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Pips-Miner', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                                  SizedBox(height: 2),
                                  Text('life changing pips', style: TextStyle(color: AppTheme.primaryColor, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8)),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _updateApp,
                              icon: const Icon(Icons.system_update_alt_rounded, size: 17),
                              label: const Text('UPDATE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    BrokerConnectionSection(
                      bot: bot,
                      storage: _storage,
                      onConnect: _connect,
                      brokerController: _brokerController,
                      loginController: _loginController,
                      serverController: _serverController,
                      passwordController: _passwordController,
                    ),
                    const SizedBox(height: 14),
                    _ModeSection(bot: bot),
                    const SizedBox(height: 14),
                    BrokerAwareSymbolSection(
                      bot: bot,
                      brokerController: _brokerController,
                      serverController: _serverController,
                    ),
                    const SizedBox(height: 14),
                    const _InfoSection(
                      title: 'STRATEGY',
                      icon: Icons.psychology_outlined,
                      lines: [
                        'Velocity baseline: 14 candles',
                        'Velocity expansion: 1.5× baseline',
                        'Volume baseline: 14 candles',
                        'Volume expansion: 1.5× baseline',
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _InfoSection(
                      title: 'RISK & POSITION MANAGEMENT',
                      icon: Icons.security_outlined,
                      lines: [
                        'Risk per trade: 1.0%',
                        'Trailing distance: 100 pips',
                        'Reversal distance: 100 pips',
                        'Minimum volume: 0.01',
                        'Volume step: 0.01',
                        'Maximum volume: 1.00',
                      ],
                    ),
                    const SizedBox(height: 14),
                    _EngineSection(bot: bot),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeSection extends StatelessWidget {
  final BotProvider bot;

  const _ModeSection({required this.bot});

  @override
  Widget build(BuildContext context) {
    final live = bot.isLiveAccount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ACCOUNT MODE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _ModeButton('DEMO', !live, AppTheme.secondaryColor, bot.isBotRunning ? null : () => bot.setAccountMode(false))),
                const SizedBox(width: 10),
                Expanded(child: _ModeButton('LIVE', live, AppTheme.warningColor, bot.isBotRunning ? null : () => bot.setAccountMode(true))),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              live ? 'LIVE MODE — trades can use real funds.' : 'DEMO MODE — recommended for testing.',
              style: TextStyle(color: live ? AppTheme.warningColor : AppTheme.secondaryColor, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  const _ModeButton(this.label, this.selected, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(.10) : AppTheme.darkSurfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color.withOpacity(.45) : AppTheme.darkBorder),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: selected ? color : Colors.white54, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> lines;

  const _InfoSection({required this.title, required this.icon, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 10),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(line, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineSection extends StatelessWidget {
  final BotProvider bot;

  const _EngineSection({required this.bot});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ENGINE STATUS', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 12),
            _line('Android trading service', bot.isBotRunning ? 'RUNNING' : 'STOPPED'),
            _line('Pips-Miner trading connection', bot.isConnected ? 'READY' : 'NOT CONNECTED'),
            _line('Trading symbol', bot.symbol),
          ],
        ),
      ),
    );
  }

  Widget _line(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10.5))),
          Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.secondaryColor)),
        ],
      ),
    );
  }
}
