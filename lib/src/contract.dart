import 'dart:typed_data';

import 'protos/gateway/gateway.pb.dart' as $gw;
import 'protos/peer/proposal.pb.dart' as $peer;
import 'protos/common/common.pb.dart' as $common;
import 'proposal_builder.dart';

import 'gateway_client.dart';
import 'types.dart';
// proposal.dart contents inlined here to avoid circular imports

/// Represents a smart contract on a channel.
class Contract {
  final String chaincodeName;
  final String? contractName;

  final GatewayClient _client;
  final String _channel;
  final List<int>? _identity;
  final Signer? _signer;

  // Internal constructor used by Network when wiring the SDK.
  Contract.internal(
      this.chaincodeName, this.contractName, this._client, this._channel,
      {List<int>? identity, Signer? signer})
      : _identity = identity,
        _signer = signer;

  // Expose internal client and channel for use by Proposal helpers.
  GatewayClient get client => _client;

  String get channel => _channel;

  /// Evaluate a transaction and return result bytes.
  Future<Uint8List> evaluateTransaction(String transactionName,
      [List<String>? args]) async {
    if (_identity == null) {
      throw StateError('identity not configured for Contract');
    }
    if (_signer == null) {
      throw StateError('signer not configured for Contract');
    }

    final $peer.SignedProposal signedProposal = await buildSignedProposal(
        channel: _channel,
        chaincodeName: chaincodeName,
        transactionName: transactionName,
        args: args,
        identity: _identity!,
        signer: _signer!);

    final String txId = DateTime.now().microsecondsSinceEpoch.toString();
    final $gw.EvaluateRequest req = $gw.EvaluateRequest(
        transactionId: txId,
        channelId: _channel,
        proposedTransaction: signedProposal);

    final $gw.EvaluateResponse resp = await _client.evaluate(req);
    return Uint8List.fromList(resp.result.payload);
  }

  /// Submit a transaction (endorse + submit) and wait for commit.
  Future<Uint8List> submitTransaction(String transactionName,
      [List<String>? args]) async {
    if (_identity == null) {
      throw StateError('identity not configured for Contract');
    }
    if (_signer == null) {
      throw StateError('signer not configured for Contract');
    }

    final $peer.SignedProposal signedProposal = await buildSignedProposal(
        channel: _channel,
        chaincodeName: chaincodeName,
        transactionName: transactionName,
        args: args,
        identity: _identity!,
        signer: _signer!);

    final String txId = DateTime.now().microsecondsSinceEpoch.toString();

    // Endorse
    final $gw.EndorseRequest endorseReq = $gw.EndorseRequest(
        transactionId: txId,
        channelId: _channel,
        proposedTransaction: signedProposal);
    final $gw.EndorseResponse endorseResp = await _client.endorse(endorseReq);

    // The gateway returns a prepared transaction (Envelope). The client must
    // sign the envelope.payload and set the envelope.signature before submit.
    final $common.Envelope prepared = endorseResp.preparedTransaction;
    final List<int> envelopeSignature = await _signer!(prepared.payload);
    prepared.signature = envelopeSignature;

    final $gw.SubmitRequest submitReq = $gw.SubmitRequest(
        transactionId: txId,
        channelId: _channel,
        preparedTransaction: prepared);
    await _client.submit(submitReq);

    return Uint8List(0);
  }

  /// Create a proposal builder for advanced flows
  ProposalBuilder newProposal(String transactionName) {
    return _SimpleProposalBuilder(transactionName, this);
  }
}

/// ProposalBuilder/Proposal skeleton (more detailed API in proposal.dart)
abstract class ProposalBuilder {}

// Simple ProposalBuilder implementation used for initial wiring.
class _SimpleProposalBuilder implements ProposalBuilder {
  final String transactionName;
  final Contract _contract;

  _SimpleProposalBuilder(this.transactionName, this._contract);
  Proposal build() => Proposal._(transactionName, _contract);
}

/// Proposal and Transaction implementations (inlined here).
class Proposal {
  final String transactionName;
  final Contract _contract;

  Proposal(this.transactionName) : _contract = throw UnimplementedError();

  Proposal._(this.transactionName, this._contract);

  Future<Uint8List> evaluate() async {
    return _contract.evaluateTransaction(transactionName);
  }

  Future<Transaction> endorse() async {
    if (_contract._identity == null) {
      throw StateError('identity not configured for Proposal.endorse()');
    }
    if (_contract._signer == null) {
      throw StateError('signer not configured for Proposal.endorse()');
    }

    final String txId = DateTime.now().microsecondsSinceEpoch.toString();

    // Build signed proposal with full cryptographic flow
    final $peer.SignedProposal signedProposal = await buildSignedProposal(
        channel: _contract.channel,
        chaincodeName: _contract.chaincodeName,
        transactionName: transactionName,
        identity: _contract._identity!,
        signer: _contract._signer!);

    final $gw.EndorseRequest endorseReq = $gw.EndorseRequest(
        transactionId: txId,
        channelId: _contract.channel,
        proposedTransaction: signedProposal);

    final $gw.EndorseResponse resp = await _contract.client.endorse(endorseReq);
    return Transaction._(
        txId, _contract.client, resp.preparedTransaction, _contract.channel,
        signer: _contract._signer);
  }
}

class Transaction {
  final String transactionId;
  final GatewayClient _client;
  final dynamic _preparedTransaction;
  final String _channel;
  final Signer? _signer;

  Transaction._(this.transactionId, this._client, this._preparedTransaction,
      this._channel,
      {Signer? signer})
      : _signer = signer;

  Future<Uint8List> submit() async {
    // If we have a signer and the prepared transaction has an empty signature,
    // we need to sign it first (Proposal-based flow)
    final $common.Envelope envelope = _preparedTransaction as $common.Envelope;
    if (_signer != null && envelope.signature.isEmpty) {
      final List<int> envelopeSignature = await _signer!(envelope.payload);
      envelope.signature = envelopeSignature;
    }

    final $gw.SubmitRequest req = $gw.SubmitRequest(
        transactionId: transactionId,
        channelId: _channel,
        preparedTransaction: envelope);
    await _client.submit(req);
    return Uint8List(0);
  }
}
