import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pips_miner_app/providers/bot_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _demoAccountController;
  late TextEditingController _liveAccountController;
  late TextEditingController _apiTokenController;
  late TextEditingController _symbolController;
  late TextEditingController _volumeController;

  @override
  void initState() {
    super.initState();
    _demoAccountController = TextEditingController();
    _liveAccountController = TextEditingController();
    _apiTokenController = TextEditingController();
    _symbolController = TextEditingController();
    _volumeController = TextEditingController();
  }

  @override
  void dispose() {
    _demoAccountController.dispose();
    _liveAccountController.dispose();
    _apiTokenController.dispose();
    _symbolController.dispose();
    _volumeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: Consumer<BotProvider>(
        builder: (context, botProvider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account Type Selector
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Account Type',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => botProvider.setAccountMode(false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: !botProvider.isLiveAccount
                                          ? Colors.blue
                                          : Colors.transparent,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(7),
                                        bottomLeft: Radius.circular(7),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.science, size: 28),
                                        const SizedBox(height: 4),
                                        Text(
                                          'DEMO',
                                          style: TextStyle(
                                            color: !botProvider.isLiveAccount
                                                ? Colors.white
                                                : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => botProvider.setAccountMode(true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: botProvider.isLiveAccount
                                          ? Colors.red
                                          : Colors.transparent,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(7),
                                        bottomRight: Radius.circular(7),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.trending_up, size: 28),
                                        const SizedBox(height: 4),
                                        Text(
                                          'LIVE',
                                          style: TextStyle(
                                            color: botProvider.isLiveAccount
                                                ? Colors.white
                                                : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: botProvider.isLiveAccount
                                ? Colors.red.withOpacity(0.2)
                                : Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            botProvider.isLiveAccount
                                ? '⚠️ Trading with REAL MONEY - Be Careful!'
                                : '✅ Demo Mode - Risk Free Practice',
                            style: TextStyle(
                              color: botProvider.isLiveAccount
                                  ? Colors.red
                                  : Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // API Configuration
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'API Configuration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _apiTokenController,
                          decoration: const InputDecoration(
                            labelText: 'MetaAPI Token',
                            hintText: 'Enter your MetaAPI token',
                            prefixIcon: Icon(Icons.vpn_key),
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _demoAccountController,
                          decoration: const InputDecoration(
                            labelText: 'Demo Account ID',
                            hintText: 'Enter demo account ID',
                            prefixIcon: Icon(Icons.account_balance),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _liveAccountController,
                          decoration: const InputDecoration(
                            labelText: 'Live Account ID',
                            hintText: 'Enter live account ID',
                            prefixIcon: Icon(Icons.account_balance),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Trading Configuration
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trading Parameters',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _symbolController,
                          decoration: const InputDecoration(
                            labelText: 'Trading Symbol',
                            hintText: 'e.g., EURUSD, GBPUSD',
                            prefixIcon: Icon(Icons.trending_up),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _volumeController,
                          decoration: const InputDecoration(
                            labelText: 'Trade Volume',
                            hintText: 'e.g., 0.01, 0.1, 1.0',
                            prefixIcon: Icon(Icons.balance),
                          ),
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Stop Loss (Pips)',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '50 pips',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      botProvider.updateSettings(
                        apiToken: _apiTokenController.text,
                        demoAccountId: _demoAccountController.text,
                        liveAccountId: _liveAccountController.text,
                        symbol: _symbolController.text,
                        volume: double.tryParse(_volumeController.text) ?? 0.01,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Settings saved successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('SAVE SETTINGS'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
