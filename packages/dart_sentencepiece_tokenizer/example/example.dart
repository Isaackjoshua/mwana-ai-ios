// ignore_for_file: avoid_print

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';

void main() async {
  // Load tokenizer from .model file
  final tokenizer = await SentencePieceTokenizer.fromModelFile(
    'tokenizer.model',
    config: SentencePieceConfig.llama, // BOS token only
  );

  // Basic encoding
  final encoding = tokenizer.encode('Hello, world!');
  print('Tokens: ${encoding.tokens}');
  print('IDs: ${encoding.ids}');
  print('Attention Mask: ${encoding.attentionMask}');

  // Decode back to text
  final decoded = tokenizer.decode(encoding.ids);
  print('Decoded: $decoded');

  // Sentence pair encoding (for QA, NLI tasks)
  final pairEncoding = tokenizer.encodePair(
    'What is machine learning?',
    'Machine learning is a subset of AI.',
  );
  print('Type IDs: ${pairEncoding.typeIds}'); // 0 for first, 1 for second

  // Batch encoding
  final texts = ['Hello', 'World', 'Dart'];
  final batchEncodings = tokenizer.encodeBatch(texts);
  for (var i = 0; i < texts.length; i++) {
    print('${texts[i]}: ${batchEncodings[i].ids}');
  }

  // Enable padding and truncation
  tokenizer
    ..enablePadding(length: 32, direction: SpPaddingDirection.right)
    ..enableTruncation(maxLength: 32);

  final paddedEncoding = tokenizer.encode('Short text');
  print('Padded length: ${paddedEncoding.length}'); // 32

  // Offset mapping
  final text = 'Hello world';
  final enc = tokenizer.encode(text, addSpecialTokens: false);
  for (var i = 0; i < enc.length; i++) {
    final offset = enc.offsets[i];
    print('Token "${enc.tokens[i]}" -> chars ${offset.$1}:${offset.$2}');
  }

  // Vocabulary access
  print('Vocab size: ${tokenizer.vocabSize}');
  print('BOS ID: ${tokenizer.vocab.bosId}');
  print('EOS ID: ${tokenizer.vocab.eosId}');

  // ========================================
  // Streaming API (v1.3.0+)
  // ========================================

  // TextStreamer - HuggingFace compatible streaming
  // Useful for displaying LLM output in real-time
  print('\n--- Streaming API ---');

  // Basic streaming with default stdout output
  final streamer = tokenizer.createTextStreamer();
  final tokens = tokenizer.encode('Hello, streaming world!');
  print('Streaming output: ');
  for (final id in tokens.ids) {
    streamer.put(id);
  }
  streamer.end();

  // Custom callback for streaming
  final chunks = <String>[];
  final customStreamer = tokenizer.createTextStreamer(
    onFinalizedText: (text, {required streamEnd}) {
      chunks.add(text);
      if (streamEnd) {
        print('Stream ended');
      }
    },
  );

  for (final id in tokens.ids) {
    customStreamer.put(id);
  }
  customStreamer.end();
  print('Collected chunks: $chunks');

  // Stream-based decoding
  final tokenStream = Stream.fromIterable(tokens.ids.toList());
  final textStream = tokenizer.decodeStream(tokenStream);
  final result = StringBuffer();
  await for (final chunk in textStream) {
    result.write(chunk);
  }
  print('Stream result: $result');

  // Callback-based decoding
  final callbackResult = StringBuffer();
  tokenizer.decodeWithCallback(
    tokens.ids.toList(),
    (chunk) => callbackResult.write(chunk),
  );
  print('Callback result: $callbackResult');

  // Skip prompt tokens (useful for chat models)
  final promptStreamer = tokenizer.createTextStreamer(
    skipPrompt: true,
    promptLength: 3, // Skip first 3 tokens
    onFinalizedText: (text, {required streamEnd}) => print(text),
  );
  // Feed tokens...
  promptStreamer.end();
}
