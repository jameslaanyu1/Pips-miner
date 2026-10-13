import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
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
  const OptionsZonePlan({
    required this.zones,
    required this.referencePrice,
    required this.middleStrike,
    required this.expiry,
    required this.sourceText,
  });
  final List<OptionsZone> zones;
  final double referencePrice;
  /// The central strike from the seven selected strikes. Displayed as a pivot,
  /// never included among the six support/resistance zones.
  final double middleStrike;
  final String? expiry;
  final String sourceText;

  factory OptionsZonePlan.fromJson(Map<String, dynamic> json) => OptionsZonePlan(
    zones: (json['zones'] as List<dynamic>)
        .map((zone) => OptionsZone.fromJson(Map<String, dynamic>.from(zone as Map)))
        .toList(),
    referencePrice: (json['referencePrice'] as num).toDouble(),
    middleStrike: (json['middleStrike'] as num?)?.toDouble()
        ?? (json['referencePrice'] as num).toDouble(),
    expiry: json['expiry'] as String?,
    sourceText: json['sourceText'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'zones': zones.map((z) => z.toJson()).toList(),
    'referencePrice': referencePrice,
    'middleStrike': middleStrike,
    'expiry': expiry,
    'sourceText': sourceText,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

class IvOptionsParser {
  static const storageKey = 'pips_miner_iv_options_zone_plan';
  static const sourcePathKey = 'pips_miner_iv_options_source_path';
  static const sourceNameKey = 'pips_miner_iv_options_source_name';

  Future<OptionsZonePlan> parsePickedFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) throw const FormatException('No file selected.');
    final file = result.files.single;
    final name = file.name;
    final lowerName = name.toLowerCase();
    final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) throw const FormatException('Could not read the selected file.');

    String text;
    if (lowerName.endsWith('.pdf')) {
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
      final existingPath = file.path;
      final tempFile = existingPath == null
          ? File('${(await getTemporaryDirectory()).path}/iv_options_ocr_${DateTime.now().microsecondsSinceEpoch}_${name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}')
          : null;
      if (tempFile != null) await tempFile.writeAsBytes(bytes, flush: true);
      final imagePath = existingPath ?? tempFile!.path;
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final recognized = await recognizer.processImage(InputImage.fromFilePath(imagePath));
        text = recognized.text;
      } finally {
        await recognizer.close();
        if (tempFile != null && await tempFile.exists()) await tempFile.delete();
      }
    }

    // Keep the previous file and plan if this new file cannot be parsed.
    final plan = parseText(text);
    await _persistSourceFile(name, bytes);
    await saveApprovedPlan(plan);
    return plan;
  }

  Future<void> _persistSourceFile(String name, Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : 'bin';
    final savedFile = File('${directory.path}/iv_options_source.$extension');
    await savedFile.writeAsBytes(bytes, flush: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sourcePathKey, savedFile.path);
    await prefs.setString(sourceNameKey, name);
  }

  OptionsZonePlan parseText(String source) {
    final text = source.replaceAll(',', '').replaceAll(RegExp(r'[\t ]+'), ' ');
    final values = <double>{};
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
    final anchor = spot ?? sorted[sorted.length ~/ 2];
    final nearest = sorted.toList()..sort((a, b) {
      final distance = (a - anchor).abs().compareTo((b - anchor).abs());
      return distance != 0 ? distance : a.compareTo(b);
    });
    final selected = nearest.take(7).toList()..sort();
    if (selected.length != 7) {
      throw const FormatException('Seven distinct gold strikes are required to create a pivot and six zones.');
    }

    final middleIndex = selected.length ~/ 2;
    final lower = selected.take(middleIndex).toList();
    final upper = selected.skip(middleIndex + 1).toList();
    final middleStrike = selected[middleIndex];
    final reference = spot ?? middleStrike;
    final zones = <OptionsZone>[
      OptionsZone(label: 'R3', price: upper[2], isResistance: true),
      OptionsZone(label: 'R2', price: upper[1], isResistance: true),
      OptionsZone(label: 'R1', price: upper[0], isResistance: true),
      OptionsZone(label: 'S1', price: lower[2], isResistance: false),
      OptionsZone(label: 'S2', price: lower[1], isResistance: false),
      OptionsZone(label: 'S3', price: lower[0], isResistance: false),
    ];
    final expiryMatch = RegExp(r'(?:expir(?:y|ing|ation)?\s*[: ]?\s*)(\d{4}[-/]\d{2}[-/]\d{2})', caseSensitive: false).firstMatch(text);
    return OptionsZonePlan(
      zones: zones,
      referencePrice: reference,
      middleStrike: middleStrike,
      expiry: expiryMatch?.group(1),
      sourceText: text,
    );
  }

  Future<void> saveApprovedPlan(OptionsZonePlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(plan.toJson()));
  }

  Future<void> clearPlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    final prefsPath = prefs.getString(sourcePathKey);
    if (prefsPath != null) {
      final source = File(prefsPath);
      if (await source.exists()) await source.delete();
    }
    await prefs.remove(sourcePathKey);
    await prefs.remove(sourceNameKey);
  }

  Future<Map<String, dynamic>?> loadSavedPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadSavedSourceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(sourceNameKey);
  }
}
