# Lanway Threat Model

This document states plainly what Lanway protects, who it protects against, and
where its limits are. Lanway is a free, open-source, anti-censorship VPN designed
for people on networks that actively try to detect and block VPN traffic.

## Goals

1. **Reach.** Let a user inside a censored network reach the open internet.
2. **Unobservability.** Make the tunnel hard to distinguish from ordinary HTTPS,
   so it survives deep-packet-inspection (DPI) and active probing.
3. **No central trust.** Avoid any Lanway-operated server or account that could be
   compromised, subpoenaed, or used to deanonymise users. Each operator runs their
   own server; settings stay on the user's own device.

## Assets

- The fact that a user is using a VPN (the most sensitive asset under censorship).
- The user's browsing traffic and destinations.
- The server's access key (controls the management API).
- The operator's cloud-provider credentials (used only on-device).

## Adversaries and what Lanway does

### 1. Censor / ISP performing DPI and blocking
The primary adversary. They watch traffic, fingerprint protocols, and block what
looks like a VPN.

- **Mitigation:** Lanway tunnels over **VLESS + REALITY (XTLS-Vision)** on Xray.
  REALITY presents the TLS handshake of a real, third-party HTTPS site, so to a
  censor the connection looks like an ordinary visit to a normal website. There is
  no self-signed cert, no telltale VPN handshake, and no listening fingerprint to
  probe — active probes are answered by the borrowed site.
- **Reuse / domain-fronting:** Lanway can also run **behind an existing website**
  (proxy mode) so the VPN shares a real site's IP and certificate.
- **Residual risk:** Traffic-analysis at scale (volume/timing correlation) and
  whole-IP-range blocking are out of scope for any single tunnel; the mitigation is
  cheap, disposable servers and multiple regions, which Lanway makes easy.

### 2. Network attacker on the management channel (MITM)
The operator manages the server over a TLS management API (port 8080) using a
bearer access key.

- **Mitigation:** The management certificate is **pinned trust-on-first-use**: the
  Manager records the certificate's SHA-256 on first connect and refuses any later
  connection that presents a different certificate, so an attacker cannot substitute
  their own certificate to capture the access key.
- **Residual risk:** The very first connect is trust-on-first-use; an attacker
  already in-path at that exact moment could be pinned. Operators provisioning over
  a hostile network should do the first connect from a trusted one.

### 3. Malicious or compromised server operator
A user trusts whoever runs the server they connect to (this is true of every VPN).

- **Position:** Lanway does not claim to protect a user from their own server
  operator; it removes the need to trust *Lanway*, not the operator. Users should
  connect to servers run by people or groups they trust, and rely on end-to-end TLS
  (HTTPS) for content confidentiality, exactly as with any VPN.

### 4. Lanway project / supply chain
- **Position:** There is **no Lanway backend**. The project cannot see traffic,
  keys, or who is connected, because nothing reports to us. The apps are MIT-licensed
  and fully auditable. Releases are built in public CI from tagged source.
- **Residual risk:** Dependency and toolchain integrity (Flutter, Xray, OS images).
  Mitigations in progress: reproducible builds and pinned, hash-checked dependencies.

### 5. Device compromise / coercion
- **Position:** A fully compromised device is out of scope (it can read anything the
  user can). Lanway stores only what is needed locally (server address, access key,
  optional name, pinned cert, cloud OAuth tokens) and never transmits it to us.
  Cloud OAuth tokens are sent only to the provider's official API.

## Data handling

- **No logs, no analytics, no accounts.** See [Privacy Policy](https://lanway.org/privacy.html).
- Cloud sign-in (Google Cloud / DigitalOcean) is OAuth on-device; tokens go only to
  the provider and are used solely to create and manage the server the user asks for.

## Known limitations / roadmap

- Independent third-party security audit (sought via funding).
- Reproducible, signed releases across all platforms.
- Optional out-of-band cert fingerprint verification to harden first-connect.
- Localisation and field testing with users in censored regions.

Found an issue? Please open a report at
<https://github.com/lanway-org/lanway/security/advisories> or email contact@lanway.org.
