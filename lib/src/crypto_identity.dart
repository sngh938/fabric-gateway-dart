import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart' as asn1;

import 'protos/msp/identities.pb.dart' as $msp;
import 'types.dart' as fabric_types;

/// X.509 Identity implementation for Fabric
class X509Identity {
  final String _mspId;
  final Uint8List _certificate;

  X509Identity._(this._mspId, this._certificate);

  String get mspId => _mspId;
  Uint8List get certificate => _certificate;

  /// Create an X509Identity from MSP ID and PEM-encoded certificate
  static X509Identity fromPEM(String mspId, Uint8List certificatePEM) {
    // For now, store the certificate bytes directly
    // TODO: Parse the actual X.509 certificate if needed for validation
    return X509Identity._(mspId, certificatePEM);
  }

  /// Get the serialized identity for Fabric (protobuf SerializedIdentity)
  Uint8List getSerializedIdentity() {
    final serializedIdentity = $msp.SerializedIdentity()
      ..mspid = _mspId
      ..idBytes = _certificate;
    
    final serializedBytes = serializedIdentity.writeToBuffer();
    print('DEBUG: SerializedIdentity - MSP ID: $_mspId');
    print('DEBUG: SerializedIdentity - Certificate size: ${_certificate.length}');
    print('DEBUG: SerializedIdentity - Total serialized size: ${serializedBytes.length}');
    print('DEBUG: SerializedIdentity - Certificate starts with: ${String.fromCharCodes(_certificate.take(30))}');
    
    return Uint8List.fromList(serializedBytes);
  }
}

/// ECDSA private key signer implementation
class ECDSAPrivateKeySigner {
  final ECPrivateKey _privateKey;

  ECDSAPrivateKeySigner._(this._privateKey);

  /// Create an ECDSA signer from PEM-encoded private key
  static ECDSAPrivateKeySigner fromPEM(Uint8List privateKeyPEM) {
    // Parse PEM format
    final pemString = utf8.decode(privateKeyPEM);
    final lines = pemString.split('\n');
    
    // Find the base64 content between BEGIN and END lines
    final beginIndex = lines.indexWhere((line) => line.contains('BEGIN'));
    final endIndex = lines.indexWhere((line) => line.contains('END'));
    
    if (beginIndex == -1 || endIndex == -1 || beginIndex >= endIndex) {
      throw ArgumentError('Invalid PEM format');
    }
    
    // Extract base64 content
    final base64Content = lines
        .sublist(beginIndex + 1, endIndex)
        .join('')
        .replaceAll(RegExp(r'\s'), '');
    
    final keyBytes = base64.decode(base64Content);
    
    // Parse PKCS#8 private key
    final asn1Parser = asn1.ASN1Parser(keyBytes);
    final topLevelSeq = asn1Parser.nextObject() as asn1.ASN1Sequence;
    
    // PKCS#8 structure: SEQUENCE { version, algorithm, privateKey }
    if (topLevelSeq.elements.length < 3) {
      throw ArgumentError('Invalid PKCS#8 structure');
    }
    
    // Extract the private key bytes (OCTET STRING)
    final privateKeyOctetString = topLevelSeq.elements[2] as asn1.ASN1OctetString;
    final privateKeyBytes = privateKeyOctetString.octets;
    
    // Parse the EC private key from the OCTET STRING
    final privateKeyParser = asn1.ASN1Parser(privateKeyBytes);
    final privateKeySeq = privateKeyParser.nextObject() as asn1.ASN1Sequence;
    
    // EC private key structure: SEQUENCE { version, privateKey, ... }
    final privateKeyValue = (privateKeySeq.elements[1] as asn1.ASN1OctetString).octets;
    
    // Create EC private key (using secp256r1/P-256 curve)
    final ecDomainParams = ECDomainParameters('secp256r1');
    final d = _bytesToBigInt(privateKeyValue);
    
    final privateKey = ECPrivateKey(d, ecDomainParams);
    
    return ECDSAPrivateKeySigner._(privateKey);
  }

  /// Sign a message digest using ECDSA
  Future<Uint8List> sign(Uint8List digest) async {
    try {
      // Create ECDSA signer
      final signer = ECDSASigner(SHA256Digest());
      final random = SecureRandom('Fortuna')..seed(KeyParameter(_generateRandomSeed()));
      
      signer.init(true, ParametersWithRandom(PrivateKeyParameter(_privateKey), random));
      
      // Sign the digest
      final signature = signer.generateSignature(digest) as ECSignature;
      
      // Canonicalize the S value (must be in lower half of curve order)
      final canonicalS = _canonicalizeS(signature.s, _privateKey.parameters!.n);
      
      // Encode as ASN.1 DER
      return _encodeECDSASignatureASN1(signature.r, canonicalS);
    } catch (e) {
      throw Exception('Failed to sign: $e');
    }
  }

  /// Generate random seed for secure random number generator
  Uint8List _generateRandomSeed() {
    final seed = Uint8List(32);
    final random = Random.secure();
    for (int i = 0; i < seed.length; i++) {
      seed[i] = random.nextInt(256);
    }
    return seed;
  }

  /// Convert byte array to BigInt
  static BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) + BigInt.from(bytes[i]);
    }
    return result;
  }

  /// Canonicalize ECDSA S value to lower half of curve order
  BigInt _canonicalizeS(BigInt s, BigInt n) {
    final halfOrder = n >> 1; // n / 2
    if (s.compareTo(halfOrder) <= 0) {
      return s;
    }
    // Return n - s to put it in lower half
    return n - s;
  }

  /// Encode ECDSA signature as ASN.1 DER format
  Uint8List _encodeECDSASignatureASN1(BigInt r, BigInt s) {
    final rBytes = _bigIntToBytes(r);
    final sBytes = _bigIntToBytes(s);
    
    final rInteger = asn1.ASN1Integer(r);
    final sInteger = asn1.ASN1Integer(s);
    
    final sequence = asn1.ASN1Sequence()..add(rInteger)..add(sInteger);
    
    return sequence.encodedBytes;
  }

  /// Convert BigInt to byte array
  Uint8List _bigIntToBytes(BigInt bigInt) {
    final hex = bigInt.toRadixString(16);
    final paddedHex = hex.length % 2 == 0 ? hex : '0$hex';
    
    final bytes = <int>[];
    for (int i = 0; i < paddedHex.length; i += 2) {
      bytes.add(int.parse(paddedHex.substring(i, i + 2), radix: 16));
    }
    
    return Uint8List.fromList(bytes);
  }
}

/// Create a proper signer function from ECDSA private key
fabric_types.Signer createECDSASigner(Uint8List privateKeyPEM) {
  final ecdsaSigner = ECDSAPrivateKeySigner.fromPEM(privateKeyPEM);
  
  return (List<int> message) async {
    // ECDSASigner(SHA256Digest()) will hash the message internally
    // So pass the raw message bytes, not a pre-computed hash
    final signature = await ecdsaSigner.sign(Uint8List.fromList(message));
    return signature.toList();
  };
}

/// Generate transaction ID from nonce and creator identity
String generateTransactionID(Uint8List creator) {
  // Generate 24-byte nonce
  final random = Random.secure();
  final nonce = Uint8List(24);
  for (int i = 0; i < nonce.length; i++) {
    nonce[i] = random.nextInt(256);
  }
  
  // Combine nonce + creator and hash with SHA-256
  final combined = <int>[...nonce, ...creator];
  final digest = sha256.convert(combined);
  
  // Return hex-encoded transaction ID
  return digest.toString();
}

