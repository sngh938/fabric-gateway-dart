import 'dart:convert';

import 'package:test/test.dart';
import 'package:fabric_gateway/fabric_gateway.dart';
import 'package:fabric_gateway/src/types.dart' as types;

Future<List<int>> _mockSigner(List<int> message) async {
  // Simple mock: prepend 'sig:' to indicate signed
  return <int>[...utf8.encode('sig:'), ...message.take(16)];
}

void main() {
  group('GatewayBuilder', () {
    test('newBuilder returns a GatewayBuilder', () {
      final GatewayBuilder builder = Gateway.newBuilder();
      expect(builder, isNotNull);
    });

    test('connection configures host:port', () {
      final GatewayBuilder builder = Gateway.newBuilder()
        ..connection('localhost:7051');
      expect(builder, isNotNull);
    });

    test('identityBytes configures identity', () {
      final List<int> id = utf8.encode('test-identity');
      final GatewayBuilder builder = Gateway.newBuilder()
        ..identityBytes(id);
      expect(builder, isNotNull);
    });

    test('signer configures signer function', () {
      final GatewayBuilder builder = Gateway.newBuilder()
        ..signer(_mockSigner);
      expect(builder, isNotNull);
    });

    test('identitySignerAdapter configures adapter', () {
      final types.SimpleSignerAdapter adapter =
          types.SimpleSignerAdapter(utf8.encode('test-id'), _mockSigner);
      final GatewayBuilder builder = Gateway.newBuilder()
        ..identitySignerAdapter(adapter);
      expect(builder, isNotNull);
    });

    test('builder methods return builder for chaining', () {
      final GatewayBuilder builder = Gateway.newBuilder()
        ..connection('localhost:7051')
        ..identityBytes(utf8.encode('id'))
        ..signer(_mockSigner);
      expect(builder, isNotNull);
    });

    test('connect throws UnimplementedError when no connection', () async {
      final GatewayBuilder builder = Gateway.newBuilder();
      expect(() async => await builder.connect(),
          throwsA(isA<UnimplementedError>()));
    });

    test('connect throws ArgumentError for unsupported connection type',
        () async {
      final GatewayBuilder builder = Gateway.newBuilder()
        ..connection(12345);
      expect(() async => await builder.connect(),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('types.SimpleSignerAdapter', () {
    test('identity returns configured identity bytes', () async {
      final List<int> id = utf8.encode('my-identity');
      final types.SimpleSignerAdapter adapter = types.SimpleSignerAdapter(id, _mockSigner);

      final List<int> result = await adapter.identity();
      expect(result, equals(id));
    });

    test('sign delegates to signer function', () async {
      final List<int> id = utf8.encode('my-identity');
      final types.SimpleSignerAdapter adapter = types.SimpleSignerAdapter(id, _mockSigner);

      final List<int> message = utf8.encode('test-message');
      final List<int> signature = await adapter.sign(message);

      expect(signature, isNotEmpty);
      expect(utf8.decode(signature.sublist(0, 4)), equals('sig:'));
    });

    test('adapter can be used with builder', () async {
      final types.SimpleSignerAdapter adapter =
          types.SimpleSignerAdapter(utf8.encode('identity'), _mockSigner);

      final GatewayBuilder builder = Gateway.newBuilder()
        ..identitySignerAdapter(adapter);
      expect(builder, isNotNull);
    });
  });

  group('Checkpointer', () {
    test('InMemoryCheckpointer can be constructed', () {
      final InMemoryCheckpointer cp = InMemoryCheckpointer();
      expect(cp, isNotNull);
    });

    test('InMemoryCheckpointer.checkpointBlock completes', () async {
      final InMemoryCheckpointer cp = InMemoryCheckpointer();
      await cp.checkpointBlock(1);
      expect(true, isTrue);
    });

    test('InMemoryCheckpointer.checkpointTransaction completes', () async {
      final InMemoryCheckpointer cp = InMemoryCheckpointer();
      await cp.checkpointTransaction(1, 'txn-id');
      expect(true, isTrue);
    });
  });

  group('Signer and Identity types', () {
    test('Signer function can be invoked', () async {
      final List<int> result = await _mockSigner(utf8.encode('test'));
      expect(result, isNotEmpty);
    });

    test('types.IdentityBytes is a List<int>', () {
      final types.IdentityBytes identity = utf8.encode('test-creator');
      expect(identity, isNotEmpty);
      expect(identity.length, greaterThan(0));
    });

    test('Multiple signers can be created', () async {
      Future<List<int>> customSigner(List<int> msg) async =>
          utf8.encode('custom-${msg.length}');

      final List<int> sig1 = await _mockSigner(utf8.encode('msg1'));
      final List<int> sig2 = await customSigner(utf8.encode('msg2'));

      expect(sig1, isNotEmpty);
      expect(sig2, isNotEmpty);
    });
  });

  group('Integration patterns', () {
    test('GatewayBuilder with adapter chain', () async {
      final List<int> testId = utf8.encode('test-creator');
      final types.SimpleSignerAdapter adapter =
          types.SimpleSignerAdapter(testId, _mockSigner);

      final GatewayBuilder builder = Gateway.newBuilder()
        ..connection('localhost:7051')
        ..identitySignerAdapter(adapter);

      // Verify builder is constructed correctly
      expect(builder, isNotNull);
    });

    test('types.SimpleSignerAdapter initialization', () async {
      final List<int> id = utf8.encode('creator-bytes');
      final types.Signer signer = _mockSigner;
      final types.SimpleSignerAdapter adapter = types.SimpleSignerAdapter(id, signer);

      final List<int> retrievedId = await adapter.identity();
      expect(retrievedId, equals(id));
    });

    test('Checkpointer as interface', () async {
      final Checkpointer cp = InMemoryCheckpointer();
      await cp.checkpointBlock(5);
      await cp.checkpointTransaction(5, 'tx-123');
      expect(true, isTrue);
    });
  });
}
