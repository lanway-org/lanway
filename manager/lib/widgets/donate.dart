import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The Lanway donation addresses. Lanway is free forever; donations keep the
/// foundation's shared servers running.
const lanwayBtcSegwit = 'bc1qc8pd4a355j963va0jvzs8ed8mc9y004j2wcxnd';
const lanwayBtcLegacy = '1EYDL42NrANEWCord6HHxaudyrkLghXr8m';

/// A "Support Lanway" card with copyable Bitcoin addresses.
class DonateCard extends StatelessWidget {
  const DonateCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LanwayColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7931A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text('₿',
                    style: TextStyle(color: Color(0xFFF7931A), fontSize: 20, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Support Lanway',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                    Text('Free forever. Donations keep the servers running.',
                        style: TextStyle(color: LanwayColors.mint, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddressRow(label: 'Bitcoin (SegWit · lowest fees)', address: lanwayBtcSegwit),
          const SizedBox(height: 10),
          _AddressRow(label: 'Bitcoin (Legacy)', address: lanwayBtcLegacy),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final String label;
  final String address;
  const _AddressRow({required this.label, required this.address});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.55), fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: LanwayColors.navy,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: LanwayColors.mint, fontFamily: 'monospace', fontSize: 12)),
              ),
              IconButton(
                tooltip: 'Copy address',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 17, color: LanwayColors.accent),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: address));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bitcoin address copied. Thank you 🙏')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
