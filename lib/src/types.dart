typedef Signer = Future<List<int>> Function(List<int> message);

typedef IdentityBytes = List<int>;

/// SignerAdapter provides an ergonomic way to supply both identity bytes and
/// a signing implementation. Implementations may fetch identities from
/// secure stores or hardware modules.
abstract class SignerAdapter {
  /// Return the marshaled identity bytes (e.g. MSP SerializedIdentity).
  Future<List<int>> identity();

  /// Sign the provided message bytes and return the signature bytes.
  Future<List<int>> sign(List<int> message);
}

/// A simple adapter implementation backed by static identity bytes and a
/// `Signer` function.
class SimpleSignerAdapter implements SignerAdapter {
  final List<int> _identity;
  final Signer _signer;

  SimpleSignerAdapter(this._identity, this._signer);

  @override
  Future<List<int>> identity() async => _identity;

  @override
  Future<List<int>> sign(List<int> message) => _signer(message);
}
