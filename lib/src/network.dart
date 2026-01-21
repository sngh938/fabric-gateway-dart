import 'contract.dart';
import 'gateway_client.dart';
import 'types.dart';

/// Represents a Fabric channel (network)
class Network {
  final String name;
  final GatewayClient _client;
  final List<int>? _identity;
  final Signer? _signer;

  Network(this.name, this._client, [this._identity, this._signer]);

  /// Obtain a contract for a chaincode
  Contract getContract(String chaincodeName, [String? contractName]) {
    return Contract.internal(chaincodeName, contractName, _client, name,
        identity: _identity, signer: _signer);
  }

  /// Stream of chaincode events - use Stream in Dart instead of iterator
  // Stream<ChaincodeEvent> chaincodeEvents(String chaincodeName) => ...
}
