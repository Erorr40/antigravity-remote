# 🚀 Antigravity Remote

[![Release](https://img.shields.io/badge/Release-v0.1.1--beta-orange.svg)](https://github.com/Erorr40/antigravity-remote/releases)
[![Android](https://img.shields.io/badge/Android-13%2B%20%7C%2016%20Baklava-brightgreen.svg)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Host-Windows%20%7C%20macOS%20%7C%20Linux-blue.svg)](https://nodejs.org)
[![Security](https://img.shields.io/badge/Security-E2EE%20(X25519%20%2B%20AES--256--GCM)-red.svg)](#security--encryption)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

> **Antigravity Remote** is a secure, end-to-end encrypted remote bridge system enabling mobile devices (Android 13+ up to Android 16) to monitor, inspect, and control Antigravity running on a remote laptop or workstation across external networks without port forwarding.

---

## 🌟 Highlights

- 🔒 **True End-to-End Encryption (E2EE)**: Key exchange via **X25519** ECDH and symmetric authenticated payloads with **AES-256-GCM**. The relay server operates with zero knowledge and cannot read your session logs or prompts.
- 📱 **Native Android 16 / 13+ Experience**: Modern Material 3 UI built with Flutter 3.24+, featuring live agent thinking previews, syntax-highlighted code diffs, markdown artifact viewers, and biometric security gates (Fingerprint & Face Unlock).
- ⚡ **Zero-Port-Forwarding Relay**: Lightweight WebSocket tunnel architecture deployable on Cloudflare Tunnels, Docker, VPS, or Supabase Realtime.
- 🖥️ **Windows One-Click Installer**: Native C# Windows setup (`AntigravityRemote-Setup.exe`) that installs the daemon, creates shortcuts, and manages background execution.
- 🔔 **Android 13+ Notification Channels**: Granular system notifications for `Agent Progress`, `Awaiting Input`, and `Task Complete`.
- 📷 **Instant QR Code Pairing**: Zero-configuration pairing via terminal/desktop QR code containing cryptographic public keys and relay coordinates.

---

## 🏗️ System Architecture

```text
       +---------------------------------------------+
       |           Android Mobile Client             |
       |  - Flutter 3.24+ (Dart 3.5+)                |
       |  - SDK 33+ (Validated on Android 16)        |
       |  - Riverpod State Architecture              |
       |  - Biometric Hardware Authentication Gate   |
       |  - Local Keystore Private Keys              |
       +----------------------+----------------------+
                              |
                              | WSS (TLS + E2EE Envelopes)
                              v
       +---------------------------------------------+
       |             Zero-Knowledge Relay            |
       |  - Cloudflare Tunnel / VPS / Docker         |
       |  - RFC 6455 Pure WebSocket Router          |
       |  - Device-ID Forwarding Table               |
       |  - Zero Plaintext Visibility                |
       +----------------------+----------------------+
                              |
                              | WSS (TLS + E2EE Envelopes)
                              v
       +---------------------------------------------+
       |           Laptop Host Daemon (PC)           |
       |  - Real-time Brain Log Tailer               |
       |  - File-offset Delta Streaming              |
       |  - Antigravity CLI / IPC Bridge             |
       |  - Native X25519 & AES-256-GCM Engine       |
       +---------------------------------------------+
```

---

## 📦 Releases & Downloads (v0.1.1 Beta)

Pre-built binaries are available under [GitHub Releases (v0.1.1-beta)](https://github.com/Erorr40/antigravity-remote/releases):

| Platform | File | Description |
|---|---|---|
| **Windows PC** | [`AntigravityRemote-Setup.exe`](https://github.com/Erorr40/antigravity-remote/releases/download/v0.1.1/AntigravityRemote-Setup.exe) | Self-extracting Windows installer. Installs daemon runtime, launcher, and shortcuts. |
| **Android Phone** | [`AntigravityRemote-Android16.apk`](https://github.com/Erorr40/antigravity-remote/releases/download/v0.1.1/AntigravityRemote-Android16.apk) | Debug/release APK built with SDK 36 (Android 16 Baklava) & Min SDK 33 (Android 13). Includes all native ABIs. |

> ⚠️ **Beta Notice (v0.1.1)**: This is the initial beta preview release. Please test on non-critical workflows and report issues on GitHub.

---

## 🚀 Quick Start Guide

### 1. Host Laptop Setup (PC)

#### Option A: Using the Windows Installer (Recommended)
1. Download and run [`AntigravityRemote-Setup.exe`](https://github.com/Erorr40/antigravity-remote/releases/download/v0.1.1/AntigravityRemote-Setup.exe).
2. The installer extracts the daemon to `%LOCALAPPDATA%\AntigravityRemote` and registers desktop/start menu shortcuts.
3. Launch **Antigravity Remote Daemon** from your Start Menu.
4. Scan the pairing QR code displayed in the console window.

#### Option B: Running from Source
```bash
cd daemon
npm install
node index.js --pair
```

---

### 2. Android Phone Setup

1. Download [`AntigravityRemote-Android16.apk`](https://github.com/Erorr40/antigravity-remote/releases/download/v0.1.1/AntigravityRemote-Android16.apk).
2. Install the APK on your device:
   ```bash
   adb install AntigravityRemote-Android16.apk
   ```
   *(Or transfer to your phone and install via your file manager with "Install unknown apps" permission enabled).*
3. Open **Antigravity Remote**.
4. Grant Camera and Notification permissions.
5. Tap **Scan Pairing QR** and scan the QR code generated on your laptop.
6. Authenticate with your fingerprint/face to confirm pairing and unlock remote control.

---

### 3. Relay Server Setup (Self-Hosted)

The relay server routes encrypted messages between your laptop and mobile device when not on the same local network.

#### Docker Deployment
```bash
cd relay
docker compose up -d
```

#### Cloudflare Tunnel (Zero Port-Forwarding)
Run the relay locally behind a free Cloudflare Tunnel for secure HTTPS/WSS:
```bash
cloudflared tunnel --url ws://localhost:8080
```
Update your daemon configuration with your public `wss://...` URL.

---

## 📁 Repository Structure

```
antigravity-remote/
├── protocol/                      # Protocol definitions & specifications
│   ├── protocol.proto             # Protobuf schema
│   ├── types.ts                   # TypeScript contracts
│   └── schemas/                   # JSON schemas (handshake, heartbeat, etc.)
│
├── daemon/                        # Host laptop companion service (Node.js / C#)
│   ├── index.js                   # CLI entry point (--pair, --status)
│   ├── esbuild.config.mjs         # Bundle configuration
│   └── src/
│       ├── config.js              # Local identity & client keys
│       ├── crypto.js              # X25519 ECDH + AES-256-GCM
│       ├── qr.js                  # Pairing token generator & console QR
│       ├── transcript_watcher.js  # Antigravity brain transcript watcher
│       ├── artifacts_manager.js   # Session artifact & diff reader
│       ├── ipc_bridge.js          # Antigravity CLI injector & abort signal
│       └── relay_client.js        # WebSocket relay transport
│
├── installer/                     # Native Windows launcher & setup installer
│   ├── AntigravityDaemonLauncher.cs
│   └── AntigravitySetup.cs
│
├── relay/                         # Zero-knowledge WebSocket routing server
│   ├── server.js                  # RFC 6455 relay router
│   ├── Dockerfile                 # Docker container setup
│   ├── docker-compose.yml
│   ├── cloudflare-tunnel.md       # Cloudflare Tunnel guide
│   └── supabase-schema.sql        # Supabase Realtime schema alternative
│
├── mobile/                        # Flutter Android application
│   ├── pubspec.yaml
│   ├── android/                   # Android native project (API 36 / Android 16)
│   │   ├── app/build.gradle.kts   # compileSdk 36, targetSdk 36, minSdk 33
│   │   └── app/src/main/AndroidManifest.xml
│   └── lib/
│       ├── main.dart              # Material 3 setup & notification bootstrap
│       ├── core/                  # Crypto, storage, auth, notifications, network
│       ├── domain/                # Data models & session entities
│       └── presentation/          # Riverpod state notifiers, screens & widgets
│
└── release/                       # Release binaries (v0.1.1 Beta)
    ├── AntigravityRemote-Setup.exe
    └── AntigravityRemote-Android16.apk
```

---

## 🔐 Security & Encryption

Antigravity Remote implements end-to-end security designed to protect your code and AI sessions:

1. **Cryptographic Identity**: Laptop daemon and mobile client generate private Curve25519 key pairs locally on initial startup.
2. **Ephemeral Key Exchange**: During QR handshake, public keys are exchanged to derive a shared symmetric secret using **HKDF-SHA256**.
3. **Envelope Encryption**: All subsequent communications (brain logs, commands, diffs) are encrypted with **AES-256-GCM** using unique 96-bit initialization vectors (IVs).
4. **Relay Blindness**: The relay only reads the outer routing envelope (`target_device_id` and routing metadata). The payload field is completely opaque ciphertext.
5. **Biometric Guard**: Sending prompts, answering tool queries, or aborting tasks requires Android Biometric Authentication (Class 3 strong biometrics).

---

## 🛠️ Development & Building from Source

### Building Mobile Client
Prerequisites: Flutter 3.24+, Android SDK 33+, JDK 17+.
```bash
cd mobile
flutter pub get
flutter build apk --debug
```

### Building Host Daemon & Installer
Prerequisites: Node.js 18+, .NET Framework 4.0+ (`csc.exe`).
```bash
cd daemon
npm run build

cd ../installer
# Compile launcher and setup installer:
csc /target:winexe /out:antigravity-daemon.exe AntigravityDaemonLauncher.cs
csc /target:winexe /out:AntigravityRemote-Setup.exe AntigravitySetup.cs
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
