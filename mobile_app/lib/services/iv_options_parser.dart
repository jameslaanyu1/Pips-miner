import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class OptionsZone {
  const OptionsZone({required this.label, required this.price, required this.isResistance, this.isPivot = false});
  final String label;
  final double price;
  final bool isResistance;
  final bool isPivot;

  Map<String, dynamic> toJson() => {'label': label, 'price': price, 'isResistance': isResistance, 'isPivot': isPivot};
  factory OptionsZone.fromJson(Map<String, dynamic> json) => OptionsZone(
    label: json['label'] as String,
    price: (json['price'] as num).toDouble(),
    isResistance: json['isResistance'] as bool,
    isPivot: json['isPivot'] == true,
  );
}

class OptionsZonePlan {
  const OptionsZonePlan({required this.zones, required this.sevenStrikes, required this.referencePrice, required this.expiry, required this.sourceText, this.pivotPrice});
  final List<OptionsZone> zones;
  /// All seven selected strike prices in ascending order; index 3 is always the pivot.
  final List<double> sevenStrikes;
  final double referencePrice;
  final double? pivotPrice;
  final String? expiry;
  final String sourceText;

  factory OptionsZonePlan.fromJson(Map<String, dynamic> json) => OptionsZonePlan(
    zones: (json['zones'] as List).whereType<Map>().map((z) => OptionsZone.fromJson(Map<String, dynamic>.from(z))).toList(),
    sevenStrikes: (json['strikes'] as List).map((v) => (v as num).toDouble()).toList(),
    referencePrice: (json['referencePrice'] as num).toDouble(),
    pivotPrice: (json['pivotPrice'] as num?)?.toDouble(),
    expiry: json['expiry']?.toString(),
    sourceText: json['sourceText']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'zones': zones.map((z) => z.toJson()).toList(),
    'strikes': sevenStrikes,
    'pivotStrikeIndex': 3,
    'referencePrice': referencePrice,
    'pivotPrice': pivotPrice,
    'pivotIsTradingLevel': true,
    'expiry': expiry,
    'sourceText': sourceText,
    'approvedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

class IvOptionsParser {
  static const storageKey = 'pips_miner_iv_options_zone_plan';
  static const sourceNameKey = 'pips_miner_iv_options_source_name';
  static const sourcePathKey = 'pips_miner_iv_options_source_path';

  Future<OptionsZonePlan> parsePickedFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) throw const FormatException('No file selected.');
    final file = result.files.single;
    final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) throw const FormatException('The selected file is empty or cannot be read.');

    final text = file.name.toLowerCase().endsWith('.pdf')
        ? await _readPdf(bytes)
        : await _recognizeImageBytes(bytes, file.name);
    if (text.trim().isEmpty) {
      throw const FormatException('No readable text was detected. Try a higher-resolution screenshot with the strike-price column fully visible.');
    }
    final plan = parseText(text);
    await _persistSourceFile(file.name, bytes);
    await saveApprovedPlan(plan);
    return plan;
  }

  Future<String> _readPdf(Uint8List bytes) async {
    // First use embedded text; this is much more accurate for digitally generated PDFs.
    final doc = PdfDocument(inputBytes: bytes);
    String embedded;
    try {
      embedded = PdfTextExtractor(doc).extractText();
    } finally {
      doc.dispose();
    }
    if (_hasLikelyPrice(embedded)) return embedded;

    // Screenshot/scanned PDFs have no text layer. Render every page and OCR it.
    final pdf = await pdfx.PdfDocument.openData(bytes);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final output = <String>[];
    Directory? tempDir;
    try {
      tempDir = await getTemporaryDirectory();
      for (var i = 1; i <= pdf.pagesCount; i++) {
        final page = await pdf.getPage(i);
        try {
          // Render at a high resolution so small strike digits remain legible.
          // Render screenshot/scanned pages at a consistently high pixel width.
          // The old 3.5x cap could leave small strike digits too soft on phone screenshots.
          final scale = (3000 / page.width).clamp(2.0, 5.0);
          final rendered = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: pdfx.PdfPageImageFormat.png,
          );
          if (rendered == null) continue;
          final imageFile = File('${tempDir.path}/pips_iv_page_${DateTime.now().microsecondsSinceEpoch}_$i.png');
          try {
            await imageFile.writeAsBytes(rendered.bytes, flush: true);
            final recognized = await recognizer.processImage(InputImage.fromFilePath(imageFile.path));
            if (recognized.text.trim().isNotEmpty) output.add(recognized.text);
          } finally {
            await imageFile.delete().catchError((_) => imageFile);
          }
        } finally {
          await page.close();
        }
      }
    } finally {
      await recognizer.close();
      await pdf.close();
    }
    final ocrText = output.join('\n');
    if (!_hasLikelyPrice(ocrText)) {
      throw FormatException('PDF OCR could not confidently find enough gold strike prices. Detected text: ${ocrText.trim().isEmpty ? '(none)' : ocrText.substring(0, ocrText.length.clamp(0, 500))}');
    }
    return ocrText;
  }

  Future<String> _recognizeImageBytes(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final extension = name.contains('.') ? name.split('.').last : 'jpg';
    final imageFile = File('${dir.path}/pips_iv_${DateTime.now().microsecondsSinceEpoch}.$extension');
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      await imageFile.writeAsBytes(bytes, flush: true);
      return (await recognizer.processImage(InputImage.fromFilePath(imageFile.path))).text;
    } finally {
      await recognizer.close();
      await imageFile.delete().catchError((_) => imageFile);
    }
  }

  bool _hasLikelyPrice(String text) {
    final normalized = _normalizeOcrText(text);
    final matches = RegExp(r'(?<![\d.])(\d{4,5}(?:\.\d+)?)(?![\d.])').allMatches(normalized);
    return matches.map((m) => double.tryParse(m.group(1)!))
        .whereType<double>().where((v) => v >= 1000 && v <= 10000).toSet().length >= 7;
  }

  String _normalizeOcrText(String source) {
    // ML Kit can confuse O/o with zero inside otherwise numeric strike prices.
    return source
        .replaceAllMapped(RegExp(r'(?<=\d)[Oo](?=\d)'), (_) => '0')
        .replaceAll(RegExp(r'(?<=\d),(?=\d{3}\b)'), '')
        .replaceAll(RegExp(r'[\t ]+'), ' ');
  }
  OptionsZonePlan parseText(String source) {
    final text = _normalizeOcrText(source);
    final values = <double>{};
    for (final match in RegExp(r'(?<![\d.])(\d{4,5}(?:\.\d+)?)(?![\d.])').allMatches(text)) {
      final value = double.tryParse(match.group(1)!);
      if (value != null && value >= 1000 && value <= 10000) values.add(value);
    }
    if (values.length < 7) {
      throw FormatException('Only ${values.length} possible gold strikes were found. Upload a clearer image/PDF with at least seven distinct strike prices.');
    }
    final sorted = values.toList()..sort();
    final spotMatch = RegExp(r'(?:XAU\s*/?\s*USD|GOLD|SPOT)\D{0,30}(\d{4}(?:\.\d+)?)', caseSensitive: false).firstMatch(text);
    final spot = spotMatch == null ? null : double.tryParse(spotMatch.group(1)!);
    final anchor = spot ?? sorted[sorted.length ~/ 2];
    final nearest = sorted.toList()..sort((a, b) => (a - anchor).abs().compareTo((b - anchor).abs()));
    final selected = nearest.take(7).toList()..sort();
    final middleIndex = selected.length ~/ 2;
    final lower = selected.take(middleIndex).toList();
    final pivot = selected[middleIndex];
    final upper = selected.skip(middleIndex + 1).toList();
    final zones = <OptionsZone>[
      OptionsZone(label: 'R3', price: upper[2], isResistance: true),
      OptionsZone(label: 'R2', price: upper[1], isResistance: true),
      OptionsZone(label: 'R1', price: upper[0], isResistance: true),
      OptionsZone(label: 'PIVOT', price: pivot, isResistance: false, isPivot: true),
      OptionsZone(label: 'S1', price: lower[2], isResistance: false),
      OptionsZone(label: 'S2', price: lower[1], isResistance: false),
      OptionsZone(label: 'S3', price: lower[0], isResistance: false),
    ];
    final expiryMatch = RegExp(r'(?:expir(?:y|ing|ation)?\s*[: ]?\s*)(\d{4}[-/]\d{2}[-/]\d{2})', caseSensitive: false).firstMatch(text);
    return OptionsZonePlan(
      zones: zones,
      sevenStrikes: List<double>.unmodifiable(selected),
      referencePrice: spot ?? pivot,
      pivotPrice: pivot,
      expiry: expiryMatch?.group(1),
      sourceText: text,
    );
  }

  Future<void> _persistSourceFile(String name, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final previousPath = prefs.getString(sourcePathKey);
    final directory = await getApplicationDocumentsDirectory();
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : 'bin';
    final destination = File('${directory.path}/iv_options_reference.$extension');
    if (previousPath != null && previousPath != destination.path) {
      try { await File(previousPath).delete(); } catch (_) {}
    }
    await destination.writeAsBytes(bytes, flush: true);
    await prefs.setString(sourceNameKey, name);
    await prefs.setString(sourcePathKey, destination.path);
  }

  Future<String?> loadSavedSourceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(sourceNameKey);
  }

  Future<String?> loadSavedSourcePath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(sourcePathKey);
    if (path == null || !await File(path).exists()) return null;
    return path;
  }

  Future<void> saveApprovedPlan(OptionsZonePlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(plan.toJson()));
  }

  Future<void> clearPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final sourcePath = prefs.getString(sourcePathKey);
    if (sourcePath != null) { try { await File(sourcePath).delete(); } catch (_) {} }
    await prefs.remove(storageKey);
    await prefs.remove(sourceNameKey);
    await prefs.remove(sourcePathKey);
  }

  Future<Map<String, dynamic>?> loadSavedPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) { return null; }
  }
}
