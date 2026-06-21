import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'oauth_secrets.dart'; // gitignored — holds digitalOceanClientId

/// OAuth client id for the Lanway Manager's DigitalOcean application. Client ids
/// aren't secret, but they're kept in the gitignored oauth_secrets.dart with the
/// other OAuth keys. No client secret is used — the implicit grant is the
/// correct, secret-free flow for a distributed desktop app.
const _doClientId = digitalOceanClientId;

/// Must exactly match the redirect URL registered on the DigitalOcean app.
const _redirectPort = 33417;

/// Runs DigitalOcean's browser OAuth flow: opens the system browser, lets the
/// user authorize, and captures the access token via a one-shot localhost
/// server. Returns the bearer token, or throws [ApiException].
class DigitalOceanOAuth {
  static Future<String> authorize() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);
    final completer = Completer<String>();

    server.listen((req) async {
      if (req.uri.path == '/token') {
        final token = req.uri.queryParameters['access_token'];
        final error = req.uri.queryParameters['error'];
        // Flush the response fully BEFORE completing — otherwise closing the
        // server in `finally` can cut off the page, leaving the browser blank.
        await _respond(req, _donePage(ok: token != null));
        if (token != null && !completer.isCompleted) {
          completer.complete(token);
        } else if (error != null && !completer.isCompleted) {
          completer.completeError(ApiException('DigitalOcean sign-in failed: $error'));
        }
      } else {
        // The token arrives in the URL fragment, which browsers don't send to
        // the server. Serve a page that forwards the fragment back as a query.
        await _respond(req, _capturePage);
      }
    });

    final authUrl = Uri.parse('https://cloud.digitalocean.com/v1/oauth/authorize').replace(
      queryParameters: {
        'client_id': _doClientId,
        'redirect_uri': 'http://localhost:$_redirectPort/',
        'response_type': 'token',
        'scope': 'read write',
      },
    );

    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      await server.close(force: true);
      throw ApiException('Could not open your browser for DigitalOcean sign-in.');
    }

    try {
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw ApiException('Timed out waiting for DigitalOcean authorization.'),
      );
    } finally {
      await server.close(force: true);
    }
  }

  static Future<void> _respond(HttpRequest req, String html) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(html);
    await req.response.close();
  }
}

const _capturePage = '''
<!doctype html><html><head><meta charset="utf-8"><title>Lanway</title></head>
<body style="margin:0;font-family:Roboto,system-ui,sans-serif;background:#0A1628;color:#E6EEF7;display:flex;height:100vh;align-items:center;justify-content:center">
<h2 style="color:#38BDF8;font-weight:500">Connecting…</h2>
<script>location.replace('/token?' + window.location.hash.substring(1));</script>
</body></html>
''';

String _donePage({required bool ok}) => '''
<!doctype html><html><head><meta charset="utf-8"><title>Lanway</title></head>
<body style="margin:0;font-family:Roboto,system-ui,sans-serif;background:#0A1628;color:#E6EEF7;display:flex;flex-direction:column;height:100vh;align-items:center;justify-content:center;text-align:center">
<div style="width:72px;height:72px;border-radius:50%;background:${ok ? '#0284C7' : '#E24B4A'};display:flex;align-items:center;justify-content:center;margin-bottom:20px">
<span style="font-size:38px;color:#fff">${ok ? '&#10003;' : '&#33;'}</span></div>
<h2 style="font-weight:500;margin:0 0 8px">${ok ? 'Connected to DigitalOcean' : 'Authorization failed'}</h2>
<p style="color:#9fb0c4;margin:0;max-width:360px">${ok ? 'You can close this window and return to Lanway Manager.' : 'Please return to Lanway Manager and try again.'}</p>
</body></html>
''';
