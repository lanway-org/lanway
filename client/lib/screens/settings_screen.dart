import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../dns_settings.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/donate.dart';

/// Local-only client preferences. These are UI/UX toggles kept on-device; the
/// VPN tunnel itself routes all traffic by default.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _autoConnect = false;
  bool _killSwitch = true;
  late DnsOption _dnsOption;
  final _customDns = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Reflect the saved DNS in the dropdown.
    final saved = ref.read(dnsServersProvider);
    _dnsOption = dnsOptions.firstWhere(
      (o) => o.servers.join(',') == saved.join(','),
      orElse: () => saved.isEmpty ? dnsOptions.first : dnsOptions.last,
    );
    if (_dnsOption.name == 'Custom…') _customDns.text = saved.join(', ');
  }

  void _applyDns(DnsOption o) {
    setState(() => _dnsOption = o);
    if (o.name == 'Custom…') {
      final servers = _customDns.text.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
      ref.read(dnsServersProvider.notifier).set(servers);
    } else {
      ref.read(dnsServersProvider.notifier).set(o.servers);
    }
  }

  @override
  void dispose() {
    _customDns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: LanwayColors.navy),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card([
            SwitchListTile(
              value: _autoConnect,
              onChanged: (v) => setState(() => _autoConnect = v),
              title: const Text('Auto-connect on startup', style: _titleStyle),
              subtitle: const Text('Reconnect to the last server when the app opens',
                  style: _subStyle),
              activeThumbColor: LanwayColors.accent,
            ),
            const Divider(height: 1, color: Color(0x14FFFFFF)),
            SwitchListTile(
              value: _killSwitch,
              onChanged: (v) => setState(() => _killSwitch = v),
              title: const Text('Kill switch', style: _titleStyle),
              subtitle: const Text('Block all traffic if the tunnel drops', style: _subStyle),
              activeThumbColor: LanwayColors.accent,
            ),
          ]),
          const SizedBox(height: 16),
          _card([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.dns_outlined, color: LanwayColors.accent, size: 20),
                      SizedBox(width: 12),
                      Text('DNS resolver', style: _titleStyle),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DnsOption>(
                    initialValue: _dnsOption,
                    isExpanded: true,
                    dropdownColor: LanwayColors.surface,
                    items: [
                      for (final o in dnsOptions)
                        DropdownMenuItem(
                          value: o,
                          child: Text('${o.name} — ${o.note}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                        ),
                    ],
                    onChanged: (o) {
                      if (o != null) _applyDns(o);
                    },
                  ),
                  if (_dnsOption.name == 'Custom…') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customDns,
                      decoration: const InputDecoration(
                        labelText: 'Custom DNS (comma-separated)',
                        hintText: '1.1.1.1, 1.0.0.1',
                      ),
                      onChanged: (_) => _applyDns(_dnsOption),
                    ),
                  ] else if (_dnsOption.servers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_dnsOption.servers.join('  ·  '),
                        style: TextStyle(
                            color: LanwayColors.mint.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontFamily: 'monospace')),
                  ],
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _card([
            ListTile(
              leading: const Icon(Icons.code, color: LanwayColors.accent),
              title: const Text('Open source on GitHub', style: _titleStyle),
              subtitle: const Text('github.com/lanway-org/lanway', style: _subStyle),
              trailing: const Icon(Icons.open_in_new, size: 18, color: LanwayColors.mint),
              onTap: () {},
            ),
            const Divider(height: 1, color: Color(0x14FFFFFF)),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: LanwayColors.accent),
              title: const Text('License', style: _titleStyle),
              subtitle: const Text('MIT — free forever', style: _subStyle),
              trailing: const Icon(Icons.chevron_right, size: 20, color: LanwayColors.mint),
              onTap: () => context.push('/license'),
            ),
          ]),
          const SizedBox(height: 16),
          const DonateCard(),
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                const LanwayLogo(size: 40),
                const SizedBox(height: 10),
                const LanwayWordmark(fontSize: 18),
                const SizedBox(height: 6),
                Text('Free to use. Free to speak. Unlimited.',
                    style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.5), fontSize: 13)),
                const SizedBox(height: 4),
                Text('Version 1.0.0 · lanway.org',
                    style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.4), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: LanwayColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      // ListTile paints ink on the nearest Material, so give it a transparent
      // one — otherwise it warns the splash is hidden by this card's colour.
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }
}

const _titleStyle = TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14);
const _subStyle = TextStyle(color: LanwayColors.mint, fontSize: 12);
