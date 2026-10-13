const crypto = require('crypto');

// Standard X25519 SPKI prefix (12 bytes)
const X25519_SPKI_HEADER = Buffer.from('302a300506032b656e032100', 'hex');

class CryptoEngine {
  /**
   * Convert raw 32-byte base64 X25519 public key to Node KeyObject
   */
  static rawPublicKeyToKeyObject(rawBase64) {
    const rawBytes = Buffer.from(rawBase64, 'base64');
    if (rawBytes.length !== 32) {
      throw new Error(`Invalid X25519 public key length: ${rawBytes.length}, expected 32 bytes`);
    }
    const spkiDer = Buffer.concat([X25519_SPKI_HEADER, rawBytes]);
    return crypto.createPublicKey({
      key: spkiDer,
      format: 'der',
      type: 'spki'
    });
  }

  /**
   * Compute shared secret using host private key and mobile public key
   */
  static computeSharedSecret(hostPrivateKeyPem, mobilePublicKeyRawBase64) {
    const mobileKeyObj = this.rawPublicKeyToKeyObject(mobilePublicKeyRawBase64);
    const hostKeyObj = crypto.createPrivateKey(hostPrivateKeyPem);
    return crypto.diffieHellman({
      privateKey: hostKeyObj,
      publicKey: mobileKeyObj
    });
  }

  /**
   * Derive 256-bit AES-GCM key from shared secret using HKDF
   */
  static deriveSessionKey(sharedSecret, salt = Buffer.alloc(16, 0), info = 'antigravity-remote-e2ee') {
    const rawKey = crypto.hkdfSync('sha256', sharedSecret, salt, Buffer.from(info, 'utf8'), 32);
    return Buffer.from(rawKey);
  }

  /**
   * Encrypt message with AES-256-GCM
   * Returns { nonce: base64, ciphertext: base64 } (auth tag appended to ciphertext)
   */
  static encrypt(sessionKey, plaintextObj, sequenceNumber = 0) {
    const nonce = crypto.randomBytes(12); // 96-bit nonce
    const cipher = crypto.createCipheriv('aes-256-gcm', sessionKey, nonce);
    
    // Additional authenticated data (AAD) binds sequence number
    const aad = Buffer.alloc(8);
    aad.writeBigInt64BE(BigInt(sequenceNumber), 0);
    cipher.setAAD(aad);

    const plaintext = Buffer.from(JSON.stringify(plaintextObj), 'utf8');
    const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const authTag = cipher.getAuthTag();

    // Ciphertext with appended 16-byte tag
    const ciphertextWithTag = Buffer.concat([encrypted, authTag]);

    return {
      nonce: nonce.toString('base64'),
      ciphertext: ciphertextWithTag.toString('base64'),
      sequenceNumber
    };
  }

  /**
   * Decrypt AES-256-GCM container
   */
  static decrypt(sessionKey, nonceBase64, ciphertextBase64, sequenceNumber = 0) {
    const nonce = Buffer.from(nonceBase64, 'base64');
    const ciphertextWithTag = Buffer.from(ciphertextBase64, 'base64');
    
    if (ciphertextWithTag.length < 16) {
      throw new Error('Ciphertext too short to contain authentication tag');
    }

    const authTag = ciphertextWithTag.subarray(ciphertextWithTag.length - 16);
    const ciphertext = ciphertextWithTag.subarray(0, ciphertextWithTag.length - 16);

    const decipher = crypto.createDecipheriv('aes-256-gcm', sessionKey, nonce);
    const aad = Buffer.alloc(8);
    aad.writeBigInt64BE(BigInt(sequenceNumber), 0);
    decipher.setAAD(aad);
    decipher.setAuthTag(authTag);

    const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    return JSON.parse(decrypted.toString('utf8'));
  }
}

module.exports = {
  CryptoEngine
};
