/**
 * Terminal Pairing Display & QR Data Generator
 */

class QrService {
  static formatPairingPayload(config, token, expiresAt) {
    const payload = {
      v: 1,
      relayUrl: config.relayUrl,
      hostDeviceId: config.hostDeviceId,
      hostName: config.hostName,
      hostPublicKey: config.keys.publicKeyRawBase64,
      pairToken: token,
      expiresAt: expiresAt
    };
    return JSON.stringify(payload);
  }

  static renderTerminalBox(title, lines) {
    const maxLen = Math.max(title.length, ...lines.map(l => l.length)) + 4;
    const border = '='.repeat(maxLen);
    console.log(`\n+${border}+`);
    console.log(`|  ${title.padEnd(maxLen - 2)}|`);
    console.log(`+${border}+`);
    for (const line of lines) {
      console.log(`|  ${line.padEnd(maxLen - 2)}|`);
    }
    console.log(`+${border}+\n`);
  }
}

module.exports = {
  QrService
};
