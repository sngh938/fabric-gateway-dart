import 'package:test/test.dart';
import 'package:fabric_gateway/fabric_gateway.dart';
import 'package:fabric_gateway/src/protos/gateway/gateway.pb.dart' as gw;

void main() {
  test('gateway builder connect throws unimplemented', () async {
    final GatewayBuilder builder = Gateway.newBuilder();
    expect(() async => await builder.connect(),
        throwsA(isA<UnimplementedError>()));
  });
  test('generated EvaluateRequest can be constructed', () {
    final gw.EvaluateRequest req = gw.EvaluateRequest()
      ..transactionId = 'tx123'
      ..channelId = 'mychannel';
    expect(req.transactionId, equals('tx123'));
    expect(req.channelId, equals('mychannel'));
  });
}
