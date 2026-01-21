import 'dart:typed_data';

/// Abstract identity representation
abstract class Identity {
  /// Serialized identity bytes (e.g., SerializedIdentity proto bytes)
  Uint8List getSerializedIdentity();
}

/// Signer interface to sign digests
abstract class Signer {
  /// Sign a digest and return signature bytes
  Future<Uint8List> sign(Uint8List digest);
}

/// SigningIdentity pairs an Identity with a Signer and hash function
class SigningIdentity {
  final Identity identity;
  final Signer signer;

  SigningIdentity(this.identity, this.signer);

  Future<Uint8List> signDigest(Uint8List digest) async => signer.sign(digest);
}
