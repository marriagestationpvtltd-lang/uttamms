/// Web stub for google_mlkit_text_recognition.
///
/// ML Kit text recognition requires native device ML models and is not
/// available in the browser.  All methods are no-ops on web.
library web_mlkit_text_recognition_stub;

enum Script { latin }

class TextRecognizer {
  const TextRecognizer({this.script = Script.latin});
  final Script script;

  Future<RecognizedText> processImage(InputImage inputImage) async =>
      const RecognizedText._('', []);

  Future<void> close() async {}
}

class RecognizedText {
  const RecognizedText._(this.text, this.blocks);
  final String text;
  final List<TextBlock> blocks;
}

class TextBlock {
  const TextBlock._(this.text, this.lines);
  final String text;
  final List<TextLine> lines;
}

class TextLine {
  const TextLine._(this.text);
  final String text;
}

class InputImage {
  InputImage.fromFilePath(String path);
}
