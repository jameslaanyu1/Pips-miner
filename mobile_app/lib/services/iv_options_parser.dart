import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class OptionStrikeData {
  const OptionStrikeData({required this.strike, this.putDelta, this.putPrice, this.callPrice, this.callDelta, this.impliedVolatility});
  final double strike; final double? putDelta, putPrice, callPrice, callDelta, impliedVolatility;
  Map<String, dynamic> toJson() => {'strike': strike, 'putDelta': putDelta, 'putPrice': putPrice, 'callPrice': callPrice, 'callDelta': callDelta, 'impliedVolatility': impliedVolatility};
  factory OptionStrikeData.fromJson(Map<String, dynamic> j) => OptionStrikeData(strike: (j['strike'] as num).toDouble(), putDelta: (j['putDelta'] as num?)?.toDouble(), putPrice: (j['putPrice'] as num?)?.toDouble(), callPrice: (j['callPrice'] as num?)?.toDouble(), callDelta: (j['callDelta'] as num?)?.toDouble(), impliedVolatility: (j['impliedVolatility'] as num?)?.toDouble());
}

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
    this.strikes = const [],
  });
  final List<OptionsZone> zones;
  final double referencePrice;
  /// The central strike from the seven selected strikes. Displayed as a pivot,
  /// never included among the six support/resistance zones.
  final double middleStrike;
  final String? expiry;
  final String sourceText;
  final List<OptionStrikeData> strikes;

  factory OptionsZonePlan.fromJson(Map<String, dynamic> json) => OptionsZonePlan(
    zones: (json['zones'] as List<dynamic>)
        .map((zone) => OptionsZone.fromJson(Map<String, dynamic>.from(zone as Map)))
        .toList(),
    referencePrice: (json['referencePrice'] as num).toDouble(),
    middleStrike: (json['middleStrike'] as num?)?.toDouble()
        ?? (json['referencePrice'] as num).toDouble(),
    expiry: json['expiry'] as String?,
    sourceText: json['sourceText'] as String? ?? '',
    strikes: (json['strikes'] as List<dynamic>? ?? []).whereType<Map>().map((e) => OptionStrikeData.fromJson(Map<String, dynamic>.from(e))).toList(),
  );

  Map<String, dynamic> toJson() => {
    'zones': zones.map((z) => z.toJson()).toList(),
    'referencePrice': referencePrice,
    'middleStrike': middleStrike,
    'expiry': expiry,
    'sourceText': sourceText,
    'strikes': strikes.map((s) => s.toJson()).toList(),
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

    final text = lowerName.endsWith('.pdf')
        ? await _extractPdfText(bytes)
        : await _recognizeImage(bytes, file.path, name);
    if (text.trim().isEmpty) {
      throw const FormatException('No readable text was found. The original file has not replaced the previous saved file.');
    }

    // Keep the previous file and plan if this new file cannot be parsed.
    final plan = parseText(text);
    await _persistSourceFile(name, bytes);
    await saveApprovedPlan(plan);
    return plan;
  }

  Future<String> _extractPdfText(Uint8List bytes) async {
    final document = PdfDocument(inputBytes: bytes);
    String text;
    try {
      text = PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
    // Scanned PDFs usually have no text layer. Render each page and OCR it.
    if (text.trim().length >= 40) return text;
    final pdf = await pdfx.PdfDocument.openData(bytes);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final directory = await getTemporaryDirectory();
    final pageTexts = <String>[];
    try {
      for (var pageNumber = 1; pageNumber <= pdf.pagesCount; pageNumber++) {
        final page = await pdf.getPage(pageNumber);
        try {
          final rendered = await page.render(
            width: page.width * 2.2,
            height: page.height * 2.2,
            format: pdfx.PdfPageImageFormat.png,
          );
          if (rendered == null) continue;
          final imageFile = File('${directory.path}/iv_options_page_${DateTime.now().microsecondsSinceEpoch}_$pageNumber.png');
          try {
            await imageFile.writeAsBytes(rendered.bytes, flush: true);
            final recognized = await recognizer.processImage(InputImage.fromFilePath(imageFile.path));
            pageTexts.add('--- PAGE $pageNumber ---\\n${recognized.text}');
          } finally {
            if (await imageFile.exists()) await imageFile.delete();
          }
        } finally {
          await page.close();
        }
      }
    } finally {
      await recognizer.close();
      await pdf.close();
    }
    final ocrText = pageTexts.join('\\n');
    return ocrText.trim().length > text.trim().length ? ocrText : text;
  }

  Future<String> _recognizeImage(Uint8List bytes, String? existingPath, String name) async {
    final tempFile = existingPath == null
        ? File('${(await getTemporaryDirectory()).path}/iv_options_ocr_${DateTime.now().microsecondsSinceEpoch}_${name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}')
        : null;
    if (tempFile != null) await tempFile.writeAsBytes(bytes, flush: true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final path = existingPath ?? tempFile!.path;
      return (await recognizer.processImage(InputImage.fromFilePath(path))).text;
    } finally {
      await recognizer.close();
      if (tempFile != null && await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<String?> loadSavedSourcePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(sourcePathKey);
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
    final rows = <double, OptionStrikeData>{};
    final pattern = RegExp(r'[-+]?\d+(?:\.\d+)?%?');
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final tokens = pattern.allMatches(line).map((m) => m.group(0)!).toList();
      final vals = tokens.map((t) => double.tryParse(t.replaceAll('%', ''))).toList();
      final si = vals.indexWhere((v) => v != null && v >= 1000 && v <= 10000);
      if (si < 2 || si + 3 >= vals.length) continue;
      final left = vals.take(si).whereType<double>().toList(); final right = vals.skip(si + 1).whereType<double>().toList();
      if (left.length < 2 || right.length < 2) continue;
      final pd = left.first, pp = left.last, cp = right[0], cd = right[1];
      double? iv; for (var i=0;i<tokens.length;i++) { if(tokens[i].contains('%')) iv=double.tryParse(tokens[i].replaceAll('%','')); }
      if (iv == null && right.length > 2 && right.last >= 5 && right.last <= 150) iv=right.last;
      if (pd < 0 && pd >= -1.1 && cd > 0 && cd <= 1.1 && pp > 0 && cp > 0) rows[vals[si]!] = OptionStrikeData(strike: vals[si]!, putDelta: pd, putPrice: pp, callPrice: cp, callDelta: cd, impliedVolatility: iv);
    }
    final strikes = rows.values.toList()..sort((a,b)=>a.strike.compareTo(b.strike));
    if (strikes.length < 7) throw FormatException('Only ${strikes.length} complete option rows were parsed. Need seven rows with put delta/price, strike, call price/delta and IV. Try a clearer screenshot or text PDF.');
    final spotMatch=RegExp(r'(?:XAU\s*/?\s*USD|GOLD|SPOT)\D{0,30}(\d{4}(?:\.\d+)?)',caseSensitive:false).firstMatch(text);
    final spot=spotMatch==null?null:double.tryParse(spotMatch.group(1)!); final anchor=spot??strikes[strikes.length~/2].strike;
    final nearest=strikes.toList()..sort((a,b){final d=(a.strike-anchor).abs().compareTo((b.strike-anchor).abs());return d!=0?d:a.strike.compareTo(b.strike);});
    final selected=nearest.take(7).toList()..sort((a,b)=>a.strike.compareTo(b.strike)); final levels=selected.map((s)=>s.strike).toList(); final middle=levels[3];
    final zones=<OptionsZone>[OptionsZone(label:'R3',price:levels[6],isResistance:true),OptionsZone(label:'R2',price:levels[5],isResistance:true),OptionsZone(label:'R1',price:levels[4],isResistance:true),OptionsZone(label:'S1',price:levels[2],isResistance:false),OptionsZone(label:'S2',price:levels[1],isResistance:false),OptionsZone(label:'S3',price:levels[0],isResistance:false)];
    final expiry=RegExp(r'(?:expir(?:y|ing|ation)?\s*[: ]?\s*)(\d{4}[-/]\d{2}[-/]\d{2})',caseSensitive:false).firstMatch(text);
    return OptionsZonePlan(zones:zones,referencePrice:spot??middle,middleStrike:middle,expiry:expiry?.group(1),sourceText:text,strikes:selected);
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
