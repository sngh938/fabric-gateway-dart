import 'dart:typed_data';
import 'package:grpc/grpc.dart' as $grpc;

import 'gateway_client.dart';
import 'network.dart';
import 'types.dart';
import 'crypto_identity.dart';

/// Gateway is the main entry point for the SDK.
class Gateway {
  final GatewayClient _client;
  final List<int>? _identity;
  final Signer? _signer;

  Gateway._(this._client, [this._identity, this._signer]);

  /// Create a new builder for a Gateway.
  static GatewayBuilder newBuilder() => GatewayBuilder._();

  /// Convenience method to create a Gateway directly with TLS credentials
  static Future<Gateway> newGateway({
    required String mspId,
    required String peerEndpoint,
    required Uint8List tlsRootCert,
    required Uint8List clientCert,
    required Uint8List clientKey,
    required String peerHostAlias,
  }) async {
    // Create TLS credentials
    final $grpc.ClientChannel channel = $grpc.ClientChannel(
      peerEndpoint.split(':')[0],
      port: int.parse(peerEndpoint.split(':')[1]),
      options: $grpc.ChannelOptions(
        credentials: $grpc.ChannelCredentials.secure(
          certificates: tlsRootCert,
          authority: peerHostAlias,
        ),
      ),
    );

    // Create proper X.509 identity
    final identity = X509Identity.fromPEM(mspId, clientCert);
    final identityBytes = identity.getSerializedIdentity();
    
    // Create proper ECDSA signer
    final signer = createECDSASigner(clientKey);

    final GatewayClient client = GatewayClient(channel);
    return Gateway._(client, identityBytes, signer);
  }

  /// Convenience method to evaluate a transaction directly
  Future<Uint8List> evaluateTransaction({
    required String channelName,
    required String chaincodeName,
    required String transactionName,
    List<String>? args,
  }) async {
    final network = getNetwork(channelName);
    final contract = network.getContract(chaincodeName);
    return await contract.evaluateTransaction(transactionName, args);
  }

  /// Convenience method to submit a transaction directly
  Future<Uint8List> submitTransaction({
    required String channelName,
    required String chaincodeName,
    required String transactionName,
    List<String>? args,
  }) async {
    final network = getNetwork(channelName);
    final contract = network.getContract(chaincodeName);
    return await contract.submitTransaction(transactionName, args);
  }

  /// Close the gateway and underlying resources.
  Future<void> close() async {
    await _client.close();
  }
}

class GatewayBuilder {
  GatewayBuilder._();

  Object? _connection;
  List<int>? _identityBytes;
  Signer? _signer;
  SignerAdapter? _adapter;

  /// Configure connection. Accepts either a `String` host:port or a
  /// `ClientChannel` instance.
  GatewayBuilder connection(Object connection) {
    _connection = connection;
    return this;
  }

  /// Configure identity bytes directly.
  GatewayBuilder identityBytes(List<int> identity) {
    _identityBytes = identity;
    return this;
  }

  /// Configure a signer function.
  GatewayBuilder signer(Signer signer) {
    _signer = signer;
    return this;
  }

  /// Configure a `SignerAdapter` which supplies both identity bytes and the
  /// signing function. This is the recommended ergonomic API for real
  /// applications (it can wrap HSMs, KMS adapters, or in-memory keys).
  GatewayBuilder identitySignerAdapter(SignerAdapter adapter) {
    _adapter = adapter;
    return this;
  }

  /// Build and connect the Gateway.
  Future<Gateway> connect() async {
    $grpc.ClientChannel channel;

    if (_connection is $grpc.ClientChannel) {
      channel = _connection as $grpc.ClientChannel;
    } else if (_connection is String) {
      final List<String> parts = (_connection as String).split(':');
      final String host = parts[0];
      final int port = parts.length > 1 ? int.parse(parts[1]) : 443;
      channel = $grpc.ClientChannel(host,
          port: port,
          options: $grpc.ChannelOptions(
              credentials: $grpc.ChannelCredentials.insecure()));
    } else if (_connection == null) {
      // Preserve previous behavior expected by tests: if no connection was
      // configured, surface an UnimplementedError so tests can detect an
      // uninitialized builder.
      throw UnimplementedError('Connection not configured');
    } else {
      throw ArgumentError(
          'Unsupported connection type: ${_connection.runtimeType}');
    }
    final GatewayClient client = GatewayClient(channel);

    // Resolve identity + signer from adapter if provided.
    List<int>? identityBytes;
    Signer? signerFn = _signer;
    if (_adapter != null) {
      identityBytes = await _adapter!.identity();
      signerFn = _adapter!.sign;
    } else {
      identityBytes = _identityBytes;
    }

    return Gateway._(client, identityBytes, signerFn);
  }

  /// Close resources associated with this builder (no-op).
  Future<void> close() async {}
}

extension GatewayExtensions on Gateway {
  /// Get a `Network` by channel name
  Network getNetwork(String name) => Network(name, _client, _identity, _signer);
}

