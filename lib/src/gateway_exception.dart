import 'protos/gateway/gateway.pb.dart' as $gw;

/// Exception thrown when a Fabric Gateway RPC call fails.
///
/// The [details] list contains decoded [ErrorDetail] messages from the
/// endorsing peers or ordering nodes that reported the failure.
class GatewayException implements Exception {
  final int code;
  final String codeName;
  final String? message;
  final List<$gw.ErrorDetail> details;

  GatewayException({
    required this.code,
    required this.codeName,
    this.message,
    this.details = const <$gw.ErrorDetail>[],
  });

  @override
  String toString() {
    final StringBuffer sb = StringBuffer('GatewayException: [$codeName] $message');
    for (final $gw.ErrorDetail detail in details) {
      sb.write('\n  - ${detail.address} (${detail.mspId}): ${detail.message}');
    }
    return sb.toString();
  }
}
