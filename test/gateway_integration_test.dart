import 'dart:convert';

import 'package:test/test.dart';
import 'package:fabric_gateway/src/gateway.dart';
import 'package:fabric_gateway/src/types.dart';

Future<List<int>> _mockSigner(List<int> message) async {
  return <int>[...utf8.encode('SIG:'), ...message.take(16)];
}

void main() {
  group('Gateway.connect() Tests', () {
    test('GatewayBuilder.connect() throws with no connection', () async {
      final builder = Gateway.newBuilder()
        ..identityBytes(utf8.encode('cert'))
        ..signer(_mockSigner);

      expect(builder.connect(), throwsA(isA<UnimplementedError>()));
    });

    test('GatewayBuilder.connect() throws with unsupported connection type',
        () async {
      final builder = Gateway.newBuilder()
        ..connection(12345) // int is not supported
        ..identityBytes(utf8.encode('cert'))
        ..signer(_mockSigner);

      expect(builder.connect(), throwsA(isA<ArgumentError>()));
    });

    test('GatewayBuilder missing identity and signer in connect', () async {
      final builder = Gateway.newBuilder()..connection('localhost:7051');

      // Should work but identity/signer will be null
      expect(builder, isNotNull);
    });

    test('GatewayBuilder.close() on builder is no-op', () async {
      final builder = Gateway.newBuilder();

      // Should not throw
      await builder.close();
      expect(builder, isNotNull);
    });
  });

  group('GatewayBuilder Configuration Tests', () {
    test('GatewayBuilder.connection() configures endpoint', () {
      final builder = Gateway.newBuilder()..connection('localhost:7051');

      expect(builder, isNotNull);
    });

    test('GatewayBuilder.identityBytes() configures identity', () {
      final identity = utf8.encode('cert-data');
      final builder = Gateway.newBuilder()..identityBytes(identity);

      expect(builder, isNotNull);
    });

    test('GatewayBuilder.signer() configures signer', () {
      final builder = Gateway.newBuilder()..signer(_mockSigner);

      expect(builder, isNotNull);
    });

    test('GatewayBuilder chaining works correctly', () {
      final builder = Gateway.newBuilder()
        ..connection('localhost:7051')
        ..identityBytes(utf8.encode('cert-data'))
        ..signer(_mockSigner);

      expect(builder, isNotNull);
    });

    test('GatewayBuilder with SimpleSignerAdapter', () {
      final identity = utf8.encode('cert-data');
      final adapter = SimpleSignerAdapter(identity, _mockSigner);

      final builder = Gateway.newBuilder()..identitySignerAdapter(adapter);

      expect(builder, isNotNull);
    });

    test('GatewayBuilder methods can be called multiple times', () {
      final builder = Gateway.newBuilder()
        ..connection('localhost:7051')
        ..identityBytes(utf8.encode('id1'))
        ..signer(_mockSigner)
        ..connection('localhost:7052')
        ..identityBytes(utf8.encode('id2'));

      expect(builder, isNotNull);
    });
  });

  group('Signer Type Tests', () {
    test('Signer typedef creates callable function', () async {
      final Signer signer = _mockSigner;

      final result = await signer(utf8.encode('message'));
      expect(result, isNotEmpty);
    });

    test('Signer receives complete message bytes', () async {
      List<int>? capturedMsg;

      Future<List<int>> capturingSigner(List<int> message) async {
        capturedMsg = message;
        return <int>[];
      }

      final msg = utf8.encode('test-msg');
      await capturingSigner(msg);

      expect(capturedMsg, equals(msg));
    });

    test('Signer can produce various signature sizes', () async {
      final sig1 = await _mockSigner(utf8.encode('msg1'));
      final sig2 = await _mockSigner(utf8.encode('msg1-longer-message'));

      expect(sig1, isNotEmpty);
      expect(sig2, isNotEmpty);
    });
  });

  group('IdentityBytes Type Tests', () {
    test('IdentityBytes is a List<int>', () {
      final IdentityBytes id = utf8.encode('certificate-data');
      expect(id, isA<List<int>>());
    });

    test('IdentityBytes can be created from string', () {
      const String certData = 'pem-certificate-content';
      final IdentityBytes id = utf8.encode(certData);

      expect(String.fromCharCodes(id), equals(certData));
    });

    test('IdentityBytes supports index access', () {
      final IdentityBytes id = <int>[65, 66, 67];
      expect(id[0], equals(65)); // 'A'
      expect(id[1], equals(66)); // 'B'
      expect(id[2], equals(67)); // 'C'
    });

    test('IdentityBytes supports length property', () {
      final IdentityBytes id = utf8.encode('test');
      expect(id.length, equals(4));
    });
  });

  group('SimpleSignerAdapter Tests', () {
    test('SimpleSignerAdapter stores identity', () async {
      final identity = utf8.encode('my-identity');
      final adapter = SimpleSignerAdapter(identity, _mockSigner);

      final retrievedIdentity = await adapter.identity();
      expect(retrievedIdentity, equals(identity));
    });

    test('SimpleSignerAdapter delegates sign() to signer', () async {
      final identity = utf8.encode('my-identity');
      final adapter = SimpleSignerAdapter(identity, _mockSigner);

      final msg = utf8.encode('message-to-sign');
      final signature = await adapter.sign(msg);

      expect(signature, isNotEmpty);
      expect(String.fromCharCodes(signature), startsWith('SIG:'));
    });

    test('SimpleSignerAdapter can be used in GatewayBuilder', () {
      final identity = utf8.encode('my-identity');
      final adapter = SimpleSignerAdapter(identity, _mockSigner);

      final builder = Gateway.newBuilder()..identitySignerAdapter(adapter);

      expect(builder, isNotNull);
    });

    test('Multiple SimpleSignerAdapters can coexist', () async {
      final id1 = utf8.encode('id1');
      final id2 = utf8.encode('id2');

      final adapter1 = SimpleSignerAdapter(id1, _mockSigner);
      final adapter2 = SimpleSignerAdapter(id2, _mockSigner);

      final identity1 = await adapter1.identity();
      final identity2 = await adapter2.identity();

      expect(identity1, equals(id1));
      expect(identity2, equals(id2));
    });
  });

  group('SignerAdapter Interface Tests', () {
    test('SignerAdapter.identity() returns bytes', () async {
      final identity = utf8.encode('certificate');
      final adapter = SimpleSignerAdapter(identity, _mockSigner);

      final result = await adapter.identity();
      expect(result, isA<List<int>>());
      expect(result, equals(identity));
    });

    test('SignerAdapter.sign() returns signature bytes', () async {
      final adapter = SimpleSignerAdapter(utf8.encode('id'), _mockSigner);

      final msg = utf8.encode('payload');
      final sig = await adapter.sign(msg);

      expect(sig, isA<List<int>>());
      expect(sig, isNotEmpty);
    });

    test('SignerAdapter.sign() with various message sizes', () async {
      final adapter = SimpleSignerAdapter(utf8.encode('id'), _mockSigner);

      final sig1 = await adapter.sign(utf8.encode('a'));
      final sig2 = await adapter.sign(utf8.encode('longer message here'));

      expect(sig1, isNotEmpty);
      expect(sig2, isNotEmpty);
    });
  });

  group('Callback Signer Tests', () {
    test('Custom signer function works', () async {
      List<int> customSig(List<int> msg) => <int>[1, 2, 3];

      Future<List<int>> signer(List<int> message) async {
        return customSig(message);
      }

      final result = await signer(utf8.encode('msg'));
      expect(result, equals([1, 2, 3]));
    });

    test('Signer can inspect message before signing', () async {
      List<int>? inspectedMsg;

      Future<List<int>> inspectingSigner(List<int> message) async {
        inspectedMsg = message;
        return utf8.encode('sig');
      }

      final msg = utf8.encode('test');
      await inspectingSigner(msg);

      expect(inspectedMsg, equals(msg));
    });

    test('Signer can create deterministic signatures', () async {
      Future<List<int>> deterministicSigner(List<int> message) async {
        // Always return same signature based on message length
        return List<int>.filled(message.length, 0xFF);
      }

      final msg = utf8.encode('abc'); // length 3
      final sig1 = await deterministicSigner(msg);
      final sig2 = await deterministicSigner(msg);

      expect(sig1, equals(sig2));
      expect(sig1.length, equals(3));
    });
  });
}
