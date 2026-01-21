/// Checkpointer interface and simple in-memory implementation
abstract class Checkpointer {
  Future<void> checkpointBlock(int blockNumber);
  Future<void> checkpointTransaction(int blockNumber, String transactionId);
}

class InMemoryCheckpointer implements Checkpointer {
  @override
  Future<void> checkpointBlock(int blockNumber) async {
    // No-op for now
  }

  @override
  Future<void> checkpointTransaction(
      int blockNumber, String transactionId) async {
    // No-op for now
  }
}
