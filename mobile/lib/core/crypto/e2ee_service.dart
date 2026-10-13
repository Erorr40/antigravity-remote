import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class E2eeService {
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );

  /// Generate fresh ephemeral or persistent mobile X25519 keypair
  Future<SimpleKeyPair> generateKeyPair() async {
    return await _x25519.newKeyPair();
  }

  /// Convert public key to raw 32-byte Base64 string for exchange
  Future<String> exportPublicKeyRawBase64(SimpleKeyPair keyPair) async {
    final pubKey = await keyPair.extractPublicKey();
    return base64Encode(pubKey.bytes);
  }

  /// Derive shared AES-256-GCM symmetric key matching daemon HKDF
  Future<SecretKey> deriveSessionKey({
    required SimpleKeyPair mobileKeyPair,
    required String hostPublicKeyRawBase64,
  }) async {
    final hostRawBytes = base64Decode(hostPublicKeyRawBase64);
    final hostPublicKey = SimplePublicKey(hostRawBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: mobileKeyPair,
      remotePublicKey: hostPublicKey,
    );

    // HKDF with zero salt and "antigravity-remote-e2ee" info string
    final salt = Uint8List(16);
    final info = utf8.encode('antigravity-remote-e2ee');

    return await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: info,
    );
  }

  /// Encrypt payload with AES-256-GCM, returning Base64 nonce and ciphertext with tag
  Future<Map<String, dynamic>> encryptPayload({
    required SecretKey sessionKey,
    required Map<String, dynamic> plaintextJson,
    required int sequenceNumber,
  }) async {
    final plaintextBytes = utf8.encode(jsonEncode(plaintextJson));
    final aad = Uint8List(8);
    ByteData.view(aad.buffer).setInt64(0, sequenceNumber, Endian.big);

    final secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: sessionKey,
      aad: aad,
    );

    // Concatenate ciphertext and 16-byte MAC tag matching daemon format
    final combinedCiphertext = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    return {
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(combinedCiphertext),
      'sequenceNumber': sequenceNumber,
    };
  }

  /// Decrypt incoming ciphertext from daemon
  Future<Map<String, dynamic>> decryptPayload({
    required SecretKey sessionKey,
    required String nonceBase64,
    required String ciphertextBase64,
    required int sequenceNumber,
  }) async {
    final nonce = base64Decode(nonceBase64);
    final combinedCiphertext = base64Decode(ciphertextBase64);

    if (combinedCiphertext.length < 16) {
      throw Exception('Ciphertext too short for authentication tag');
    }

    final cipherTextLength = combinedCiphertext.length - 16;
    final cipherText = combinedCiphertext.sublist(0, cipherTextLength);
    final macBytes = combinedCiphertext.sublist(cipherTextLength);

    final aad = Uint8List(8);
    ByteData.view(aad.buffer).setInt64(0, sequenceNumber, Endian.big);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decryptedBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: sessionKey,
      aad: aad,
    );

    final jsonString = utf8.decode(decryptedBytes);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }
}
