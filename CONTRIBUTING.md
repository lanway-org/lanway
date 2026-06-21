# Contributing to Lanway

Thank you for helping keep the internet open. Lanway is a community project — every
contribution, from a typo fix to a new translation to a protocol improvement, matters.

## Ways to help

- **Report bugs** and request features via GitHub issues.
- **Translate** the apps and the landing page into more languages — this is especially valuable
  for the communities Lanway serves.
- **Improve the docs** so setup is approachable for non-technical operators.
- **Write code** for the server, the Manager app, the client app, or the website.

## Project layout

| Directory | Stack | Notes |
|---|---|---|
| `server/` | Go + Xray-core + Docker | Management API and tunnel supervision |
| `manager/` | Flutter (desktop) | Riverpod, go_router, dio |
| `client/` | Flutter (mobile + desktop) | Riverpod, go_router, flutter_v2ray |
| `web/` | HTML + Tailwind | Single-file landing page |

## Development setup

```bash
# Server (needs Go 1.22+ and the xray binary on PATH, or Docker)
cd server && go build ./...

# Flutter apps
cd manager && flutter pub get && flutter analyze && flutter test
cd client  && flutter pub get && flutter analyze && flutter test
```

## Pull request guidelines

1. Keep changes focused — one concern per PR.
2. Run `flutter analyze` (apps) and `go vet ./...` (server) before pushing; both must be clean.
3. Match the existing style and naming. New UI should use the brand palette in `theme.dart`.
4. Add or update tests where it makes sense.
5. Describe the user-facing effect of your change in the PR description.

## Security

If you find a vulnerability, please **do not** open a public issue. Email
`security@lanway.org` so it can be fixed before disclosure.

## Code of conduct

Be kind and assume good faith. Lanway exists to help people in difficult circumstances — keep
that spirit in every interaction.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
