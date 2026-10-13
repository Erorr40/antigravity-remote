/**
 * Antigravity Off-LAN Relay Server
 * Lightweight, zero-dependency RFC 6455 WebSocket routing server
 * Routes End-to-End Encrypted (E2EE) packets between Mobile and Host Laptop
 */

const http = require('http');
const crypto = require('crypto');
const url = require('url');

const PORT = process.env.PORT || 8765;
const AUTH_SECRET = process.env.RELAY_AUTH_SECRET || ''; // Optional master relay auth token
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// Connected devices table: deviceId -> { socket, role, deviceId, lastSeen, ip }
const clients = new Map();

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  if (parsed.pathname === '/health' || parsed.pathname === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'healthy',
      connectedDevices: clients.size,
      hostsOnline: Array.from(clients.values()).filter(c => c.role === 'host').length,
      clientsOnline: Array.from(clients.values()).filter(c => c.role === 'client').length,
      uptime: process.uptime()
    }));
    return;
  }
  res.writeHead(404);
  res.end('Not Found');
});

// RFC 6455 Frame Parser & Sender Helpers
function sendWsFrame(socket, text) {
  if (socket.destroyed || !socket.writable) return;
  const payload = Buffer.from(text, 'utf8');
  const length = payload.length;

  let header;
  if (length <= 125) {
    header = Buffer.from([0x81, length]);
  } else if (length <= 65535) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(length), 2);
  }

  socket.write(Buffer.concat([header, payload]));
}

function parseWsFrames(buffer, onMessage) {
  let offset = 0;
  while (offset < buffer.length) {
    if (buffer.length - offset < 2) break;

    const byte1 = buffer[offset];
    const byte2 = buffer[offset + 1];
    const opcode = byte1 & 0x0f;
    const isMasked = (byte2 & 0x80) !== 0;
    let payloadLength = byte2 & 0x7f;
    let headerLength = 2;

    if (payloadLength === 126) {
      if (buffer.length - offset < 4) break;
      payloadLength = buffer.readUInt16BE(offset + 2);
      headerLength = 4;
    } else if (payloadLength === 127) {
      if (buffer.length - offset < 10) break;
      payloadLength = Number(buffer.readBigUInt64BE(offset + 2));
      headerLength = 10;
    }

    const maskOffset = offset + headerLength;
    const dataOffset = isMasked ? maskOffset + 4 : maskOffset;
    const totalFrame = dataOffset + payloadLength;

    if (buffer.length < totalFrame) break; // Incomplete frame

    let mask = null;
    if (isMasked) {
      mask = buffer.subarray(maskOffset, maskOffset + 4);
    }

    const rawData = buffer.subarray(dataOffset, totalFrame);
    const unmasked = Buffer.alloc(payloadLength);

    if (isMasked && mask) {
      for (let i = 0; i < payloadLength; i++) {
        unmasked[i] = rawData[i] ^ mask[i % 4];
      }
    } else {
      rawData.copy(unmasked);
    }

    // 0x1 = Text, 0x8 = Close, 0x9 = Ping, 0xA = Pong
    if (opcode === 0x1) {
      onMessage(unmasked.toString('utf8'));
    } else if (opcode === 0x8) {
      return -1; // Socket close
    }

    offset = totalFrame;
  }
  return offset;
}

// Handle WebSocket Upgrade
server.on('upgrade', (req, socket, head) => {
  const parsed = url.parse(req.url, true);
  const deviceId = parsed.query.deviceId;
  const role = parsed.query.role || 'client'; // 'host' or 'client'
  const token = parsed.query.token || req.headers['authorization']?.replace('Bearer ', '');

  // Auth validation if RELAY_AUTH_SECRET is set
  if (AUTH_SECRET && token !== AUTH_SECRET) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }

  if (!deviceId) {
    socket.write('HTTP/1.1 400 Bad Request: Missing deviceId\r\n\r\n');
    socket.destroy();
    return;
  }

  const key = req.headers['sec-websocket-key'];
  if (!key) {
    socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
    socket.destroy();
    return;
  }

  const accept = crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`
  );

  console.log(`[Relay] Connected: deviceId=${deviceId}, role=${role}`);
  clients.set(deviceId, {
    socket,
    role,
    deviceId,
    lastSeen: Date.now(),
    ip: req.socket.remoteAddress
  });

  // Notify clients if a host came online
  if (role === 'host') {
    broadcastPresence(deviceId, true);
  }

  let rxBuffer = Buffer.alloc(0);

  socket.on('data', (chunk) => {
    rxBuffer = Buffer.concat([rxBuffer, chunk]);
    const processed = parseWsFrames(rxBuffer, (textMsg) => {
      handleInboundMessage(deviceId, textMsg);
    });

    if (processed === -1) {
      socket.destroy();
    } else if (processed > 0) {
      rxBuffer = rxBuffer.subarray(processed);
    }
  });

  const cleanup = () => {
    if (clients.has(deviceId)) {
      console.log(`[Relay] Disconnected: deviceId=${deviceId}`);
      clients.delete(deviceId);
      if (role === 'host') {
        broadcastPresence(deviceId, false);
      }
    }
  };

  socket.on('close', cleanup);
  socket.on('error', cleanup);
});

function broadcastPresence(hostDeviceId, online) {
  const presenceEnvelope = JSON.stringify({
    messageId: `presence-${Date.now()}`,
    timestamp: Date.now(),
    type: 'HEARTBEAT_PONG',
    senderId: hostDeviceId,
    targetId: '*',
    plainPayload: {
      online,
      hostDeviceId
    }
  });

  for (const client of clients.values()) {
    if (client.role === 'client') {
      sendWsFrame(client.socket, presenceEnvelope);
    }
  }
}

function handleInboundMessage(senderId, rawText) {
  let envelope;
  try {
    envelope = JSON.parse(rawText);
  } catch (err) {
    console.warn(`[Relay] Invalid JSON from ${senderId}:`, err.message);
    return;
  }

  const targetId = envelope.targetId;

  // Broadcast presence or query
  if (targetId === '*') {
    for (const [id, client] of clients.entries()) {
      if (id !== senderId) {
        sendWsFrame(client.socket, rawText);
      }
    }
    return;
  }

  // Direct envelope delivery to recipient
  const recipient = clients.get(targetId);
  if (recipient) {
    sendWsFrame(recipient.socket, rawText);
  } else {
    // If target offline, send bounce back to sender
    const bounce = JSON.stringify({
      messageId: `bounce-${Date.now()}`,
      timestamp: Date.now(),
      type: 'RELAY_ERROR',
      senderId: 'relay',
      targetId: senderId,
      plainPayload: {
        errorCode: 'TARGET_OFFLINE',
        message: `Recipient device ${targetId} is currently offline.`,
        originalMessageId: envelope.messageId
      }
    });
    const sender = clients.get(senderId);
    if (sender) {
      sendWsFrame(sender.socket, bounce);
    }
  }
}

server.listen(PORT, () => {
  console.log(`[Relay] Antigravity Relay Server running on port ${PORT}`);
  console.log(`[Relay] Health endpoint: http://localhost:${PORT}/health`);
});
