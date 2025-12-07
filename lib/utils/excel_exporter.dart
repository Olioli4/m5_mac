import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../models.dart';

/// Excel exporter utility for converting CSV data to Excel files
class ExcelExporter {
  /// Convert CSV content to Excel and save to the specified path
  static Future<bool> convertCsvToExcel(String csvContent, String xlsxPath) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      
      final rows = CsvParser.parseRaw(csvContent);
      
      // Header style
      final headerStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        backgroundColorHex: ExcelColor.fromHexString('#007ACC'),
        fontColorHex: ExcelColor.white,
      );
      
      for (var rowIdx = 0; rowIdx < rows.length; rowIdx++) {
        final row = rows[rowIdx];
        for (var colIdx = 0; colIdx < row.length; colIdx++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx));
          final value = row[colIdx];
          
          if (rowIdx == 0) {
            // Header row
            cell.value = TextCellValue(value);
            cell.cellStyle = headerStyle;
          } else {
            // Data rows - try to parse time values for columns 4, 5, 6 (start, end, duration)
            if (colIdx >= 4 && colIdx <= 6) {
              final timeValue = _parseTimeValue(value);
              if (timeValue != null) {
                cell.value = DoubleCellValue(timeValue);
                // Note: Excel package doesn't support number formats directly
                // The value is stored as Excel time fraction
              } else {
                cell.value = TextCellValue(value);
              }
            } else {
              // Try number, otherwise text
              final numValue = double.tryParse(value);
              if (numValue != null) {
                cell.value = DoubleCellValue(numValue);
              } else {
                cell.value = TextCellValue(value);
              }
            }
          }
        }
      }
      
      // Set column widths
      for (var i = 0; i < 7; i++) {
        sheet.setColumnWidth(i, 15);
      }
      
      // Save
      final bytes = excel.save();
      if (bytes != null) {
        final file = File(xlsxPath);
        await file.writeAsBytes(bytes);
        return true;
      }
      return false;
    } catch (e) {
      print('Excel export error: $e');
      return false;
    }
  }

  /// Append CSV data to an existing Excel file
  static Future<bool> appendCsvToExcel(String csvContent, String xlsxPath) async {
    try {
      final file = File(xlsxPath);
      if (!await file.exists()) {
        return convertCsvToExcel(csvContent, xlsxPath);
      }
      
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel['Sheet1'];
      
      // Find the last row
      int lastRow = sheet.maxRows;
      
      final rows = CsvParser.parseRaw(csvContent);
      
      // Skip header row when appending
      for (var rowIdx = 1; rowIdx < rows.length; rowIdx++) {
        final row = rows[rowIdx];
        final targetRow = lastRow + rowIdx - 1;
        
        for (var colIdx = 0; colIdx < row.length; colIdx++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: targetRow));
          final value = row[colIdx];
          
          // Same logic as convert
          if (colIdx >= 4 && colIdx <= 6) {
            final timeValue = _parseTimeValue(value);
            if (timeValue != null) {
              cell.value = DoubleCellValue(timeValue);
            } else {
              cell.value = TextCellValue(value);
            }
          } else {
            final numValue = double.tryParse(value);
            if (numValue != null) {
              cell.value = DoubleCellValue(numValue);
            } else {
              cell.value = TextCellValue(value);
            }
          }
        }
      }
      
      final savedBytes = excel.save();
      if (savedBytes != null) {
        await file.writeAsBytes(savedBytes);
        return true;
      }
      return false;
    } catch (e) {
      print('Excel append error: $e');
      return false;
    }
  }

  /// Export CSV data using the export configuration
  static Future<bool> exportWithConfig(String csvContent, ExportConfig config) async {
    try {
      // Extract machine name from first data row
      String machineName = 'Unknown';
      final rows = CsvParser.parseRaw(csvContent);
      if (rows.length > 1 && rows[1].isNotEmpty) {
        machineName = rows[1][0];
      }
      
      // Generate output filename
      String outputPath;
      if (config.exportMode == 'multiple') {
        final dateStr = DateTime.now().toIso8601String().split('T')[0];
        outputPath = '${config.exportFolder}/${machineName}_$dateStr.xlsx';
      } else {
        outputPath = '${config.exportFolder}/${config.filename}';
      }
      
      // Check if file exists and append or create
      final file = File(outputPath);
      bool success;
      if (await file.exists()) {
        success = await appendCsvToExcel(csvContent, outputPath);
      } else {
        success = await convertCsvToExcel(csvContent, outputPath);
      }
      
      return success;
    } catch (e) {
      print('Export with config error: $e');
      return false;
    }
  }

  /// Parse time string (H:MM:SS or HH:MM:SS) to Excel time fraction
  static double? _parseTimeValue(String value) {
    final parts = value.split(':');
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      final seconds = int.tryParse(parts[2]);
      
      if (hours != null && minutes != null && seconds != null &&
          hours >= 0 && minutes >= 0 && minutes < 60 && seconds >= 0 && seconds < 60) {
        // Excel time: fraction of day (1.0 = 24 hours)
        final totalSeconds = hours * 3600.0 + minutes * 60.0 + seconds;
        return totalSeconds / 86400.0;
      }
    } else if (parts.length == 2) {
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      
      if (hours != null && minutes != null && hours >= 0 && minutes >= 0 && minutes < 60) {
        final totalSeconds = hours * 3600.0 + minutes * 60.0;
        return totalSeconds / 86400.0;
      }
    }
    return null;
  }

  /// Get the app's config directory for storing export_config.json
  static Future<String> getConfigPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/m5_tool_export_config.json';
  }

  /// Load export configuration
  static Future<ExportConfig> loadConfig() async {
    try {
      final path = await getConfigPath();
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        return ExportConfig.fromJson(jsonDecode(content));
      }
    } catch (e) {
      print('Load config error: $e');
    }
    return ExportConfig.defaultConfig();
  }

  /// Save export configuration
  static Future<bool> saveConfig(ExportConfig config) async {
    try {
      final path = await getConfigPath();
      final file = File(path);
      await file.writeAsString(jsonEncode(config.toJson()));
      return true;
    } catch (e) {
      print('Save config error: $e');
      return false;
    }
  }
}
