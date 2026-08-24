import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pips_miner_app/providers/bot_provider.dart';
import 'package:pips_miner_app/services/secure_storage_service.dart';
import 'package:pips_miner_app/theme/app_theme.dart';
import 'package:pips_miner_app/widgets/broker_aware_symbol_section.dart';
import 'package:pips_miner_app/widgets/broker_connection_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SecureStorageService _storage = SecureStorageService();

  late final TextEditingController _brokerController;
  late final TextEditingController _loginController;
  late final TextEditingController _serverController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _brokerController = TextEditingController();
    _loginController = TextEditingController();
    _serverController = TextEditingController();
    _passwordController = TextEditingController();
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
        const SnackBar(
          content: Text('Select a broker server, then enter your MT5 account number and trading password.'),
        ),
      );
      return;
    }

    final success = await bot.connectMt5(
      login: login,
      password: password,
      server: server,
    );

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
        content: Text(
          success
              ? 'MT5 account connected successfully.'
              : bot.connectionError ?? 'MT5 connection failed.',
        ),
        backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
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
              SliverToBoxAdapter(child: _SettingsHeader(bot: bot)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 30),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
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
                    _AccountModeSection(bot: bot),
                    const SizedBox(height: 14),
                    BrokerAwareSymbolSection(
                      bot: bot,
                      brokerController: _brokerController,
                      serverController: _serverController,
                    ),
                    const SizedBox(height: 14),
                    const _StrategySection(),
                    const SizedBox(height: 14),
                    const _RiskSection(),
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

class _SettingsHeader extends StatelessWidget {
  final BotProvider bot;
  const _SettingsHeader({required this.bot});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primaryColor.withOpacity(.30)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/pips_miner_pro_icon.png', fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pips-Miner', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                SizedBox(height: 2),
                Text('ENGINE SETTINGS', style: TextStyle(fontSize: 8.5, letterSpacing: 1.25, fontWeight: FontWeight.w700, color: Colors.white38)),
              ],
            ),
          ),
          _StatusPill(
            label: bot.isBotRunning ? 'ACTIVE' : 'IDLE',
            color: bot.isBotRunning ? AppTheme.successColor : Colors.white38,
          ),
        ],
      ),
    );
  }
}

class _AccountModeSection extends StatelessWidget {
  final BotProvider bot;
  const _AccountModeSection({required this.bot});

  @override
  Widget build(BuildContext context) {
    final live = bot.isLiveAccount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'ACCOUNT MODE', icon: Icons.shield_outlined),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _ModeButton(title: 'DEMO', subtitle: 'Practice', icon: Icons.science_outlined, selected: !live, color: AppTheme.secondaryColor, onTap: bot.isBotRunning ? null : () => bot.setAccountMode(false))),
                const SizedBox(width: 10),
                Expanded(child: _ModeButton(title: 'LIVE', subtitle: 'Real money', icon: Icons.warning_amber_rounded, selected: live, color: AppTheme.warningColor, onTap: bot.isBotRunning ? null : () => bot.setAccountMode(true))),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              live ? 'LIVE MODE — trades can use real funds.' : 'DEMO MODE — recommended for testing.',
              style: TextStyle(color: live ? AppTheme.warningColor : AppTheme.secondaryColor, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrategySection extends StatelessWidget {
  const _StrategySection();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'STRATEGY', icon: Icons.psychology_outlined),
            const SizedBox(height: 13),
            const _ParameterRow(title: 'Velocity baseline', value: '14 candles'),
            const _ParameterRow(title: 'Velocity expansion', value: '1.5× baseline'),
            const _ParameterRow(title: 'Volume baseline', value: '14 candles'),
            const _ParameterRow(title: 'Volume expansion', value: '1.5× baseline'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(.07), borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.bolt_rounded, color: AppTheme.primaryColor, size: 18),
                  SizedBox(width: 9),
                  Expanded(child: Text('Entries require velocity expansion followed by volume confirmation.', style: TextStyle(color: Colors.white54, fontSize: 10.5))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskSection extends StatelessWidget {
  const _RiskSection();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'RISK & POSITION MANAGEMENT', icon: Icons.security_outlined),
            const SizedBox(height: 13),
            const _ParameterRow(title: 'Risk per trade', value: '1.0%'),
            const _ParameterRow(title: 'Trailing distance', value: '100 pips'),
            const _ParameterRow(title: 'Reversal distance', value: '100 pips'),
            const _ParameterRow(title: 'Minimum volume', value: '0.01'),
            const _ParameterRow(title: 'Volume step', value: '0.01'),
            const _ParameterRow(title: 'Maximum volume', value: '1.00'),
            const SizedBox(height: 10),
            const Text('Position sizing remains broker-aware and is calculated by the trading engine for the selected symbol.', style: TextStyle(color: Colors.white30, fontSize: 10)),
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
    final running = bot.isBotRunning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'ENGINE STATUS', icon: Icons.memory_rounded),
            const SizedBox(height: 14),
            _StatusLine(title: 'Android trading service', value: running ? 'RUNNING' : 'STOPPED', color: running ? AppTheme.successColor : Colors.white38),
            _StatusLine(title: 'Pips-Miner trading connection', value: bot.isConnected ? 'READY' : 'NOT CONNECTED', color: bot.isConnected ? AppTheme.successColor : AppTheme.warningColor),
            _StatusLine(title: 'Trading symbol', value: bot.symbol, color: AppTheme.secondaryColor),
            const SizedBox(height: 10),
            const Text('The Android background service owns the trading engine. Closing this screen does not stop an active miner.', style: TextStyle(color: Colors.white30, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  const _ModeButton({required this.title, required this.subtitle, required this.icon, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(.10) : AppTheme.darkSurfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color.withOpacity(.45) : AppTheme.darkBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : Colors.white30, size: 23),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? color : Colors.white54, fontSize: 13)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.white30, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class _ParameterRow extends StatelessWidget {
  final String title;
  final String value;
  const _ParameterRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11))),
          Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  const _StatusLine({required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10.5))),
          Text(value, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
        ],
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
        Text(title, style: const TextStyle(fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: Colors.white54)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(.24))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
