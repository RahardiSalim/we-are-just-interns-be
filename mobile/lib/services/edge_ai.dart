import 'dart:convert';
import 'dart:io';
import 'dart:math' show exp;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/wordpiece.dart';
import 'dev_ml.dart';
import 'on_device_stt.dart';

/// Edge AI: speech-to-text and the classifier both run on the phone, from models bundled in the app
/// (`assets/models/`, Android only). Nothing about the speech leaves the phone to be judged.
///
/// - Speech-to-text: Whisper maleo base (ggml q8_0, 82 MB) with Silero voice detection (0.9 MB), through
///   `onDeviceListener`.
/// - Classifier: IndoBERT-lite clf-lite-5x as ONNX (35 MB; only its word table is int8, which changed no
///   decision on 735 test sentences), through ONNX Runtime, with [ModelClassifier]'s rules.
class EdgeAi {
  static const _whisper = 'assets/models/ggml-base-id-q8_0.bin';
  static const _vad = 'assets/models/ggml-silero-v5.1.2.bin';
  static const _model = 'assets/models/classifier.onnx';

  /// The classifier, with the model on the phone. It loads on the first line it scores.
  final classifier = ModelClassifier(_score);

  /// Finished sentences from the microphone ([pcm] instead, for a test file), each scored before it's
  /// handed on. [modelPath] / [vadPath] replace the bundled speech models, to try another one.
  Stream<String> listen({
    String? modelPath,
    String? vadPath,
    Stream<Uint8List>? pcm,
    int chunkSecs = 6,
  }) async* {
    final String model, vad;
    try {
      model = modelPath ?? await assetFile(_whisper);
      vad = vadPath ?? await assetFile(_vad);
    } catch (e) {
      // No speech-to-text this ride (e.g. no room to copy the models); recording and SOS still work.
      debugPrint('edge AI: speech models unavailable: $e');
      return;
    }
    yield* onDeviceListener(
      modelPath: model,
      vadModelPath: vad,
      pcm: pcm,
      chunkSecs: chunkSecs,
    ).asyncMap((line) async {
      try {
        await classifier.learn(line);
      } catch (e) {
        debugPrint('edge AI: classifier failed, keywords only for this line: $e');
      }
      return line; // a line the model couldn't score is still judged by the keywords
    });
  }

  /// Copies the speech models out ahead of the first ride, so its opening words aren't lost to the copy.
  static Future<void> prepare() async {
    try {
      await assetFile(_whisper);
      await assetFile(_vad);
    } catch (e) {
      debugPrint('edge AI: could not copy the speech models yet: $e');
    }
  }

  static Future<(OrtSession, WordPiece, List<String>)>? _loaded;

  static Future<(String, double)> _score(String line) async {
    final loading = _loaded ??= _load();
    final (OrtSession, WordPiece, List<String>) loaded;
    try {
      loaded = await loading;
    } catch (_) {
      _loaded = null; // try again on the next line instead of failing for the rest of the app's life
      rethrow;
    }
    final (session, tok, labels) = loaded;
    final ids = tok.encode(line);
    final n = ids.length;
    final inputs = {
      'input_ids': await OrtValue.fromList(Int64List.fromList(ids), [1, n]),
      'attention_mask': await OrtValue.fromList(Int64List(n)..fillRange(0, n, 1), [1, n]),
      'token_type_ids': await OrtValue.fromList(Int64List(n), [1, n]),
    };
    final out = await session.run(inputs);
    final logits = [for (final v in await out['logits']!.asFlattenedList()) (v as num).toDouble()];
    for (final v in [...inputs.values, ...out.values]) {
      await v.dispose();
    }
    return best(logits, labels);
  }

  /// The top label and its probability (softmax of the model's logits).
  static (String, double) best(List<double> logits, List<String> labels) {
    final top = logits.reduce((a, b) => a > b ? a : b);
    final e = [for (final l in logits) exp(l - top)];
    final sum = e.reduce((a, b) => a + b);
    var i = 0;
    for (var j = 1; j < e.length; j++) {
      if (e[j] > e[i]) i = j;
    }
    return (labels[i], e[i] / sum);
  }

  static Future<(OrtSession, WordPiece, List<String>)> _load() async {
    final session = await OnnxRuntime().createSessionFromAsset(_model);
    final vocab = const LineSplitter().convert(await rootBundle.loadString('assets/models/vocab.txt'));
    final labels = (jsonDecode(await rootBundle.loadString('assets/models/labels.json')) as List).cast<String>();
    return (session, WordPiece(vocab), labels);
  }

  /// A bundled model copied to the app's own folder once, because whisper.cpp reads a file path.
  // shortcut: the copy is reused by name; give a changed model a new file name, or it keeps the old one.
  static Future<String> assetFile(String asset) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/models/${asset.split('/').last}');
    if (await file.exists()) return file.path;
    await file.parent.create(recursive: true);
    final data = await rootBundle.load(asset);
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await tmp.rename(file.path); // atomic: a killed copy never leaves a half file under the real name
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    return file.path;
  }
}
