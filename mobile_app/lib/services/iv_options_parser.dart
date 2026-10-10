import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class OptionsZone {
  const OptionsZone({required this.label, required this.price, required this.isResistance});
  final String label;
  final double price;
  final bool isResistance;

  Map<String, dynamic> toJson() => {'label': label, 'price': price, 'isResistance': isResistance};
  factory OptionsZone.fromJson(Map<String, dynamic> json) => OptionsZone(
    label: json['label'] as String,
    price: (json['price'] as num).toDouble(),
    isResistance: json['isResistance'] as bool,
  );
}

class OptionsZonePlan {
  const OptionsZonePlan({required this.zones, required this.referencePrice, required this.expiry, required this.sourceText});
  final List<OptionsZone> zones;
  final double referencePrice;
  final String? expiry;
  final String sourceText;

  Map<String, dynamic> toJson() => {
    'zones': zones.map((z) => z.toJson()).toList(),
    'referencePrice': referencePrice,
    'expiry': expiry,
    'sourceText': sourceText,
    'approvedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

class IvOptionsParser {
  static const storageKey = 'pips_miner_iv_options_zone_plan';

  Future<OptionsZonePlan> parsePickedFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) throw const FormatException('No file selected.');
    final file = result.files.single;
    final name = file.name.toLowerCase();
    String text;
    if (name.endsWith('.pdf')) {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      try {
        text = PdfTextExtractor(document).extractText();
      } finally {
        document.dispose();
      }
      if (text.trim().isEmpty) {
        throw const FormatException('This PDF has no selectable text. Export its page as an image or upload a screenshot for OCR.');
      }
    } else {
      final path = file.path;
      if (path == null) throw const FormatException('Could not read the selected image.');
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final recognized = await recognizer.processImage(InputImage.fromFilePath(path));
        text = recognized.text;
      } finally {
        await recognizer.close();
      }
    }
    return parseText(text);
  }

  OptionsZonePlan parseText(String source) {
    final text = source.replaceAll(',', '').replaceAll(RegExp(r'[\t ]+'), ' ');
    final values = <double>{};
    // Gold strike prices are commonly four digits; avoid deltas/percentages.
    for (final match in RegExp(r'(?<![\d.])(\d{4,5}(?:\.\d+)?)(?![\d.])').allMatches(text)) {
      final value = double.tryParse(match.group(1)!);
      if (value != null && value >= 1000 && value <= 10000) values.add(value);
    }
    if (values.length < 7) {
      throw FormatException('Only ${values.length} possible gold strikes were found. Upload a clearer image/PDF with at least seven strike prices.');
    }
    final sorted = values.toList()..sort();
    final spotMatch = RegExp(r'(?:XAU\s*/?\s*USD|GOLD|SPOT)\D{0,30}(\d{4}(?:\.\d+)?)', caseSensitive: false).firstMatch(text);
    final spot = spotMatch == null ? null : double.tryParse(spotMatch.group(1)!);
    final reference = spot ?? sorted[sorted.length ~/ 2];
    // Keep the nearest six strikes around the reference, excluding the reference strike.
    final below = sorted.where((v) => v < reference).toList()..sort((a,b) => b.compareTo(a));
    final above = sorted.where((v) => v > reference).toList()..sort();
    if (below.length < 3 || above.length < 3) {
      throw const FormatException('Could not identify three strikes above and three below the reference price. Check the extracted text before retrying.');
    }
    final lower = below.take(3).toList()..sort();
    final upper = above.take(3).toList()..sort();
    final zones = <OptionsZone>[
      OptionsZone(label: 'R3', price: upper[2], isResistance: true),
      OptionsZone(label: 'R2', price: upper[1], isResistance: true),
      OptionsZone(label: 'R1', price: upper[0], isResistance: true),
      OptionsZone(label: 'S1', price: lower[2], isResistance: false),
      OptionsZone(label: 'S2', price: lower[1], isResistance: false),
      OptionsZone(label: 'S3', price: lower[0], isResistance: false),
    ];
    final expiryMatch = RegExp(r'(?:expir(?:y|ing|ation)?\s*[: ]?\s*)(\d{4}[-/]\d{2}[-/]\d{2})', caseSensitive: false).firstMatch(text);
    return OptionsZonePlan(zones: zones, referencePrice: reference, expiry: expiryMatch?.group(1), sourceText: text);
  }

  Future<void> saveApprovedPlan(OptionsZonePlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(plan.toJson()));
  }

  Future<void> clearPlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  Future<Map<String, dynamic>?> loadSavedPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) { return null; }
  }
}
