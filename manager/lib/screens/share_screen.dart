import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../api_client.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// Shows the QR code and share links for a single user.
class ShareScreen extends ConsumerWidget {
  final String userId;
  const ShareScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyAsync = ref.watch(_userKeyProvider(userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Share access key'), backgroundColor: LanwayColors.navy),
      body: Center(
        child: keyAsync.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e', style: const TextStyle(color: LanwayColors.danger)),
          ),
          data: (data) => _ShareBody(data: data),
        ),
      ),
    );
  }
}

final _userKeyProvider = FutureProvider.autoDispose.family<UserWithLinks, String>((ref, id) async {
  final client = ref.watch(apiClientProvider);
  if (client == null) throw ApiException('Not connected');
  return client.userKey(id);
});

class _ShareBody extends StatelessWidget {
  final UserWithLinks data;
  const _ShareBody({required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          children: [
            Text(data.user.name,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white)),
            const SizedBox(height: 4),
            Text('Scan this with the Lanway app',
                style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6))),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: data.links.lanway,
                size: 240,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square, color: LanwayColors.navy),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square, color: LanwayColors.navy),
              ),
            ),
            const SizedBox(height: 28),
            _LinkBox(label: 'VLESS link', value: data.links.vless),
            const SizedBox(height: 12),
            _LinkBox(label: 'Lanway deep link', value: data.links.lanway),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Share.share(
                  data.links.vless,
                  subject: 'Your Lanway access key',
                ),
                icon: const Icon(Icons.ios_share, size: 20),
                label: const Text('Share key'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkBox extends StatelessWidget {
  final String label;
  final String value;
  const _LinkBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: LanwayColors.navy2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: LanwayColors.mint.withValues(alpha: 0.5), fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: LanwayColors.mint, fontSize: 13, fontFamily: 'monospace')),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18, color: LanwayColors.accent),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }
}
