import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart';

// ✅ Supported algorithms
enum EncryptionAlgorithm { AES, AESGCM, RSA, ChaCha20, ECDSA_P256 }

class EncryptionService {
  // Some inputs (keys/ciphertexts) may not be properly padded base64url.
  // `base64Url.normalize` can throw a RangeError for certain invalid lengths,
  // so we do safe padding ourselves and fall back gracefully.
  static Uint8List _decodeBase64UrlLenient(String input) {
    final s = input.trim();
    if (s.isEmpty) return Uint8List(0);
    final mod = s.length % 4;
    // If mod == 1, it's not valid base64/base64url, but we still try fallbacks.
    final padded = mod == 0 ? s : (mod == 1 ? s : s.padRight(s.length + (4 - mod), '='));
    return Uint8List.fromList(base64Url.decode(padded));
  }

  static Uint8List _decodeBase64Lenient(String input) {
    final s = input.trim();
    if (s.isEmpty) return Uint8List(0);
    try {
      return Uint8List.fromList(base64.decode(s));
    } catch (_) {
      // Some callers may pass base64url; try that too.
      return _decodeBase64UrlLenient(s);
    }
  }

  // ═══════════════════════════════════════════
  // 🔑 KEY GENERATION
  // ═══════════════════════════════════════════

  static String generateAESKey() {
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(keyBytes);
  }

  static String generateChaCha20Key() {
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(keyBytes);
  }

  static Map<String, String> generateRSAKeyPair() {
    final keyGen = RSAKeyGenerator();
    final secureRandom = FortunaRandom();

    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    keyGen.init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
      secureRandom,
    ));

    final pair = keyGen.generateKeyPair();
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;

    return {
      'publicKey': _encodeRSAPublicKey(publicKey),
      'privateKey': _encodeRSAPrivateKey(privateKey),
    };
  }

  // ═══════════════════════════════════════════
  // 🔑 ECC / ECDH (P-256) KEY GENERATION
  // ═══════════════════════════════════════════

  static Map<String, String> generateEcdhKeyPairP256() {
    final keyGen = ECKeyGenerator();
    final secureRandom = FortunaRandom();

    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final params = ECKeyGeneratorParameters(ECDomainParameters('secp256r1'));
    keyGen.init(ParametersWithRandom(params, secureRandom));

    final pair = keyGen.generateKeyPair();
    final pub = pair.publicKey as ECPublicKey;
    final priv = pair.privateKey as ECPrivateKey;

    final pubBytes = pub.Q!.getEncoded(false); // uncompressed
    final privBytes = _bigIntToFixedBytes(priv.d!, 32);

    return {
      'publicKey': base64Url.encode(pubBytes),
      'privateKey': base64Url.encode(privBytes),
    };
  }

  // ═══════════════════════════════════════════
  // ✍️ ECDSA (P-256) SIGN / VERIFY
  // ═══════════════════════════════════════════

  static String signEcdsaP256({
    required String message,
    required String privateKeyBase64Url,
  }) {
    final domain = ECDomainParameters('secp256r1');
    final privBytes = _decodeBase64UrlLenient(privateKeyBase64Url);
    final d = _bigIntFromBytes(Uint8List.fromList(privBytes));
    final priv = ECPrivateKey(d, domain);

    final hash = SHA256Digest().process(Uint8List.fromList(utf8.encode(message)));
    final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
    signer.init(true, PrivateKeyParameter<ECPrivateKey>(priv));
    final sig = signer.generateSignature(hash) as ECSignature;

    final r = _bigIntToFixedBytes(sig.r, 32);
    final s = _bigIntToFixedBytes(sig.s, 32);
    return base64Url.encode(Uint8List.fromList([...r, ...s]));
  }

  static bool verifyEcdsaP256({
    required String message,
    required String signatureBase64Url,
    required String publicKeyBase64Url,
  }) {
    try {
      final domain = ECDomainParameters('secp256r1');
      final pubBytes = _decodeBase64UrlLenient(publicKeyBase64Url);
      final Q = domain.curve.decodePoint(Uint8List.fromList(pubBytes));
      if (Q == null) return false;
      final pub = ECPublicKey(Q, domain);

      final sigBytes = _decodeBase64UrlLenient(signatureBase64Url);
      if (sigBytes.length != 64) return false;
      final r = _bigIntFromBytes(Uint8List.fromList(sigBytes.sublist(0, 32)));
      final s = _bigIntFromBytes(Uint8List.fromList(sigBytes.sublist(32, 64)));

      final hash =
          SHA256Digest().process(Uint8List.fromList(utf8.encode(message)));
      final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
      signer.init(false, PublicKeyParameter<ECPublicKey>(pub));
      return signer.verifySignature(hash, ECSignature(r, s));
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════
  // 🔑 KEY HELPER — Fixed: uses List<int>.from()
  // ═══════════════════════════════════════════

  static Uint8List _safeDecodeKey(String keyBase64) {
    try {
      // ✅ List<int>.from() makes it growable (not fixed-length)
      List<int> bytes = List<int>.from(
        _decodeBase64UrlLenient(keyBase64),
      );
      while (bytes.length < 32) {
        bytes.add(0);
      }
      return Uint8List.fromList(bytes.sublist(0, 32));
    } catch (_) {
      try {
        List<int> bytes = List<int>.from(_decodeBase64Lenient(keyBase64));
        while (bytes.length < 32) {
          bytes.add(0);
        }
        return Uint8List.fromList(bytes.sublist(0, 32));
      } catch (_) {
        List<int> bytes = List<int>.from(utf8.encode(keyBase64));
        while (bytes.length < 32) {
          bytes.add(0);
        }
        return Uint8List.fromList(bytes.sublist(0, 32));
      }
    }
  }

  static Uint8List _bigIntToFixedBytes(BigInt v, int len) {
    final out = Uint8List(len);
    var x = v;
    for (var i = len - 1; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static BigInt _bigIntFromBytes(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static String deriveSharedKeyEcdhP256({
    required String myPrivateKeyBase64Url,
    required String theirPublicKeyBase64Url,
  }) {
    final domain = ECDomainParameters('secp256r1');
    final myPrivBytes = _decodeBase64UrlLenient(myPrivateKeyBase64Url);
    final theirPubBytes = _decodeBase64UrlLenient(theirPublicKeyBase64Url);

    final d = _bigIntFromBytes(Uint8List.fromList(myPrivBytes));
    final Q = domain.curve.decodePoint(Uint8List.fromList(theirPubBytes));
    if (Q == null) {
      throw Exception('Invalid ECDH public key');
    }

    // Shared point = d * Q
    final sharedPoint = Q * d;
    final xBytes = _bigIntToFixedBytes(sharedPoint!.x!.toBigInteger()!, 32);

    // Simple KDF: SHA-256(x)
    final digest = SHA256Digest().process(xBytes);
    return base64Url.encode(digest);
  }

  // ═══════════════════════════════════════════
  // 🔐 MAIN ENCRYPT
  // ═══════════════════════════════════════════

  static String encrypt(
    String plainText,
    String keyBase64,
    EncryptionAlgorithm algorithm,
  ) {
    try {
      switch (algorithm) {
        case EncryptionAlgorithm.AES:
          return _encryptAES(plainText, keyBase64);
        case EncryptionAlgorithm.AESGCM:
          return _encryptAESGCM(plainText, keyBase64);
        case EncryptionAlgorithm.RSA:
          return _encryptRSA(plainText, keyBase64);
        case EncryptionAlgorithm.ChaCha20:
          return _encryptChaCha20(plainText, keyBase64);
        case EncryptionAlgorithm.ECDSA_P256:
          throw Exception('ECDSA is for sign/verify, not encryption');
      }
    } catch (e) {
      throw Exception("Encryption failed: $e");
    }
  }

  // ═══════════════════════════════════════════
  // 🔓 MAIN DECRYPT
  // ═══════════════════════════════════════════

  static String decrypt(
    String encryptedText,
    String keyBase64,
    EncryptionAlgorithm algorithm,
  ) {
    try {
      switch (algorithm) {
        case EncryptionAlgorithm.AES:
          return _decryptAES(encryptedText, keyBase64);
        case EncryptionAlgorithm.AESGCM:
          return _decryptAESGCM(encryptedText, keyBase64);
        case EncryptionAlgorithm.RSA:
          return _decryptRSA(encryptedText, keyBase64);
        case EncryptionAlgorithm.ChaCha20:
          return _decryptChaCha20(encryptedText, keyBase64);
        case EncryptionAlgorithm.ECDSA_P256:
          return "[Invalid: ECDSA is not a decryption algorithm]";
      }
    } catch (e) {
      return "[Decryption Failed: $e]";
    }
  }

  // ═══════════════════════════════════════════
  // 🔹 AES ENCRYPTION (CBC mode, 256-bit)
  // ═══════════════════════════════════════════

  static String _encryptAES(String plainText, String keyBase64) {
    final keyBytes = _safeDecodeKey(keyBase64);
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(16);

    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc),
    );

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    final ivEncoded = base64Url.encode(iv.bytes);
    final dataEncoded = encrypted.base64;
    return "$ivEncoded:$dataEncoded";
  }

  static String _decryptAES(String encryptedText, String keyBase64) {
    final parts = encryptedText.split(":");
    if (parts.length < 2) return "[Invalid AES format]";

    final keyBytes = _safeDecodeKey(keyBase64);
    final key = enc.Key(keyBytes);

    Uint8List ivBytes;
    try {
      ivBytes = _decodeBase64UrlLenient(parts[0]);
    } catch (_) {
      ivBytes = _decodeBase64Lenient(parts[0]);
    }

    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc),
    );

    final encryptedData = parts.sublist(1).join(":");
    return encrypter.decrypt64(encryptedData, iv: iv);
  }

  // ═══════════════════════════════════════════
  // 🔹 AES-GCM ENCRYPTION (256-bit, authenticated)
  // ═══════════════════════════════════════════

  static String _encryptAESGCM(String plainText, String keyBase64) {
    final key = _safeDecodeKey(keyBase64);
    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => random.nextInt(256)),
    );

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
    );

    final input = Uint8List.fromList(utf8.encode(plainText));
    final out = cipher.process(input);

    return "${base64Url.encode(nonce)}:${base64Url.encode(out)}";
  }

  static String _decryptAESGCM(String encryptedText, String keyBase64) {
    final parts = encryptedText.split(":");
    if (parts.length < 2) return "[Invalid AESGCM format]";

    final key = _safeDecodeKey(keyBase64);
    final nonce = _decodeBase64UrlLenient(parts[0]);
    final data = _decodeBase64UrlLenient(parts[1]);

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      false,
      AEADParameters(KeyParameter(key), 128, Uint8List.fromList(nonce), Uint8List(0)),
    );

    final out = cipher.process(Uint8List.fromList(data));
    return utf8.decode(out);
  }

  // ═══════════════════════════════════════════
  // 🔹 RSA ENCRYPTION (PKCS1, 2048-bit)
  // ═══════════════════════════════════════════

  static String _encryptRSA(String plainText, String publicKeyStr) {
    try {
      final publicKey = _decodeRSAPublicKey(publicKeyStr);
      final cipher = PKCS1Encoding(RSAEngine());
      cipher.init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

      final inputBytes = Uint8List.fromList(utf8.encode(plainText));

      if (inputBytes.length > 245) {
        final aesKey = generateAESKey();
        final aesEncrypted = _encryptAES(plainText, aesKey);
        final aesKeyBytes = Uint8List.fromList(utf8.encode(aesKey));
        final encryptedKey = cipher.process(aesKeyBytes);
        return "RSA_HYBRID:${base64.encode(encryptedKey)}:$aesEncrypted";
      }

      final encrypted = cipher.process(inputBytes);
      return "RSA_DIRECT:${base64.encode(encrypted)}";
    } catch (e) {
      throw Exception("RSA encrypt error: $e");
    }
  }

  static String _decryptRSA(String encryptedText, String privateKeyStr) {
    try {
      final privateKey = _decodeRSAPrivateKey(privateKeyStr);
      final cipher = PKCS1Encoding(RSAEngine());
      cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

      if (encryptedText.startsWith("RSA_HYBRID:")) {
        final parts = encryptedText.split(":");
        if (parts.length < 4) return "[Invalid RSA Hybrid format]";

        final encryptedKeyBytes = base64.decode(parts[1]);
        final aesKeyBytes =
            cipher.process(Uint8List.fromList(encryptedKeyBytes));
        final aesKey = utf8.decode(aesKeyBytes);
        final aesEncrypted = parts.sublist(2).join(":");
        return _decryptAES(aesEncrypted, aesKey);
      } else if (encryptedText.startsWith("RSA_DIRECT:")) {
        final encryptedData = encryptedText.substring("RSA_DIRECT:".length);
        final inputBytes = base64.decode(encryptedData);
        final decrypted = cipher.process(Uint8List.fromList(inputBytes));
        return utf8.decode(decrypted);
      }

      return "[Invalid RSA format]";
    } catch (e) {
      return "[RSA Decrypt Error: $e]";
    }
  }

  // ═══════════════════════════════════════════
  // 🔹 ChaCha20 ENCRYPTION (256-bit)
  // ═══════════════════════════════════════════

  static String _encryptChaCha20(String plainText, String keyBase64) {
    final keyBytes = _safeDecodeKey(keyBase64);

    final random = Random.secure();
    final nonceBytes = List<int>.generate(12, (_) => random.nextInt(256));

    final params = ParametersWithIV(
      KeyParameter(keyBytes),
      Uint8List.fromList(nonceBytes),
    );

    final cipher = ChaCha7539Engine();
    cipher.init(true, params);

    final inputBytes = Uint8List.fromList(utf8.encode(plainText));
    final outputBytes = Uint8List(inputBytes.length);
    cipher.processBytes(inputBytes, 0, inputBytes.length, outputBytes, 0);

    final nonceEncoded = base64Url.encode(nonceBytes);
    final dataEncoded = base64Url.encode(outputBytes);
    return "$nonceEncoded:$dataEncoded";
  }

  static String _decryptChaCha20(String encryptedText, String keyBase64) {
    final parts = encryptedText.split(":");
    if (parts.length < 2) return "[Invalid ChaCha20 format]";

    final keyBytes = _safeDecodeKey(keyBase64);

    Uint8List nonceBytes;
    Uint8List encryptedBytes;
    try {
      nonceBytes = _decodeBase64UrlLenient(parts[0]);
      encryptedBytes = _decodeBase64UrlLenient(parts[1]);
    } catch (_) {
      nonceBytes = _decodeBase64Lenient(parts[0]);
      encryptedBytes = _decodeBase64Lenient(parts[1]);
    }

    final params = ParametersWithIV(
      KeyParameter(keyBytes),
      nonceBytes,
    );

    final cipher = ChaCha7539Engine();
    cipher.init(false, params);

    final outputBytes = Uint8List(encryptedBytes.length);
    cipher.processBytes(
        encryptedBytes, 0, encryptedBytes.length, outputBytes, 0);

    return utf8.decode(outputBytes);
  }

  // ═══════════════════════════════════════════
  // 🔑 RSA KEY ENCODE / DECODE
  // ═══════════════════════════════════════════

  static String _encodeRSAPublicKey(RSAPublicKey key) {
    final data = {
      'modulus': key.modulus.toString(),
      'exponent': key.exponent.toString(),
    };
    return base64Url.encode(utf8.encode(jsonEncode(data)));
  }

  static String _encodeRSAPrivateKey(RSAPrivateKey key) {
    final data = {
      'modulus': key.modulus.toString(),
      'privateExponent': key.privateExponent.toString(),
      'p': key.p.toString(),
      'q': key.q.toString(),
    };
    return base64Url.encode(utf8.encode(jsonEncode(data)));
  }

  static RSAPublicKey _decodeRSAPublicKey(String encoded) {
    try {
      String decoded;
      try {
        decoded = utf8.decode(_decodeBase64UrlLenient(encoded));
      } catch (_) {
        decoded = utf8.decode(_decodeBase64Lenient(encoded));
      }
      final data = jsonDecode(decoded);
      return RSAPublicKey(
        BigInt.parse(data['modulus']),
        BigInt.parse(data['exponent']),
      );
    } catch (e) {
      throw Exception("RSA public key decode error: $e");
    }
  }

  static RSAPrivateKey _decodeRSAPrivateKey(String encoded) {
    try {
      String decoded;
      try {
        decoded = utf8.decode(_decodeBase64UrlLenient(encoded));
      } catch (_) {
        decoded = utf8.decode(_decodeBase64Lenient(encoded));
      }
      final data = jsonDecode(decoded);
      return RSAPrivateKey(
        BigInt.parse(data['modulus']),
        BigInt.parse(data['privateExponent']),
        BigInt.parse(data['p']),
        BigInt.parse(data['q']),
      );
    } catch (e) {
      throw Exception("RSA private key decode error: $e");
    }
  }

  // ═══════════════════════════════════════════
  // 🔄 ALGORITHM CONVERTER
  // ═══════════════════════════════════════════

  static EncryptionAlgorithm algorithmFromString(String algo) {
    switch (algo.toUpperCase()) {
      case 'AESGCM':
      case 'AES-GCM':
        return EncryptionAlgorithm.AESGCM;
      case 'RSA':
        return EncryptionAlgorithm.RSA;
      case 'CHACHA20':
        return EncryptionAlgorithm.ChaCha20;
      case 'ECDSA':
      case 'ECDSA_P256':
      case 'ECC':
        return EncryptionAlgorithm.ECDSA_P256;
      default:
        return EncryptionAlgorithm.AES;
    }
  }

  static String algorithmToString(EncryptionAlgorithm algo) {
    switch (algo) {
      case EncryptionAlgorithm.AESGCM:
        return 'AESGCM';
      case EncryptionAlgorithm.RSA:
        return 'RSA';
      case EncryptionAlgorithm.ChaCha20:
        return 'ChaCha20';
      case EncryptionAlgorithm.ECDSA_P256:
        return 'ECDSA_P256';
      default:
        return 'AES';
    }
  }
}