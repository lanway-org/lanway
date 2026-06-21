import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'oauth_secrets.dart'; // gitignored — holds googleOAuthClientSecret

// Desktop OAuth client. The loopback redirect + code exchange is Google's
// documented "Desktop app" flow. The client id is public; the secret lives in
// the gitignored oauth_secrets.dart so it never lands in the public repo.
const _clientId = googleOAuthClientId;
const _clientSecret = googleOAuthClientSecret;
// cloud-platform is the superset that covers projects, Service Usage, billing
// and compute — one scope the consent page reliably renders. (The earlier
// billing failure was the Cloud Billing API not being enabled + the wrong quota
// project, fixed in google_create_screen, not a scope gap.)
const _scopes =
    'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email openid';

/// Tokens from a successful Google sign-in.
class GoogleTokens {
  final String accessToken;
  final String? refreshToken; // present on first consent (access_type=offline)
  const GoogleTokens(this.accessToken, this.refreshToken);
}

/// Runs Google's loopback OAuth (authorization-code) flow: opens the system
/// browser, captures the code on 127.0.0.1, and exchanges it for tokens.
class GoogleOAuth {
  static Future<GoogleTokens> authorize() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port; // Google allows any loopback port for Desktop apps
    final redirectUri = 'http://127.0.0.1:$port';
    final completer = Completer<String>();

    server.listen((req) async {
      final code = req.uri.queryParameters['code'];
      final error = req.uri.queryParameters['error'];
      await _respond(req, _donePage(ok: code != null));
      if (code != null && !completer.isCompleted) {
        completer.complete(code);
      } else if (error != null && !completer.isCompleted) {
        completer.completeError(ApiException('Google sign-in failed: $error'));
      }
    });

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes,
      'access_type': 'offline',
      // Single value (no space, so Safari doesn't send a malformed 400). This
      // shows the account chooser so the operator can pick the account that owns
      // their billing/project. A refresh token is still returned on first auth.
      'prompt': 'select_account',
    });

    try {
      await _openAuthUrl(authUrl);
      final code = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw ApiException('Timed out waiting for Google authorization.'),
      );
      return await _exchange(code, redirectUri);
    } finally {
      await server.close(force: true);
    }
  }

  /// Opens the auth URL. Google's consent flow is unreliable in Safari (its
  /// tracking/cookie protections can 400 the multi-step flow), so on macOS we
  /// prefer a Chromium browser when one is installed, and fall back to the
  /// default browser otherwise.
  static Future<void> _openAuthUrl(Uri url) async {
    if (Platform.isMacOS) {
      for (final app in const ['Google Chrome', 'Brave Browser', 'Microsoft Edge', 'Chromium']) {
        try {
          final r = await Process.run('open', ['-a', app, url.toString()]);
          if (r.exitCode == 0) return;
        } catch (_) {/* app not installed — try the next */}
      }
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw ApiException('Could not open the browser for Google sign-in.');
    }
  }

  static Future<GoogleTokens> _exchange(String code, String redirectUri) async {
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    try {
      final res = await dio.post(
        'https://oauth2.googleapis.com/token',
        data: {
          'code': code,
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = res.data is Map ? res.data['access_token'] as String? : null;
      if (token == null) {
        throw ApiException('Google sign-in failed: could not get an access token.');
      }
      return GoogleTokens(token, res.data['refresh_token'] as String?);
    } on DioException catch (e) {
      throw ApiException('Google sign-in failed: ${e.message ?? e.type.name}');
    }
  }

  /// Exchanges a saved refresh token for a fresh access token (silent — no
  /// browser). Throws [ApiException] if the token was revoked.
  static Future<String> refresh(String refreshToken) async {
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    try {
      final res = await dio.post(
        'https://oauth2.googleapis.com/token',
        data: {
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = res.data is Map ? res.data['access_token'] as String? : null;
      if (token == null) {
        throw ApiException('Google session expired — please sign in again.');
      }
      return token;
    } on DioException catch (e) {
      throw ApiException('Google sign-in failed: ${e.message ?? e.type.name}');
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

String _donePage({required bool ok}) => '''
<!doctype html><html><head><meta charset="utf-8"><title>Lanway</title></head>
<body style="margin:0;font-family:Roboto,system-ui,sans-serif;background:#0A1628;color:#E6EEF7;display:flex;flex-direction:column;height:100vh;align-items:center;justify-content:center;text-align:center">
<div style="width:72px;height:72px;border-radius:50%;background:${ok ? '#0284C7' : '#E24B4A'};display:flex;align-items:center;justify-content:center;margin-bottom:20px">
<span style="font-size:38px;color:#fff">${ok ? '&#10003;' : '&#33;'}</span></div>
<h2 style="font-weight:500;margin:0 0 8px">${ok ? 'Connected to Google Cloud' : 'Authorization failed'}</h2>
<p style="color:#9fb0c4;margin:0;max-width:360px">${ok ? 'You can close this window and return to Lanway Manager.' : 'Please return to Lanway Manager and try again.'}</p>
</body></html>
''';
