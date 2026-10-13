#!/usr/bin/env node

const { configManager, BRAIN_DIR, ANTIGRAVITY_APP_DATA } = require('./src/config');
const { TranscriptWatcher } = require('./src/transcript_watcher');
const { ArtifactsManager } = require('./src/artifacts_manager');
const { IpcBridge } = require('./src/ipc_bridge');
const { HostRelayClient } = require('./src/relay_client');
const { QrService } = require('./src/qr');

const args = process.argv.slice(2);

function showHelp() {
  console.log(`
Antigravity Remote Companion Daemon (v1.0.0)
Secure Laptop Host Bridge for Android 13+ Mobile Client

Usage:
  node index.js [options]

Options:
  --pair          Generate a short-lived QR pairing code for mobile client
  --status        Display host status, registered devices, and paths
  --relay <url>   Set or override Relay server URL (e.g. wss://relay.yourdomain.com)
  --help          Show this help message
`);
}

function handlePair() {
  const config = configManager.get();
  const { token, expiresAt } = configManager.generatePairingToken(15);
  const qrJson = QrService.formatPairingPayload(config, token, expiresAt);

  QrService.renderTerminalBox('ANTIGRAVITY REMOTE - MOBILE PAIRING TOKEN', [
    `Host Device:  ${config.hostName} (${config.hostDeviceId})`,
    `Relay Server: ${config.relayUrl}`,
    `Pair Token:   ${token}`,
    `Expires In:   15 minutes`,
    '',
    'SCAN OR COPY PAIRING JSON INTO ANDROID APP:',
    qrJson
  ]);
}

function handleStatus() {
  const config = configManager.get();
  const pairedCount = Object.keys(config.pairedClients).length;

  QrService.renderTerminalBox('HOST DAEMON STATUS', [
    `Host Device ID:  ${config.hostDeviceId}`,
    `Host Name:       ${config.hostName}`,
    `Relay Server:    ${config.relayUrl}`,
    `Brain Directory: ${config.brainDir}`,
    `Paired Devices:  ${pairedCount}`,
    ...Object.entries(config.pairedClients).map(
      ([id, info]) => `  - ${info.deviceName} (${id})`
    )
  ]);
}

async function startDaemon() {
  const config = configManager.get();

  // Override relay URL if passed in CLI
  const relayIndex = args.indexOf('--relay');
  if (relayIndex !== -1 && args[relayIndex + 1]) {
    configManager.updateRelayUrl(args[relayIndex + 1]);
  }

  console.log('========================================================');
  console.log('  Antigravity Remote Companion Daemon starting...');
  console.log(`  Host Device:  ${config.hostName} (${config.hostDeviceId})`);
  console.log(`  Relay Target: ${config.relayUrl}`);
  console.log(`  Brain Dir:    ${BRAIN_DIR}`);
  console.log('========================================================');

  const transcriptWatcher = new TranscriptWatcher(BRAIN_DIR);
  const artifactsManager = new ArtifactsManager(BRAIN_DIR);
  const ipcBridge = new IpcBridge(ANTIGRAVITY_APP_DATA);

  const relayClient = new HostRelayClient({
    configManager,
    transcriptWatcher,
    artifactsManager,
    ipcBridge
  });

  relayClient.connect();

  // If no paired devices yet, auto-print pairing token to terminal
  const pairedCount = Object.keys(config.pairedClients).length;
  if (pairedCount === 0) {
    console.log('\n[Daemon] No paired mobile devices found. Generating initial pairing token:');
    handlePair();
  }

  // Graceful shutdown
  const shutdown = () => {
    console.log('\n[Daemon] Shutting down daemon...');
    relayClient.stopHeartbeat();
    transcriptWatcher.stopWatching();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

if (args.includes('--help')) {
  showHelp();
} else if (args.includes('--pair')) {
  handlePair();
} else if (args.includes('--status')) {
  handleStatus();
} else {
  startDaemon();
}
