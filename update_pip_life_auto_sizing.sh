#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd ~/Pips-miner

python3 - <<'PY'
from pathlib import Path

# 1) Branding
p = Path("mobile_app/lib/screens/home_screen.dart")
s = p.read_text()
old = "        title: const Text('PIPS Miner Bot'),"
new = """        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pip-life',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'life changing pips',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),"""
if old not in s:
    raise SystemExit("Branding target not found in home_screen.dart")
p.write_text(s.replace(old, new, 1))

# 2) MetaApi: add real broker margin calculation
p = Path("mobile_app/lib/services/metaapi_service.dart")
s = p.read_text()
needle = """  Future<Map<String, dynamic>> closePosition(String positionId) async {
    return _trade({
      'actionType': 'POSITION_CLOSE_ID',
      'positionId': positionId,
    });
  }

"""
insert = """  Future<Map<String, dynamic>> closePosition(String positionId) async {
    return _trade({
      'actionType': 'POSITION_CLOSE_ID',
      'positionId': positionId,
    });
  }

  Future<Map<String, dynamic>> calculateMargin({
    required String symbol,
    required double volume,
    required bool buy,
    required double openPrice,
  }) async {
    final response = await http.post(
      _uri('/calculate-margin'),
      headers: _headers,
      body: jsonEncode({
        'symbol': symbol,
        'type': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL',
        'volume': volume,
        'openPrice': openPrice,
      }),
    );
    return _map(response);
  }

"""
if needle not in s:
    raise SystemExit("MetaApi insertion target not found")
p.write_text(s.replace(needle, insert, 1))

# 3) Trading config: make sizing policy explicit
p = Path("mobile_app/lib/models/trading_config.dart")
s = p.read_text()
s = s.replace(
"""  // Position sizing.
  final double riskPercent;
  final double minimumVolume;
  final double volumeStep;
  final double maximumVolume;
""",
"""  // Automatic position sizing.
  // Each bot calculates size from its own account balance and
  // the live broker specification for the selected symbol.
  final double riskPercent;
  final double minimumVolume;
  final double volumeStep;
  final double maximumVolume;
"""
)
p.write_text(s)

# 4) Provider: remove manual lot sizing from the app path.
p = Path("mobile_app/lib/providers/bot_provider.dart")
s = p.read_text()
s = s.replace("  double _volume = 0.01;\n", "")
s = s.replace("  double get volume => _volume;\n", "")
old = """  void updateSettings({
    String? symbol,
    double? volume,
  }) {
    if (symbol != null && symbol.trim().isNotEmpty) {
      _symbol = symbol.trim().toUpperCase();
    }
    if (volume != null && volume > 0) {
      _volume = volume;
    }
    notifyListeners();
  }
"""
new = """  void updateSettings({
    String? symbol,
  }) {
    if (symbol != null && symbol.trim().isNotEmpty) {
      _symbol = symbol.trim().toUpperCase();
    }
    notifyListeners();
  }
"""
if old not in s:
    raise SystemExit("Provider updateSettings block not found")
s = s.replace(old, new, 1)
s = s.replace("        minimumVolume: _volume,\n", "")
p.write_text(s)

# 5) Settings: replace manual volume with automatic sizing explanation.
p = Path("mobile_app/lib/screens/settings_screen.dart")
s = p.read_text()
s = s.replace("  late TextEditingController _volumeController;\n", "")
s = s.replace("    _volumeController = TextEditingController();\n", "")
s = s.replace("    _volumeController.dispose();\n", "")
old = """                        TextField(
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
"""
new = """                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.auto_graph, color: Colors.green),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Automatic position sizing: 1% of the current account balance per new position. The broker\\'s live minimum volume, maximum volume and volume step are applied separately for each symbol. Margin is checked before the order is sent.',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
"""
if old not in s:
    raise SystemExit("Settings volume field block not found")
s = s.replace(old, new, 1)
old_save = """                      botProvider.updateSettings(
                        symbol: _symbolController.text,
                        volume: double.tryParse(_volumeController.text) ?? 0.01,
                      );
"""
new_save = """                      botProvider.updateSettings(
                        symbol: _symbolController.text,
                      );
"""
if old_save not in s:
    raise SystemExit("Settings save block not found")
s = s.replace(old_save, new_save, 1)
p.write_text(s)

# 6) Engine: dynamic broker-aware sizing.
p = Path("mobile_app/lib/services/velocity_reversal_engine.dart")
s = p.read_text()

old = """    final clientId =
        '${_clientPrefix}_${DateTime.now().millisecondsSinceEpoch}';

    await api.marketOrder(
      symbol: config.symbol,
      volume: _activeVolume,
      buy: buy,
      clientId: clientId,
      magic: magic,
    );
"""
new = """    // Calculate this bot's position size from its own live account
    // balance and this broker's live symbol requirements. Never use
    // a shared/global lot size.
    _activeVolume = await _calculatePositionVolume(
      buy: buy,
    );

    final clientId =
        '${_clientPrefix}_${DateTime.now().millisecondsSinceEpoch}';

    await api.marketOrder(
      symbol: config.symbol,
      volume: _activeVolume,
      buy: buy,
      clientId: clientId,
      magic: magic,
    );
"""
if old not in s:
    raise SystemExit("Engine market-order block not found")
s = s.replace(old, new, 1)

needle = """  Future<void> _createReversalStop(
    EnginePositionDirection direction,
  ) async {
"""
helper = """  Future<double> _calculatePositionVolume({
    required bool buy,
  }) async {
    final account = await api.accountInformation();
    final specification = await api.symbolSpecification(config.symbol);
    final price = await api.symbolPrice(config.symbol);

    final balance = _number(account['balance']);
    final freeMargin = _number(account['freeMargin']);

    if (balance == null || balance <= 0) {
      throw Exception(
        'Cannot calculate position size: MetaApi returned no valid account balance.',
      );
    }

    if (freeMargin == null || freeMargin <= 0) {
      throw Exception(
        'Cannot calculate position size: account free margin is zero or unavailable.',
      );
    }

    final minVolume = _number(
          specification['minVolume'] ?? specification['volumeMin'],
        ) ??
        config.minimumVolume;

    final maxVolume = _number(
          specification['maxVolume'] ?? specification['volumeMax'],
        ) ??
        config.maximumVolume;

    final volumeStep = _number(
          specification['volumeStep'],
        ) ??
        config.volumeStep;

    final tickSize = _number(
      specification['tickSize'],
    );

    final profitTickValue = _number(
      price['profitTickValue'],
    );

    final lossTickValue = _number(
      price['lossTickValue'],
    ) ?? profitTickValue;

    final bid = _number(
      price['bid'] ?? price['Bid'] ?? price['last'],
    );
    final ask = _number(
      price['ask'] ?? price['Ask'] ?? price['last'],
    );

    if (minVolume == null ||
        maxVolume == null ||
        volumeStep == null ||
        minVolume <= 0 ||
        maxVolume < minVolume ||
        volumeStep <= 0) {
      throw Exception(
        'Broker returned invalid volume minimum/maximum/step for ${config.symbol}.',
      );
    }

    if (tickSize == null ||
        tickSize <= 0 ||
        lossTickValue == null ||
        lossTickValue <= 0) {
      throw Exception(
        'MetaApi did not return valid tick sizing data for ${config.symbol}.',
      );
    }

    if (bid == null || ask == null) {
      throw Exception(
        'MetaApi did not return a valid bid/ask for ${config.symbol}.',
      );
    }

    final riskAmount = balance * (config.riskPercent / 100.0);
    final pipSize = await _pipSizeFromSpecification(specification);
    final stopDistance = config.reversalPips * pipSize;

    final ticksToStop = stopDistance / tickSize;
    final lossPerLot = ticksToStop * lossTickValue;

    if (lossPerLot <= 0) {
      throw Exception(
        'Cannot calculate loss-per-lot for ${config.symbol}.',
      );
    }

    // 1% of THIS account's current balance is the target risk.
    var desiredVolume = riskAmount / lossPerLot;

    // Apply the broker's live min/max first.
    desiredVolume = desiredVolume.clamp(minVolume, maxVolume);

    // Round DOWN to the broker's step so risk is never increased by rounding.
    desiredVolume = _floorToStep(desiredVolume, volumeStep);

    if (desiredVolume < minVolume) {
      desiredVolume = minVolume;
    }

    // Keep the new order within the project's 50% free-margin cap.
    final marginBudget = freeMargin * 0.50;
    final openPrice = buy ? ask : bid;

    var margin = await api.calculateMargin(
      symbol: config.symbol,
      volume: desiredVolume,
      buy: buy,
      openPrice: _normalizePrice(openPrice),
    );

    var requiredMargin = _number(margin['margin']);

    if (requiredMargin != null && requiredMargin > marginBudget) {
      final scale = marginBudget / requiredMargin;
      desiredVolume = _floorToStep(
        desiredVolume * scale,
        volumeStep,
      );

      if (desiredVolume < minVolume) {
        throw Exception(
          'Broker minimum volume for ${config.symbol} would exceed the 50% free-margin safety cap.',
        );
      }

      margin = await api.calculateMargin(
        symbol: config.symbol,
        volume: desiredVolume,
        buy: buy,
        openPrice: _normalizePrice(openPrice),
      );
      requiredMargin = _number(margin['margin']);

      if (requiredMargin != null && requiredMargin > marginBudget) {
        throw Exception(
          'Calculated ${config.symbol} position still exceeds the 50% free-margin safety cap.',
        );
      }
    }

    return double.parse(
      desiredVolume.toStringAsFixed(8),
    );
  }

  double _floorToStep(double value, double step) {
    if (step <= 0) return value;
    final units = (value / step).floor();
    return units * step;
  }

  Future<double> _pipSizeFromSpecification(
    Map<String, dynamic> specification,
  ) async {
    final explicitPipSize = _number(specification['pipSize']);

    if (explicitPipSize != null && explicitPipSize > 0) {
      return explicitPipSize;
    }

    final point = _number(specification['point']);
    final digits = int.tryParse(
          specification['digits']?.toString() ?? '',
        ) ??
        0;

    if (point == null || point <= 0) {
      throw Exception(
        'MetaApi symbol specification has no valid point size.',
      );
    }

    return (digits == 3 || digits == 5)
        ? point * 10
        : point;
  }

"""
if needle not in s:
    raise SystemExit("Engine helper insertion point not found")
s = s.replace(needle, helper + needle, 1)

old_pip = """  Future<double> _pipSize() async {
    final specification =
        await api.symbolSpecification(config.symbol);

    final point = _number(
      specification['point'],
    );

    final digits =
        int.tryParse(
          specification['digits']?.toString() ?? '',
        ) ??
        0;

    if (point == null || point <= 0) {
      throw Exception(
        'MetaApi symbol specification has no valid point size.',
      );
    }

    /*
     * Standard FX convention:
     * 5/3 digit symbols use 10 points per pip.
     * 2/4 digit symbols use 1 point per pip.
     *
     * This also avoids hard-coding XAUUSD price precision.
     */
    return (digits == 3 || digits == 5)
        ? point * 10
        : point;
  }
"""
new_pip = """  Future<double> _pipSize() async {
    final specification =
        await api.symbolSpecification(config.symbol);

    return _pipSizeFromSpecification(specification);
  }
"""
if old_pip not in s:
    raise SystemExit("Old pip-size helper not found")
s = s.replace(old_pip, new_pip, 1)

p.write_text(s)

print("Pip-life branding and broker-aware automatic position sizing applied.")
PY

git diff --check

git add \
  mobile_app/lib/screens/home_screen.dart \
  mobile_app/lib/services/metaapi_service.dart \
  mobile_app/lib/models/trading_config.dart \
  mobile_app/lib/providers/bot_provider.dart \
  mobile_app/lib/screens/settings_screen.dart \
  mobile_app/lib/services/velocity_reversal_engine.dart

git commit -m "Brand Pip-life and add broker-aware automatic position sizing"
git push

echo
echo "UPDATE COMPLETE"
git log -1 --oneline
git status --short
