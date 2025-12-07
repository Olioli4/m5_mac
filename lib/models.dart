import 'dart:convert';
import 'dart:io';

/// Type of file system entry
enum FileSystemEntryType {
  file,
  directory,
}

/// Represents a file or directory on the ESP32 flash storage
class FileSystemEntry {
  final String parentPath;
  final String name;
  final FileSystemEntryType type;
  final int size;

  FileSystemEntry({
    required this.parentPath,
    required this.name,
    required this.type,
    required this.size,
  });

  String get fullPath => '$parentPath/$name';

  bool get isDirectory => type == FileSystemEntryType.directory;
  bool get isFile => type == FileSystemEntryType.file;

  @override
  String toString() => 'FileSystemEntry($name, $type, $size bytes)';
}

/// ESP32 device configuration
class EspConfig {
  final String boardSerial;
  final String machine;
  final String lastUpdated;
  final List<String> drivers;
  final List<String> jobs;

  EspConfig({
    required this.boardSerial,
    required this.machine,
    required this.lastUpdated,
    required this.drivers,
    required this.jobs,
  });

  factory EspConfig.empty() => EspConfig(
        boardSerial: '',
        machine: '',
        lastUpdated: '',
        drivers: [],
        jobs: [],
      );

  EspConfig copyWith({
    String? boardSerial,
    String? machine,
    String? lastUpdated,
    List<String>? drivers,
    List<String>? jobs,
  }) {
    return EspConfig(
      boardSerial: boardSerial ?? this.boardSerial,
      machine: machine ?? this.machine,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      drivers: drivers ?? List.from(this.drivers),
      jobs: jobs ?? List.from(this.jobs),
    );
  }

  Map<String, dynamic> toJson() => {
        'board_serial': boardSerial,
        'Machine': machine,
        'last_updated': lastUpdated,
        'Driver': drivers,
        'Jobs': jobs,
      };

  factory EspConfig.fromJson(Map<String, dynamic> json) {
    return EspConfig(
      boardSerial: json['board_serial'] as String? ?? '',
      machine: json['Machine'] as String? ?? '',
      lastUpdated: json['last_updated'] as String? ?? '',
      drivers: (json['Driver'] as List<dynamic>?)?.cast<String>() ?? [],
      jobs: (json['Jobs'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  @override
  String toString() => 'EspConfig(machine: $machine, serial: $boardSerial)';
}

/// ESP32 time information
class EspTimeInfo {
  final String espTime;
  final String rtcTime;
  final String localTime;
  final bool m5Available;

  EspTimeInfo({
    required this.espTime,
    required this.rtcTime,
    required this.localTime,
    required this.m5Available,
  });

  factory EspTimeInfo.empty() => EspTimeInfo(
        espTime: '',
        rtcTime: '',
        localTime: '',
        m5Available: false,
      );

  @override
  String toString() =>
      'EspTimeInfo(rtc: $rtcTime, esp: $espTime, local: $localTime)';
}

/// Export configuration for data export
class ExportConfig {
  String exportMode; // 'single' or 'multiple'
  String exportFolder;
  String filename;

  ExportConfig({
    required this.exportMode,
    required this.exportFolder,
    required this.filename,
  });

  factory ExportConfig.defaultConfig() => ExportConfig(
        exportMode: 'single',
        exportFolder: '',
        filename: 'export.xlsx',
      );

  factory ExportConfig.fromJson(Map<String, dynamic> json) {
    return ExportConfig(
      exportMode: json['exportMode'] as String? ?? 'single',
      exportFolder: json['exportFolder'] as String? ?? '',
      filename: json['filename'] as String? ?? 'export.xlsx',
    );
  }

  Map<String, dynamic> toJson() => {
        'exportMode': exportMode,
        'exportFolder': exportFolder,
        'filename': filename,
      };

  /// Load config from file
  static Future<ExportConfig> load(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        return ExportConfig.fromJson(jsonDecode(content));
      }
    } catch (e) {
      // Return default if load fails
    }
    return ExportConfig.defaultConfig();
  }

  /// Save config to file
  Future<bool> save(String path) async {
    try {
      final file = File(path);
      await file.writeAsString(jsonEncode(toJson()));
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// CSV data row from the device
class DataRow {
  final String machine;
  final String driver;
  final String job;
  final String date;
  final String startTime;
  final String endTime;
  final String duration;

  DataRow({
    required this.machine,
    required this.driver,
    required this.job,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });

  factory DataRow.fromCsvLine(String line) {
    final parts = line.split(',');
    return DataRow(
      machine: parts.isNotEmpty ? parts[0].trim() : '',
      driver: parts.length > 1 ? parts[1].trim() : '',
      job: parts.length > 2 ? parts[2].trim() : '',
      date: parts.length > 3 ? parts[3].trim() : '',
      startTime: parts.length > 4 ? parts[4].trim() : '',
      endTime: parts.length > 5 ? parts[5].trim() : '',
      duration: parts.length > 6 ? parts[6].trim() : '',
    );
  }

  List<String> toList() => [
        machine,
        driver,
        job,
        date,
        startTime,
        endTime,
        duration,
      ];

  @override
  String toString() => '$machine,$driver,$job,$date,$startTime,$endTime,$duration';
}

/// Parse CSV content into DataRows
class CsvParser {
  static List<DataRow> parse(String csvContent) {
    final lines = csvContent.split('\n');
    final rows = <DataRow>[];
    
    // Skip header line
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        rows.add(DataRow.fromCsvLine(line));
      }
    }
    
    return rows;
  }

  static List<List<String>> parseRaw(String csvContent) {
    return csvContent
        .split('\n')
        .map((line) => line.split(',').map((e) => e.trim()).toList())
        .where((row) => row.isNotEmpty && row.first.isNotEmpty)
        .toList();
  }
}
