# Fabric Gateway Dart

A Dart implementation of Hyperledger Fabric Gateway client library.

## Features

- Complete Hyperledger Fabric Gateway API implementation
- ECDSA cryptographic signing with proper canonicalization
- X.509 identity management
- Protobuf-based communication with Fabric peers
- Support for proposal evaluation and transaction submission

## Usage

Add to your pubspec.yaml:
```yaml
dependencies:
  fabric_gateway:
    path: ../fabric-gateway-dart
```

## Example

```dart
import 'package:fabric_gateway/fabric_gateway.dart';

// Create gateway connection
final gateway = await Gateway.newGateway(
  mspId: 'Org1MSP',
  peerEndpoint: 'localhost:7051',
  tlsRootCert: tlsCertBytes,
  clientCert: clientCertBytes,
  clientKey: clientKeyBytes,
  peerHostAlias: 'peer0.org1.example.com',
);

// Evaluate transaction
final result = await gateway.evaluateTransaction(
  channelName: 'mychannel',
  chaincodeName: 'mychaincode',
  transactionName: 'GetAsset',
  args: ['asset1'],
);
```
