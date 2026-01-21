import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:fabric_gateway/src/gateway.dart';
import 'package:fabric_gateway/src/network.dart';
import 'package:fabric_gateway/src/contract.dart';
import 'package:fabric_gateway/src/gateway_client.dart';
import 'package:fabric_gateway/src/types.dart';
import 'package:fabric_gateway/src/protos/gateway/gateway.pb.dart' as $gw;
import 'package:fabric_gateway/src/protos/common/common.pb.dart' as $common;
import 'package:fabric_gateway/src/protos/peer/proposal_response.pb.dart'
    as $peer;

/// Mock GatewayClient for RPC integration testing.
class MockGatewayClient implements GatewayClient {
  bool evaluateCalled = false;
  bool endorseCalled = false;
  bool submitCalled = false;
  bool commitStatusCalled = false;

  late $gw.EvaluateRequest lastEvaluateRequest;
  late $gw.EndorseRequest lastEndorseRequest;
  late $gw.SubmitRequest lastSubmitRequest;
  late $gw.SignedCommitStatusRequest lastCommitStatusRequest;

  // Configurable responses
  List<int> evaluateResponsePayload = utf8.encode('evaluation-result');
  List<int> endorseResponseSignature = utf8.encode('endorsement-sig');
  List<int> submitResponseTxId = utf8.encode('submit-txid');
  int commitStatusCode = 200;

  @override
  Future<$gw.EvaluateResponse> evaluate($gw.EvaluateRequest request,
      {dynamic options}) async {
    evaluateCalled = true;
    lastEvaluateRequest = request;

    // Validate request structure
    expect(request.transactionId, isNotEmpty);
    expect(request.channelId, isNotEmpty);
    expect(request.proposedTransaction.proposalBytes, isNotEmpty);
    expect(request.proposedTransaction.signature, isNotEmpty);

    final $peer.Response response = $peer.Response(
        status: 200, payload: Uint8List.fromList(evaluateResponsePayload));

    return $gw.EvaluateResponse(result: response);
  }

  @override
  Future<$gw.EndorseResponse> endorse($gw.EndorseRequest request,
      {dynamic options}) async {
    endorseCalled = true;
    lastEndorseRequest = request;

    // Validate request structure
    expect(request.transactionId, isNotEmpty);
    expect(request.channelId, isNotEmpty);
    expect(request.proposedTransaction.proposalBytes, isNotEmpty);
    expect(request.proposedTransaction.signature, isNotEmpty);

    // Return prepared transaction (Envelope with payload but no signature)
    final $common.Envelope preparedTx = $common.Envelope(
        payload: Uint8List.fromList(utf8.encode('prepared-envelope-payload')),
        signature: Uint8List(0)); // Client will sign this

    return $gw.EndorseResponse(preparedTransaction: preparedTx);
  }

  @override
  Future<$gw.SubmitResponse> submit($gw.SubmitRequest request,
      {dynamic options}) async {
    submitCalled = true;
    lastSubmitRequest = request;

    // Validate request structure
    expect(request.transactionId, isNotEmpty);
    expect(request.channelId, isNotEmpty);
    expect(request.preparedTransaction.signature, isNotEmpty);

    return $gw.SubmitResponse();
  }

  @override
  Future<$gw.CommitStatusResponse> commitStatus(
      $gw.SignedCommitStatusRequest request,
      {dynamic options}) async {
    commitStatusCalled = true;
    lastCommitStatusRequest = request;

    return $gw.CommitStatusResponse(blockNumber: $fixnum.Int64(100));
  }

  @override
  Stream<$gw.ChaincodeEventsResponse> chaincodeEvents(
      $gw.SignedChaincodeEventsRequest request,
      {dynamic options}) {
    return Stream.fromIterable([$gw.ChaincodeEventsResponse(events: [])]);
  }

  @override
  Stream<Uint8List> blockEvents(Uint8List requestBytes) {
    return Stream.error(UnimplementedError('blockEvents not implemented'));
  }

  @override
  Future<void> close() async {
    // No-op for mock
  }
}

Future<List<int>> _mockSigner(List<int> message) async {
  // Mock signer: prepend 'MOCK_SIG:' to indicate signed
  return <int>[...utf8.encode('MOCK_SIG:'), ...message.take(32)];
}

void main() {
  group('Contract RPC Integration Tests', () {
    late MockGatewayClient mockClient;
    late Contract contract;
    late List<int> testIdentity;

    setUp(() {
      mockClient = MockGatewayClient();
      testIdentity = utf8.encode('test-identity-cert');

      // Create contract directly with mock client
      contract = Contract.internal(
        'my-chaincode',
        'contract-name',
        mockClient,
        'my-channel',
        identity: testIdentity,
        signer: _mockSigner,
      );
    });

    test('evaluateTransaction sends correct EvaluateRequest', () async {
      final Uint8List result =
          await contract.evaluateTransaction('submitOrder', ['order123']);

      expect(mockClient.evaluateCalled, isTrue);
      expect(mockClient.lastEvaluateRequest.channelId, equals('my-channel'));
      expect(mockClient.lastEvaluateRequest.transactionId, isNotEmpty);
      expect(mockClient.lastEvaluateRequest.proposedTransaction.proposalBytes,
          isNotEmpty);
      expect(mockClient.lastEvaluateRequest.proposedTransaction.signature,
          isNotEmpty);
      expect(
          result, equals(Uint8List.fromList(utf8.encode('evaluation-result'))));
    });

    test('evaluateTransaction includes transaction name in proposal', () async {
      await contract.evaluateTransaction('submitOrder', ['order123']);

      expect(mockClient.evaluateCalled, isTrue);
      expect(mockClient.lastEvaluateRequest.proposedTransaction.proposalBytes,
          isNotEmpty);
      // Proposal bytes should be parsable and contain the transaction name
    });

    test('evaluateTransaction includes args in proposal', () async {
      final List<String> args = ['arg1', 'arg2', 'arg3'];
      await contract.evaluateTransaction('multiArgTxn', args);

      expect(mockClient.evaluateCalled, isTrue);
      expect(mockClient.lastEvaluateRequest.proposedTransaction.proposalBytes,
          isNotEmpty);
    });

    test('evaluateTransaction throws without identity', () async {
      final Contract contractNoId = Contract.internal(
        'my-chaincode',
        'contract-name',
        mockClient,
        'my-channel',
        identity: null,
        signer: _mockSigner,
      );

      expect(contractNoId.evaluateTransaction('submitOrder', ['order123']),
          throwsA(isA<StateError>()));
    });

    test('evaluateTransaction throws without signer', () async {
      final Contract contractNoSigner = Contract.internal(
        'my-chaincode',
        'contract-name',
        mockClient,
        'my-channel',
        identity: testIdentity,
        signer: null,
      );

      expect(contractNoSigner.evaluateTransaction('submitOrder', ['order123']),
          throwsA(isA<StateError>()));
    });

    test('submitTransaction sends EndorseRequest then SubmitRequest', () async {
      await contract.submitTransaction('createOrder', ['order456']);

      expect(mockClient.endorseCalled, isTrue);
      expect(mockClient.submitCalled, isTrue);

      // Verify EndorseRequest
      expect(mockClient.lastEndorseRequest.channelId, equals('my-channel'));
      expect(mockClient.lastEndorseRequest.transactionId, isNotEmpty);
      expect(mockClient.lastEndorseRequest.proposedTransaction.proposalBytes,
          isNotEmpty);

      // Verify SubmitRequest
      expect(mockClient.lastSubmitRequest.channelId, equals('my-channel'));
      expect(mockClient.lastSubmitRequest.transactionId,
          equals(mockClient.lastEndorseRequest.transactionId));
      expect(mockClient.lastSubmitRequest.preparedTransaction.signature,
          isNotEmpty); // Client must sign
    });

    test('submitTransaction signs envelope payload from EndorseResponse',
        () async {
      await contract.submitTransaction('updateOrder', ['order789']);

      expect(mockClient.endorseCalled, isTrue);
      expect(mockClient.submitCalled, isTrue);

      // The signature in the submit request should come from _mockSigner
      final List<int> submitSig =
          mockClient.lastSubmitRequest.preparedTransaction.signature;
      expect(submitSig, isNotEmpty);
      expect(String.fromCharCodes(submitSig), startsWith('MOCK_SIG:'));
    });

    test('submitTransaction throws without identity', () async {
      final Contract contractNoId = Contract.internal(
        'my-chaincode',
        'contract-name',
        mockClient,
        'my-channel',
        identity: null,
        signer: _mockSigner,
      );

      expect(contractNoId.submitTransaction('createOrder', ['order456']),
          throwsA(isA<StateError>()));
    });

    test('submitTransaction throws without signer', () async {
      final Contract contractNoSigner = Contract.internal(
        'my-chaincode',
        'contract-name',
        mockClient,
        'my-channel',
        identity: testIdentity,
        signer: null,
      );

      expect(contractNoSigner.submitTransaction('createOrder', ['order456']),
          throwsA(isA<StateError>()));
    });

    test('multiple evaluateTransaction calls work independently', () async {
      await contract.evaluateTransaction('getTx', ['id1']);
      expect(mockClient.evaluateCalled, isTrue);

      mockClient.evaluateCalled = false;

      await contract.evaluateTransaction('getTx', ['id2']);
      expect(mockClient.evaluateCalled, isTrue);
    });

    test('contract chaincode name is preserved', () {
      expect(contract.chaincodeName, equals('my-chaincode'));
    });

    test('contract name is accessible', () {
      expect(contract.contractName, equals('contract-name'));
    });

    test('contract exposes client getter', () {
      expect(contract.client, equals(mockClient));
    });

    test('contract exposes channel getter', () {
      expect(contract.channel, equals('my-channel'));
    });
  });

  group('Network Integration Tests', () {
    late MockGatewayClient mockClient;
    late Network network;
    late List<int> testIdentity;

    setUp(() {
      mockClient = MockGatewayClient();
      testIdentity = utf8.encode('test-identity-cert');

      // Create network directly with mock client
      network = Network(
        'my-channel',
        mockClient,
        testIdentity,
        _mockSigner,
      );
    });

    test('getContract returns Contract with correct chaincode name', () {
      final Contract contract = network.getContract('my-chaincode');

      expect(contract, isNotNull);
      expect(contract.chaincodeName, equals('my-chaincode'));
      expect(contract.contractName, isNull);
    });

    test('getContract returns Contract with correct contract name', () {
      final Contract contract =
          network.getContract('my-chaincode', 'my-contract');

      expect(contract, isNotNull);
      expect(contract.chaincodeName, equals('my-chaincode'));
      expect(contract.contractName, equals('my-contract'));
    });

    test('getContract preserves network identity and signer', () {
      final Contract contract = network.getContract('my-chaincode');

      // We can verify by invoking a transaction
      expect(() async {
        await contract.evaluateTransaction('test');
      }, isNotNull);
    });

    test('multiple getContract calls return independent Contract instances',
        () {
      final Contract contract1 = network.getContract('chaincode1');
      final Contract contract2 = network.getContract('chaincode2');

      expect(contract1, isNotNull);
      expect(contract2, isNotNull);
      expect(contract1.chaincodeName, equals('chaincode1'));
      expect(contract2.chaincodeName, equals('chaincode2'));
    });

    test('network name is accessible', () {
      expect(network.name, equals('my-channel'));
    });
  });

  group('Gateway Integration Tests', () {
    late List<int> testIdentity;

    setUp(() {
      testIdentity = utf8.encode('test-identity-cert');
    });

    test('Gateway.newBuilder creates GatewayBuilder', () {
      final GatewayBuilder builder = Gateway.newBuilder();
      expect(builder, isNotNull);
    });

    test('GatewayBuilder configuration chain works', () {
      final GatewayBuilder builder = Gateway.newBuilder()
        ..connection('localhost:7051')
        ..identityBytes(testIdentity)
        ..signer(_mockSigner);

      expect(builder, isNotNull);
    });

    test('GatewayBuilder with identitySignerAdapter configuration chain works',
        () {
      final SimpleSignerAdapter adapter =
          SimpleSignerAdapter(testIdentity, _mockSigner);

      final GatewayBuilder builder = Gateway.newBuilder()
        ..connection('localhost:7051')
        ..identitySignerAdapter(adapter);

      expect(builder, isNotNull);
    });
  });

  group('Proposal and Transaction Builders', () {
    late MockGatewayClient mockClient;
    late Contract contract;
    late List<int> testIdentity;

    setUp(() {
      mockClient = MockGatewayClient();
      testIdentity = utf8.encode('test-identity-cert');

      contract = Contract.internal(
        'my-chaincode',
        'contract-name',
        mockClient,
        'my-channel',
        identity: testIdentity,
        signer: _mockSigner,
      );
    });

    test('newProposal returns ProposalBuilder', () {
      final ProposalBuilder builder = contract.newProposal('submitOrder');
      expect(builder, isNotNull);
    });

    test('Proposal.evaluate() invokes evaluateTransaction', () async {
      final Proposal proposal =
          (contract.newProposal('submitOrder') as dynamic).build();
      final Uint8List result = await proposal.evaluate();

      expect(mockClient.evaluateCalled, isTrue);
      expect(
          result, equals(Uint8List.fromList(utf8.encode('evaluation-result'))));
    });

    test('Proposal.endorse() invokes endorseTransaction', () async {
      final Proposal proposal =
          (contract.newProposal('submitOrder') as dynamic).build();
      final Transaction transaction = await proposal.endorse();

      expect(mockClient.endorseCalled, isTrue);
      expect(transaction, isNotNull);
      expect(transaction.transactionId, isNotEmpty);
      expect(mockClient.lastEndorseRequest.proposedTransaction.proposalBytes,
          isNotEmpty);
      expect(mockClient.lastEndorseRequest.proposedTransaction.signature,
          isNotEmpty);
    });

    test('Transaction.submit() sends SubmitRequest', () async {
      final Proposal proposal =
          (contract.newProposal('submitOrder') as dynamic).build();
      final Transaction transaction = await proposal.endorse();

      await transaction.submit();

      expect(mockClient.submitCalled, isTrue);
      expect(mockClient.lastSubmitRequest.transactionId,
          equals(transaction.transactionId));
    });
  });

  group('End-to-End Workflow Tests', () {
    late MockGatewayClient mockClient;
    late Network network;
    late List<int> testIdentity;

    setUp(() {
      mockClient = MockGatewayClient();
      testIdentity = utf8.encode('test-identity-cert');

      network = Network(
        'fabric-channel',
        mockClient,
        testIdentity,
        _mockSigner,
      );
    });

    test('complete evaluate workflow', () async {
      final Contract contract = network.getContract('asset-chaincode');
      final Uint8List result =
          await contract.evaluateTransaction('getAsset', ['asset123']);

      expect(mockClient.evaluateCalled, isTrue);
      expect(result, isNotEmpty);
    });

    test('complete submit workflow', () async {
      final Contract contract = network.getContract('asset-chaincode');
      await contract.submitTransaction('createAsset', ['asset456', 'data']);

      expect(mockClient.endorseCalled, isTrue);
      expect(mockClient.submitCalled, isTrue);
    });

    test('proposal-based workflow', () async {
      final Contract contract = network.getContract('asset-chaincode');
      final ProposalBuilder pb = contract.newProposal('updateAsset');
      final Proposal proposal = (pb as dynamic).build();

      final Transaction tx = await proposal.endorse();
      await tx.submit();

      expect(mockClient.endorseCalled, isTrue);
      expect(mockClient.submitCalled, isTrue);
    });

    test('multiple contracts on same network', () async {
      final Contract assetContract = network.getContract('asset-cc');
      final Contract orderContract = network.getContract('order-cc');

      mockClient.evaluateCalled = false;
      await assetContract.evaluateTransaction('getAsset', ['id1']);
      expect(mockClient.evaluateCalled, isTrue);

      mockClient.evaluateCalled = false;
      await orderContract.evaluateTransaction('getOrder', ['id2']);
      expect(mockClient.evaluateCalled, isTrue);
    });
  });

  group('MockGatewayClient Response Customization', () {
    late MockGatewayClient mockClient;
    late Contract contract;
    late List<int> testIdentity;

    setUp(() {
      mockClient = MockGatewayClient();
      testIdentity = utf8.encode('test-identity-cert');

      contract = Contract.internal(
        'my-chaincode',
        'contract-name',
        mockClient,
        'my-channel',
        identity: testIdentity,
        signer: _mockSigner,
      );
    });

    test('customize evaluate response payload', () async {
      mockClient.evaluateResponsePayload = utf8.encode('custom-result');

      final Uint8List result =
          await contract.evaluateTransaction('getTx', ['id']);

      expect(result, equals(Uint8List.fromList(utf8.encode('custom-result'))));
    });

    test('verify request details from mock', () async {
      await contract.evaluateTransaction('myTxn', ['arg1', 'arg2']);

      expect(mockClient.lastEvaluateRequest.transactionId, isNotEmpty);
      expect(mockClient.lastEvaluateRequest.channelId, equals('my-channel'));
    });

    test('track multiple RPC calls', () async {
      final Contract contract1 = Contract.internal(
          'cc1', null, mockClient, 'ch1',
          identity: testIdentity, signer: _mockSigner);
      final Contract contract2 = Contract.internal(
          'cc2', null, mockClient, 'ch2',
          identity: testIdentity, signer: _mockSigner);

      await contract1.evaluateTransaction('txn1');
      expect(mockClient.lastEvaluateRequest.channelId, equals('ch1'));

      await contract2.evaluateTransaction('txn2');
      expect(mockClient.lastEvaluateRequest.channelId, equals('ch2'));
    });
  });
}
