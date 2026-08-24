import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'settings_screen.dart';

class EnhancedSettingsScreen extends StatefulWidget {
  const EnhancedSettingsScreen({super.key});

  @override
  State<EnhancedSettingsScreen> createState() => _EnhancedSettingsScreenState();
}

class _EnhancedSettingsScreenState extends State<EnhancedSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        SettingsScreen(),
        _SettingsBrandOverlay(),
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
