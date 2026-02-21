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

## Generating Protobuf Files

The `lib/src/protos/` directory contains Dart files generated from Hyperledger Fabric `.proto` definitions.
These are **not committed** to the repo and must be generated before building.

### Prerequisites

1. **`protoc`** — Protocol Buffers compiler:
   ```sh
   brew install protobuf   # macOS
   ```

2. **`protoc-gen-dart`** — Dart plugin for protoc (requires `protoc_plugin ^25.0.0`, which targets `protobuf ^6.0.0`):
   ```sh
   dart pub global activate protoc_plugin
   ```
   Add the pub-cache bin to your PATH (add to `~/.zshrc` or `~/.bashrc`):
   ```sh
   export PATH="$PATH:$HOME/.pub-cache/bin"
   ```

3. **`fabric-protos`** — Hyperledger Fabric `.proto` source files, cloned at `~/github/fabric-protos`:
   ```sh
   git clone https://github.com/hyperledger/fabric-protos ~/github/fabric-protos
   ```
   The script defaults to that path; pass a custom path as the first argument if needed.

### Running the generator

```sh
./tool/gen_protos.sh
# or with a custom fabric-protos path:
./tool/gen_protos.sh /path/to/fabric-protos
```

> **Note:** `protoc-gen-dart` must be on your `PATH` when running the script. If you get
> `protoc-gen-dart: program not found`, prepend the pub-cache bin:
> `PATH="$PATH:$HOME/.pub-cache/bin" ./tool/gen_protos.sh`

### Version compatibility

| Package | Required version |
|---------|-----------------|
| `protobuf` | `^6.0.0` |
| `grpc` | `^5.1.0` |
| `protoc_plugin` | `^25.0.0` |

`protoc_plugin 25.0.0` generates well-known type imports from `package:protobuf/well_known_types/…`
which requires `protobuf 6.0.0+`. Do **not** use an older `protoc_plugin` with this project.

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
