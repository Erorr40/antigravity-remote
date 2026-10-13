const os = require('os');
const { CryptoEngine } = require('./crypto');

class HostRelayClient {
  constructor({ configManager, transcriptWatcher, artifactsManager, ipcBridge }) {
    this.configManager = configManager;
    this.transcriptWatcher = transcriptWatcher;
    this.artifactsManager = artifactsManager;
    this.ipcBridge = ipcBridge;

    this.ws = null;
    this.isConnected = false;
    this.heartbeatTimer = null;
    this.reconnectTimer = null;
    this.sessionKeys = new Map(); // mobileDeviceId -> derived AES sessionKey Buffer
    this.seqCounter = 0;

    // Listen for live transcript delta events and broadcast to paired clients
    this.transcriptWatcher.on('transcript_delta', (delta) => {
      this.broadcastEncryptedDelta(delta);
    });
  }

  connect() {
    const config = this.configManager.get();
    const relayUrl = `${config.relayUrl}?deviceId=${config.hostDeviceId}&role=host`;

    console.log(`[RelayClient] Connecting to relay at ${relayUrl}...`);

    try {
      this.ws = new WebSocket(relayUrl);

      this.ws.onopen = () => {
        this.isConnected = true;
        console.log(`[RelayClient] Connected to relay successfully as ${config.hostDeviceId}`);
        this.startHeartbeat();
      };

      this.ws.onmessage = async (event) => {
        try {
          const raw = typeof event.data === 'string' ? event.data : event.data.toString();
          const envelope = JSON.parse(raw);
          await this.handleEnvelope(envelope);
        } catch (err) {
          console.error('[RelayClient] Error processing envelope:', err);
        }
      };

      this.ws.onclose = () => {
        this.isConnected = false;
        this.stopHeartbeat();
        console.warn('[RelayClient] Connection closed. Reconnecting in 3s...');
        this.scheduleReconnect();
      };

      this.ws.onerror = (err) => {
        console.error('[RelayClient] WebSocket error:', err.message || err);
      };
    } catch (err) {
      console.error('[RelayClient] Connect exception:', err.message);
      this.scheduleReconnect();
    }
  }

  scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, 3000);
  }

  startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.sendHeartbeat();
    }, 15000);
  }

  stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  sendHeartbeat() {
    if (!this.isConnected || !this.ws) return;
    const config = this.configManager.get();
    const envelope = {
      messageId: `hb-${Date.now()}`,
      timestamp: Date.now(),
      type: 'HEARTBEAT_PONG',
      senderId: config.hostDeviceId,
      targetId: '*', // broadcast presence to relay
      plainPayload: {
        online: true,
        hostOs: `${os.type()} ${os.release()} (${os.arch()})`,
        activeSessionId: this.transcriptWatcher.currentLiveSessionId,
        activeTasksCount: this.ipcBridge.activeProcesses.size,
        hostVersion: '1.0.0',
        uptimeSeconds: Math.floor(os.uptime()),
        memoryUsagePercent: Math.round(((os.totalmem() - os.freemem()) / os.totalmem()) * 100)
      }
    };
    this.send(envelope);
  }

  send(envelope) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(envelope));
    }
  }

  /**
   * Main router for inbound relay messages
   */
  async handleEnvelope(envelope) {
    const config = this.configManager.get();

    switch (envelope.type) {
      case 'HEARTBEAT_PING':
        this.sendHeartbeat();
        break;

      case 'PAIRING_REQUEST':
        await this.handlePairingRequest(envelope);
        break;

      case 'ENCRYPTED_CONTAINER':
        await this.handleEncryptedMessage(envelope);
        break;

      default:
        console.log(`[RelayClient] Received unhandled envelope type: ${envelope.type}`);
    }
  }

  /**
   * Handle pairing request from mobile client
   */
  async handlePairingRequest(envelope) {
    const config = this.configManager.get();
    const { pairToken, mobileDeviceId, deviceName, mobilePublicKey } = envelope.plainPayload || {};

    console.log(`[RelayClient] Pairing attempt from: ${deviceName} (${mobileDeviceId})`);

    const isValid = this.configManager.validatePairingToken(pairToken);
    if (!isValid) {
      console.warn(`[RelayClient] Invalid or expired pairing token: ${pairToken}`);
      this.send({
        messageId: `pair-res-${Date.now()}`,
        timestamp: Date.now(),
        type: 'PAIRING_RESPONSE',
        senderId: config.hostDeviceId,
        targetId: envelope.senderId,
        plainPayload: {
          success: false,
          hostDeviceId: config.hostDeviceId,
          errorMessage: 'Pairing token invalid or expired. Rescan QR code on laptop.'
        }
      });
      return;
    }

    // Persist paired client
    this.configManager.addPairedClient(mobileDeviceId, deviceName, mobilePublicKey);

    // Derive and cache session key
    const sharedSecret = CryptoEngine.computeSharedSecret(config.keys.privateKeyPem, mobilePublicKey);
    const sessionKey = CryptoEngine.deriveSessionKey(sharedSecret);
    this.sessionKeys.set(mobileDeviceId, sessionKey);

    console.log(`[RelayClient] Successfully paired with ${deviceName} (${mobileDeviceId})!`);

    this.send({
      messageId: `pair-res-${Date.now()}`,
      timestamp: Date.now(),
      type: 'PAIRING_RESPONSE',
      senderId: config.hostDeviceId,
      targetId: envelope.senderId,
      plainPayload: {
        success: true,
        hostDeviceId: config.hostDeviceId,
        hostPublicKey: config.keys.publicKeyRawBase64
      }
    });
  }

  /**
   * Decrypt and dispatch E2EE commands from mobile
   */
  async handleEncryptedMessage(envelope) {
    const config = this.configManager.get();
    const senderId = envelope.senderId;
    const pairedClient = config.pairedClients[senderId];

    if (!pairedClient) {
      console.warn(`[RelayClient] Rejected encrypted message from unauthorized device: ${senderId}`);
      return;
    }

    // Get or compute session key
    let sessionKey = this.sessionKeys.get(senderId);
    if (!sessionKey) {
      const sharedSecret = CryptoEngine.computeSharedSecret(
        config.keys.privateKeyPem,
        pairedClient.publicKeyRawBase64
      );
      sessionKey = CryptoEngine.deriveSessionKey(sharedSecret);
      this.sessionKeys.set(senderId, sessionKey);
    }

    const { nonce, ciphertext, sequenceNumber } = envelope.encryptedPayload || {};

    let inner;
    try {
      inner = CryptoEngine.decrypt(sessionKey, nonce, ciphertext, sequenceNumber);
    } catch (err) {
      console.error(`[RelayClient] Decryption failed for device ${senderId}:`, err.message);
      return;
    }

    // Route inner action
    let responseAction = null;
    let responsePayload = null;

    try {
      switch (inner.action) {
        case 'REQ_SESSION_LIST': {
          const sessions = await this.transcriptWatcher.listSessions(inner.payload?.limit || 30);
          responseAction = 'RESP_SESSION_LIST';
          responsePayload = { sessions };
          break;
        }

        case 'REQ_TRANSCRIPT_SYNC': {
          const { sessionId, fromStepIndex } = inner.payload || {};
          const snapshot = await this.transcriptWatcher.getTranscriptSnapshot(sessionId, fromStepIndex || 0);
          this.transcriptWatcher.watchSession(sessionId);
          responseAction = 'RESP_TRANSCRIPT_SNAPSHOT';
          responsePayload = snapshot;
          break;
        }

        case 'CMD_DISPATCH_PROMPT': {
          const ack = await this.ipcBridge.dispatchPrompt(inner.payload);
          responseAction = 'RESP_COMMAND_ACK';
          responsePayload = ack;
          break;
        }

        case 'CMD_ABORT_TASK': {
          const ack = await this.ipcBridge.abortTask(inner.payload);
          responseAction = 'RESP_COMMAND_ACK';
          responsePayload = ack;
          break;
        }

        case 'CMD_SEND_TOOL_INPUT': {
          const ack = await this.ipcBridge.handleToolInput(inner.payload);
          responseAction = 'RESP_COMMAND_ACK';
          responsePayload = ack;
          break;
        }

        case 'REQ_ARTIFACT_LIST': {
          const artifacts = await this.artifactsManager.listArtifacts(inner.payload?.sessionId);
          responseAction = 'RESP_ARTIFACT_LIST';
          responsePayload = { sessionId: inner.payload?.sessionId, artifacts };
          break;
        }

        case 'REQ_ARTIFACT_CONTENT': {
          const content = await this.artifactsManager.getArtifactContent(
            inner.payload?.sessionId,
            inner.payload?.fileName
          );
          responseAction = 'RESP_ARTIFACT_CONTENT';
          responsePayload = content;
          break;
        }

        default:
          console.warn(`[RelayClient] Unknown inner action: ${inner.action}`);
      }
    } catch (actionErr) {
      responseAction = 'RESP_COMMAND_ACK';
      responsePayload = {
        requestId: inner.innerId,
        success: false,
        message: actionErr.message,
        timestamp: Date.now()
      };
    }

    if (responseAction && responsePayload) {
      this.sendEncryptedResponse(senderId, responseAction, responsePayload, inner.sessionId);
    }
  }

  sendEncryptedResponse(targetId, action, payload, sessionId) {
    const config = this.configManager.get();
    const sessionKey = this.sessionKeys.get(targetId);
    if (!sessionKey) return;

    this.seqCounter++;
    const innerMsg = {
      innerId: `resp-${Date.now()}`,
      timestamp: Date.now(),
      action,
      sessionId,
      payload
    };

    const encrypted = CryptoEngine.encrypt(sessionKey, innerMsg, this.seqCounter);

    const envelope = {
      messageId: `env-${Date.now()}`,
      timestamp: Date.now(),
      type: 'ENCRYPTED_CONTAINER',
      senderId: config.hostDeviceId,
      targetId,
      encryptedPayload: {
        senderKeyId: config.keys.publicKeyRawBase64.slice(0, 8),
        nonce: encrypted.nonce,
        ciphertext: encrypted.ciphertext,
        sequenceNumber: encrypted.sequenceNumber
      }
    };

    this.send(envelope);
  }

  broadcastEncryptedDelta(delta) {
    const config = this.configManager.get();
    for (const [mobileDeviceId] of Object.entries(config.pairedClients)) {
      this.sendEncryptedResponse(mobileDeviceId, 'EVT_TRANSCRIPT_DELTA', delta, delta.sessionId);
    }
  }
}

module.exports = {
  HostRelayClient
};
