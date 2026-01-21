import 'dart:convert';

import 'package:test/test.dart';
import 'package:fabric_gateway/src/proposal_builder.dart'
    show buildSignedProposal;
import 'package:fabric_gateway/src/protos/peer/proposal.pb.dart' as $peer;
import 'package:fabric_gateway/src/protos/common/common.pb.dart' as $common;
import 'package:fabric_gateway/src/protos/peer/chaincode.pb.dart' as $cc;

Future<List<int>> _mockSigner(List<int> message) async {
  // Deterministic mock signature: prefix + first 8 bytes of message (or whole message)
  final List<int> prefix = utf8.encode('mock-sign:');
  final List<int> tail = message.take(8).toList();
  return <int>[...prefix, ...tail];
}

void main() {
  test('buildSignedProposal constructs parsable proposal and signs it',
      () async {
    final String channel = 'mychannel';
    final String chaincode = 'mycc';
    final String txName = 'transfer';
    final List<String> args = <String>['a', 'b'];
    final List<int> identity = utf8.encode('TestCreator');

    final $peer.SignedProposal signed = await buildSignedProposal(
      channel: channel,
      chaincodeName: chaincode,
      transactionName: txName,
      args: args,
      identity: identity,
      signer: _mockSigner,
    );

    // Signature should be non-empty
    expect(signed.signature, isNotEmpty);

    // Proposal bytes should parse
    final $peer.Proposal proposal =
        $peer.Proposal.fromBuffer(signed.proposalBytes);
    expect(proposal.payload, isNotEmpty);
    expect(proposal.header, isNotEmpty);

    // Parse header and verify channel id and creator
    final $common.Header header = $common.Header.fromBuffer(proposal.header);
    final $common.ChannelHeader ch =
        $common.ChannelHeader.fromBuffer(header.channelHeader);
    expect(ch.channelId, equals(channel));
    expect(ch.txId, isNotEmpty);

    final $common.SignatureHeader sh =
        $common.SignatureHeader.fromBuffer(header.signatureHeader);
    expect(sh.creator, equals(identity));

    // Parse payload and check chaincode name and args
    final $peer.ChaincodeProposalPayload payload =
        $peer.ChaincodeProposalPayload.fromBuffer(proposal.payload);
    final $cc.ChaincodeInvocationSpec invocation =
        $cc.ChaincodeInvocationSpec.fromBuffer(payload.input);
    expect(invocation.chaincodeSpec.chaincodeId.name, equals(chaincode));
    final List<List<int>> invocationArgs = invocation.chaincodeSpec.input.args;
    // first arg is transaction name
    expect(utf8.decode(invocationArgs[0]), equals(txName));
    // following args match
    expect(utf8.decode(invocationArgs[1]), equals(args[0]));
    expect(utf8.decode(invocationArgs[2]), equals(args[1]));
  });
}
