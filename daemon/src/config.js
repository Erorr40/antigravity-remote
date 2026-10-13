const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const HOME_DIR = os.homedir();
const REMOTE_CONFIG_DIR = path.join(HOME_DIR, '.antigravity-remote');
const CONFIG_FILE = path.join(REMOTE_CONFIG_DIR, 'config.json');

// Default Antigravity Brain path
const ANTIGRAVITY_APP_DATA = path.join(HOME_DIR, '.gemini', 'antigravity');
const BRAIN_DIR = path.join(ANTIGRAVITY_APP_DATA, 'brain');

class ConfigManager {
  constructor() {
    this.config = null;
    this.ensureInitialized();
  }

  ensureInitialized() {
    if (!fs.existsSync(REMOTE_CONFIG_DIR)) {
      fs.mkdirSync(REMOTE_CONFIG_DIR, { recursive: true });
    }

    if (fs.existsSync(CONFIG_FILE)) {
      try {
        const raw = fs.readFileSync(CONFIG_FILE, 'utf8');
        this.config = JSON.parse(raw);
      } catch (err) {
        console.warn('[Config] Failed to parse existing config, creating fresh:', err.message);
      }
    }

    if (!this.config) {
      // Generate persistent X25519 keypair for laptop daemon identity
      const keypair = crypto.generateKeyPairSync('x25519', {
        publicKeyEncoding: { type: 'spki', format: 'pem' },
        privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
      });

      this.config = {
        hostDeviceId: `host-${crypto.randomUUID()}`,
        hostName: os.hostname(),
        relayUrl: process.env.RELAY_URL || 'ws://localhost:8765',
        keys: {
          publicKeyPem: keypair.publicKey,
          privateKeyPem: keypair.privateKey,
          // Raw 32 bytes base64 for easy exchange with Dart/Flutter
          publicKeyRawBase64: this.extractRawPublicKey(keypair.publicKey)
        },
        pairedClients: {}, // mobileDeviceId -> { deviceName, publicKeyRawBase64, pairedAt }
        activePairingToken: null,
        pairingExpiresAt: 0,
        brainDir: BRAIN_DIR,
        antigravityAppData: ANTIGRAVITY_APP_DATA
      };
      this.save();
    }
  }

  extractRawPublicKey(pem) {
    // DER SPKI for X25519 is 44 bytes, raw key is the last 32 bytes
    const der = Buffer.from(
      pem.replace(/-----[^\n]+-----/g, '').replace(/\s+/g, ''),
      'base64'
    );
    // Raw public key is last 32 bytes of 44 byte SPKI DER
    const rawKey = der.subarray(der.length - 32);
    return rawKey.toString('base64');
  }

  save() {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(this.config, null, 2), 'utf8');
  }

  get() {
    return this.config;
  }

  updateRelayUrl(url) {
    this.config.relayUrl = url;
    this.save();
  }

  generatePairingToken(ttlMinutes = 15) {
    const token = crypto.randomBytes(16).toString('hex');
    const expiresAt = Date.now() + ttlMinutes * 60 * 1000;
    this.config.activePairingToken = token;
    this.config.pairingExpiresAt = expiresAt;
    this.save();
    return { token, expiresAt };
  }

  reload() {
    if (fs.existsSync(CONFIG_FILE)) {
      try {
        const raw = fs.readFileSync(CONFIG_FILE, 'utf8');
        this.config = JSON.parse(raw);
      } catch (err) {
        console.warn('[Config] Failed to reload config:', err.message);
      }
    }
  }

  validatePairingToken(token) {
    this.reload();
    if (!this.config.activePairingToken || this.config.activePairingToken !== token) {
      return false;
    }
    if (Date.now() > this.config.pairingExpiresAt) {
      return false;
    }
    return true;
  }

  addPairedClient(mobileDeviceId, deviceName, publicKeyRawBase64) {
    this.config.pairedClients[mobileDeviceId] = {
      deviceName,
      publicKeyRawBase64,
      pairedAt: Date.now()
    };
    // Clear pairing token once paired
    this.config.activePairingToken = null;
    this.config.pairingExpiresAt = 0;
    this.save();
  }

  removePairedClient(mobileDeviceId) {
    delete this.config.pairedClients[mobileDeviceId];
    this.save();
  }
}

module.exports = {
  configManager: new ConfigManager(),
  BRAIN_DIR,
  ANTIGRAVITY_APP_DATA
};
