import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The project's MIT license, shown in a monospace boxed card.
const lanwayLicense = '''MIT License

Copyright (c) 2026 Lanway Foundation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';

class LicenseScreen extends StatelessWidget {
  const LicenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('License'), backgroundColor: LanwayColors.navy),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0B1422),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Copy license',
                      icon: const Icon(Icons.copy, size: 18, color: LanwayColors.accent),
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: lanwayLicense));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('License copied to clipboard')),
                        );
                      },
                    ),
                  ),
                  SelectableText(
                    lanwayLicense,
                    style: TextStyle(
                      color: LanwayColors.mint.withValues(alpha: 0.85),
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
