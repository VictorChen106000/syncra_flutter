import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Extracts raw text from a PDF on disk or in memory. Used by the resume
/// parser as a pre-step before sending text to Claude.
class ResumePdfTextExtractor {
  const ResumePdfTextExtractor();

  /// Reads [filePath] as a PDF and returns its concatenated text. Returns
  /// an empty string if the file is missing, unreadable, or contains only
  /// scanned images (no embedded text).
  Future<String> extractFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      final bytes = await file.readAsBytes();
      return extractFromBytes(bytes);
    } catch (e) {
      debugPrint('pdf text extraction failed: $e');
      return '';
    }
  }

  /// Returns the concatenated text inside [bytes].
  String extractFromBytes(Uint8List bytes) {
    syncfusion.PdfDocument? document;
    try {
      document = syncfusion.PdfDocument(inputBytes: bytes);
      final extractor = syncfusion.PdfTextExtractor(document);
      return extractor.extractText().trim();
    } catch (e) {
      debugPrint('pdf text extraction failed: $e');
      return '';
    } finally {
      document?.dispose();
    }
  }
}
