import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'google_well_known_types/protobuf/timestamp.pb.dart'
    as $ts;
import 'package:fixnum/fixnum.dart' as $fixnum;

import 'protos/peer/proposal.pb.dart' as $peer;
import 'protos/peer/chaincode.pb.dart' as $cc;
import 'protos/common/common.pb.dart' as $common;

import 'types.dart';

/// Build a SignedProposal for a chaincode invocation.
///
/// - `channel` is the channel name.
/// - `chaincodeName` is the chaincode id/name.
/// - `transactionName` is the function to invoke (first argument).
/// - `args` are the function arguments (strings).
/// - `identity` is the marshaled `msp.SerializedIdentity` bytes.
/// - `signer` is a function that signs raw bytes and returns signature bytes.
Future<$peer.SignedProposal> buildSignedProposal({
  required String channel,
  required String chaincodeName,
  required String transactionName,
  List<String>? args,
  Map<String, List<int>>? transientMap,
  required List<int> identity,
  required Signer signer,
}) async {
  // 1) Build ChaincodeInvocationSpec -> ChaincodeProposalPayload
  final List<List<int>> inputArgs = <List<int>>[
    utf8.encode(transactionName),
    for (final String a in (args ?? <String>[])) utf8.encode(a)
  ];
  final $cc.ChaincodeInput input = $cc.ChaincodeInput()..args.addAll(inputArgs);

  final $cc.ChaincodeID ccid = $cc.ChaincodeID()..name = chaincodeName;

  final $cc.ChaincodeSpec spec = $cc.ChaincodeSpec()
    ..chaincodeId = ccid
    ..input = input;

  final $cc.ChaincodeInvocationSpec invocation = $cc.ChaincodeInvocationSpec()
    ..chaincodeSpec = spec;

  final Uint8List invocationBytes =
      Uint8List.fromList(invocation.writeToBuffer());

  final $peer.ChaincodeProposalPayload payload =
      $peer.ChaincodeProposalPayload()..input = invocationBytes;
  if (transientMap != null) {
    payload.transientMap.addAll(transientMap);
  }
  final Uint8List payloadBytes = Uint8List.fromList(payload.writeToBuffer());

  // 2) Build ChaincodeHeaderExtension
  final $peer.ChaincodeHeaderExtension ext = $peer.ChaincodeHeaderExtension()
    ..chaincodeId = ccid;
  final Uint8List extBytes = Uint8List.fromList(ext.writeToBuffer());

  // 3) Generate nonce first (needed for transaction ID)
  final Random rng = Random.secure();
  final Uint8List nonce =
      Uint8List.fromList(List<int>.generate(24, (_) => rng.nextInt(256)));

  // 3.1) Compute transaction ID: SHA-256(nonce + creator)
  final Uint8List saltedCreator = Uint8List.fromList([...nonce, ...identity]);
  final Digest digest = sha256.convert(saltedCreator);
  final String txId = digest.toString();

  // 3.2) Build ChannelHeader
  final $ts.Timestamp now = $ts.Timestamp.fromDateTime(DateTime.now().toUtc());
  final $common.ChannelHeader ch = $common.ChannelHeader()
    ..type = 3
    ..version = 1
    ..timestamp = now
    ..channelId = channel
    ..txId = txId
    ..epoch = $fixnum.Int64.ZERO
    ..extension_7 = extBytes;
  final Uint8List chBytes = Uint8List.fromList(ch.writeToBuffer());

  // 4) Build SignatureHeader (use the same nonce from transaction ID computation)
  final $common.SignatureHeader sh = $common.SignatureHeader()
    ..creator = identity
    ..nonce = nonce;
  final Uint8List shBytes = Uint8List.fromList(sh.writeToBuffer());

  // 5) Build Header (channelHeader + signatureHeader)
  final $common.Header header = $common.Header()
    ..channelHeader = chBytes
    ..signatureHeader = shBytes;
  final Uint8List headerBytes = Uint8List.fromList(header.writeToBuffer());

  // 6) Build Proposal (header + payload)
  final $peer.Proposal proposal = $peer.Proposal()
    ..header = headerBytes
    ..payload = payloadBytes;
  final Uint8List proposalBytes = Uint8List.fromList(proposal.writeToBuffer());

  // 7) Sign proposalBytes
  final List<int> signature = await signer(proposalBytes);

  return $peer.SignedProposal(
      proposalBytes: proposalBytes, signature: signature);
}
