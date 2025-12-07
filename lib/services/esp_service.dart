import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../models.dart';

/// Connection state for the ESP device
enum EspConnectionState {
  disconnected,
  connecting,
  connected,
}

/// Central service for ESP32 communication
/// Implements the JSON protocol matching the Qt/C++ version
class EspService extends ChangeNotifier {
  static final EspService _instance = EspService._internal();
  factory EspService() => _instance;
  EspService._internal();

  // Connection state
  EspConnectionState _state = EspConnectionState.disconnected;
  EspConnectionState get state => _state;
  bool get isConnected => _state == EspConnectionState.connected;

  // Serial port
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;
  String? _currentPortName;
  String? get currentPortName => _currentPortName;

  // Buffers and timing
  String _rxBuffer = '';
  DateTime? _lastPongTime;
  Timer? _heartbeatTimer;
  Timer? _connectionTimer;

  // Timeouts (matching Qt version)
  static const Duration connectionTimeout = Duration(milliseconds: 5000);
  static const Duration heartbeatInterval = Duration(milliseconds: 3000);
  static const Duration pongTimeout = Duration(milliseconds: 10000);

  // Pending download path for file downloads
  String? _pendingDownloadPath;
  Uint8List? _lastDownloadedData;
  Uint8List? get lastDownloadedData => _lastDownloadedData;

  // Output log for terminal
  final List<String> _output = [];
  List<String> get output => List.unmodifiable(_output);

  // Status message
  String _statusMessage = 'Bereit';
  String get statusMessage => _statusMessage;

  // Callbacks for specific message types
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Event streams
  final _fileListController = StreamController<List<FileSystemEntry>>.broadcast();
  Stream<List<FileSystemEntry>> get fileListStream => _fileListController.stream;

  final _configController = StreamController<EspConfig>.broadcast();
  Stream<EspConfig> get configStream => _configController.stream;

  final _serialController = StreamController<String>.broadcast();
  Stream<String> get serialStream => _serialController.stream;

  final _timeController = StreamController<EspTimeInfo>.broadcast();
  Stream<EspTimeInfo> get timeStream => _timeController.stream;

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  final _operationController = StreamController<String>.broadcast();
  Stream<String> get operationStream => _operationController.stream;

  final _downloadController = StreamController<String>.broadcast();
  Stream<String> get downloadStream => _downloadController.stream;

  /// Get available serial ports (platform-aware)
  /// On macOS: filters for /dev/cu.* ports (outgoing connections)
  /// On Windows: returns COM ports
  /// On Linux: returns /dev/ttyUSB* and /dev/ttyACM* ports
  List<String> get availablePorts {
    final allPorts = SerialPort.availablePorts;
    
    if (Platform.isMacOS) {
      // On macOS, prefer cu.* ports over tty.* for outgoing connections
      // Filter out Bluetooth ports
      return allPorts.where((port) =>
        port.startsWith('/dev/cu.') && 
        !port.contains('Bluetooth') &&
        !port.contains('debug')
      ).toList();
    } else if (Platform.isLinux) {
      // On Linux, filter for USB serial ports
      return allPorts.where((port) =>
        port.startsWith('/dev/ttyUSB') || 
        port.startsWith('/dev/ttyACM')
      ).toList();
    }
    
    // Windows: return all ports (COM*)
    return allPorts;
  }

  /// Get port description
  String getPortDescription(String portName) {
    try {
      final port = SerialPort(portName);
      final desc = port.description ?? '';
      port.dispose();
      return desc.isNotEmpty ? '$portName ($desc)' : portName;
    } catch (e) {
      return portName;
    }
  }

  /// Connect to a serial port
  Future<bool> connect(String portName) async {
    if (_state != EspConnectionState.disconnected) {
      await disconnect();
    }

    _currentPortName = portName;
    _port = SerialPort(portName);

    // Open port first
    if (!_port!.openReadWrite()) {
      final lastError = SerialPort.lastError;
      _setStatus('Fehler beim Öffnen von $portName: $lastError');
      _errorController.add('Fehler beim Öffnen von $portName: $lastError');
      debugPrint('[ESP] Failed to open port: $lastError');
      return false;
    }

    // Configure serial port AFTER opening (matching Qt version: 115200 8N1)
    try {
      final config = _port!.config;
      config.baudRate = 115200;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      
      // DTR/RTS handling differs by platform
      if (Platform.isMacOS || Platform.isLinux) {
        // On Unix systems, don't toggle DTR to avoid resetting the device
        config.dtr = SerialPortDtr.off;
        config.rts = SerialPortRts.off;
      } else {
        // On Windows, use DTR to signal connection
        config.dtr = SerialPortDtr.on;
        config.rts = SerialPortRts.off;
      }
      
      _port!.config = config;
    } catch (e) {
      debugPrint('[ESP] Failed to set config: $e');
    }

    _rxBuffer = '';
    _output.clear();
    _setState(EspConnectionState.connecting);
    _setStatus('Verbinde mit $portName...');

    // Start connection timeout
    _connectionTimer?.cancel();
    _connectionTimer = Timer(connectionTimeout, _onConnectionTimeout);

    // Start reading
    _reader = SerialPortReader(_port!);
    _subscription = _reader!.stream.listen(
      _onDataReceived,
      onError: (error) {
        debugPrint('[ESP] Read error: $error');
        _errorController.add('Lesefehler: $error');
        disconnect();
      },
    );

    // Wait for ESP32 boot (DTR toggle causes reset on many boards)
    // ESP32 outputs boot messages at 74880 baud, which appear as garbage at 115200
    await Future.delayed(const Duration(milliseconds: 1000));
    _rxBuffer = ''; // Clear boot noise
    _output.clear();

    // Send handshake
    _sendHandshake();

    notifyListeners();
    return true;
  }

  /// Disconnect from the serial port
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectionTimer?.cancel();
    _connectionTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    _reader?.close();
    _reader = null;

    _port?.close();
    _port = null;

    _rxBuffer = '';
    _currentPortName = null;
    _setState(EspConnectionState.disconnected);
    _setStatus('Getrennt');
    notifyListeners();
  }

  void _setState(EspConnectionState newState) {
    if (_state == newState) return;

    _state = newState;

    switch (newState) {
      case EspConnectionState.disconnected:
        _heartbeatTimer?.cancel();
        _connectionTimer?.cancel();
        break;
      case EspConnectionState.connecting:
        // Timer already started in connect()
        break;
      case EspConnectionState.connected:
        _connectionTimer?.cancel();
        _lastPongTime = DateTime.now();
        _startHeartbeat();
        break;
    }

    notifyListeners();
  }

  void _setStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void _onConnectionTimeout() {
    if (_state == EspConnectionState.connecting) {
      _errorController.add('Verbindungstimeout - keine Antwort vom Gerät');
      disconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_state != EspConnectionState.connected) return;

      final now = DateTime.now();
      final elapsed = now.difference(_lastPongTime ?? now);

      if (elapsed > pongTimeout) {
        debugPrint('[Heartbeat] TIMEOUT - disconnecting');
        _errorController.add('Verbindung verloren - keine Antwort vom Gerät');
        disconnect();
        return;
      }

      debugPrint('[Heartbeat] Sending PING');
      sendPing();
    });
  }

  void _onDataReceived(Uint8List data) {
    final text = utf8.decode(data, allowMalformed: true);
    
    // Filter out non-printable characters (boot garbage)
    final cleanText = text.replaceAll(RegExp(r'[^\x20-\x7E\n\r\t]'), '');
    
    if (cleanText.isNotEmpty) {
      debugPrint('[SERIAL IN] $cleanText');
      _output.add(cleanText);
    }
    
    _rxBuffer += text;
    _processBuffer();
    _lastPongTime = DateTime.now();
    notifyListeners();
  }

  void _processBuffer() {
    while (_rxBuffer.contains('\n')) {
      final idx = _rxBuffer.indexOf('\n');
      final line = _rxBuffer.substring(0, idx).trim();
      _rxBuffer = _rxBuffer.substring(idx + 1);

      if (line.isEmpty) continue;

      debugPrint('[RX] Complete line: $line');

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        _handleMessage(json);
      } catch (e) {
        debugPrint('[RX] JSON parse error: $e');
      }
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    debugPrint('[RX] Message type: $type');

    _messageController.add(msg);

    switch (type) {
      case 'HANDSHAKE':
        if (msg['device'] == 'ESP32') {
          if (_state != EspConnectionState.connected) {
            debugPrint('[RX] Handshake accepted, transitioning to CONNECTED');
            _setState(EspConnectionState.connected);
            _setStatus('Verbunden');
            _operationController.add('Handshake abgeschlossen: ${msg['device']}');
          }
          _lastPongTime = DateTime.now();
        }
        break;

      case 'PONG':
        _lastPongTime = DateTime.now();
        debugPrint('[RX] PONG received');
        break;

      case 'ACK':
        _operationController.add('ACK: ${msg['cmd']}');
        break;

      case 'NAK':
        _errorController.add('NAK: ${msg['cmd']} (${msg['error_msg']})');
        break;

      case 'ERROR':
        _errorController.add('Fehler: ${msg['error_msg']}');
        break;

      case 'SERIAL':
        _serialController.add(msg['serial'] as String? ?? '');
        _setStatus('Seriennummer abgerufen');
        break;

      case 'FILE_LIST':
        final files = <FileSystemEntry>[];
        final arr = msg['files'] as List<dynamic>? ?? [];
        for (final item in arr) {
          if (item is Map<String, dynamic>) {
            files.add(FileSystemEntry(
              parentPath: '/flash',
              name: item['name'] as String? ?? '',
              type: (item['type'] as String?) == 'dir'
                  ? FileSystemEntryType.directory
                  : FileSystemEntryType.file,
              size: item['size'] as int? ?? 0,
            ));
          } else if (item is String) {
            files.add(FileSystemEntry(
              parentPath: '/flash',
              name: item,
              type: FileSystemEntryType.file,
              size: 0,
            ));
          }
        }
        _fileListController.add(files);
        _setStatus('Dateiliste aktualisiert');
        break;

      case 'CONFIG':
        final cfg = msg['config'] as Map<String, dynamic>? ?? {};
        final config = EspConfig(
          boardSerial: cfg['board_serial'] as String? ?? '',
          machine: cfg['Machine'] as String? ?? '',
          lastUpdated: cfg['last_updated'] as String? ?? '',
          drivers: (cfg['Driver'] as List<dynamic>?)?.cast<String>() ?? [],
          jobs: (cfg['Jobs'] as List<dynamic>?)?.cast<String>() ?? [],
        );
        _configController.add(config);
        _setStatus('Konfiguration geladen');
        break;

      case 'TIME':
        final info = EspTimeInfo(
          rtcTime: msg['rtc'] as String? ?? '',
          espTime: msg['esp'] as String? ?? '',
          localTime: msg['local'] as String? ?? '',
          m5Available: msg['m5_available'] as bool? ?? false,
        );
        _timeController.add(info);
        _setStatus('Gerätezeit aktualisiert');
        break;

      case 'FILE_DATA':
        final hexdata = msg['hexdata'] as String? ?? '';
        if (_pendingDownloadPath != null && hexdata.isNotEmpty) {
          _lastDownloadedData = _hexToBytes(hexdata);
          _downloadController.add(_pendingDownloadPath!);
          _operationController.add('Datei heruntergeladen: $_pendingDownloadPath');
          _pendingDownloadPath = null;
        }
        break;

      case 'STATUS':
        final status = msg['status'] as String?;
        if (status == 'disconnected' && _state == EspConnectionState.connected) {
          _errorController.add('Gerät hat Trennung gemeldet');
          disconnect();
        }
        break;
    }
  }

  // --- Command methods ---

  void _sendJson(Map<String, dynamic> obj) {
    if (_port == null || !_port!.isOpen) return;

    final cmd = '${jsonEncode(obj)}\n';
    debugPrint('[SERIAL OUT] $cmd');
    _port!.write(Uint8List.fromList(utf8.encode(cmd)));
    _output.add('> $cmd');
    notifyListeners();
  }

  void _sendHandshake() {
    _sendJson({
      'type': 'HANDSHAKE',
      'device': 'FlutterApp',
      'version': 1,
    });
  }

  void sendPing() {
    _sendJson({'type': 'PING'});
  }

  void listFiles() {
    _sendJson({'type': 'LIST_FILES'});
  }

  void uploadFile(String remoteFilename, Uint8List data) {
    _sendJson({
      'type': 'UPLOAD_FILE',
      'filename': remoteFilename,
      'hexdata': _bytesToHex(data),
    });
  }

  void downloadFile(String remoteFilename, String localPath) {
    _pendingDownloadPath = localPath;
    _sendJson({
      'type': 'DOWNLOAD_FILE',
      'filename': remoteFilename,
    });
  }

  void deleteFile(String remoteFilename) {
    _sendJson({
      'type': 'DELETE_FILE',
      'filename': remoteFilename,
    });
  }

  void readConfig() {
    _sendJson({'type': 'READ_CONFIG'});
  }

  void writeConfig(EspConfig config) {
    _sendJson({
      'type': 'WRITE_CONFIG',
      'config': {
        'board_serial': config.boardSerial,
        'Machine': config.machine,
        'last_updated': config.lastUpdated,
        'Driver': config.drivers,
        'Jobs': config.jobs,
      },
    });
  }

  void getBoardSerial() {
    _sendJson({'type': 'GET_SERIAL'});
  }

  void fetchDeviceTime() {
    _sendJson({'type': 'FETCH_TIME'});
  }

  void syncTime(DateTime dateTime) {
    debugPrint('[ESP] Syncing time: ${dateTime.toIso8601String()}');
    _sendJson({
      'type': 'SYNC_TIME',
      'time': '${dateTime.year},${dateTime.month},${dateTime.day},'
          '${dateTime.hour},${dateTime.minute},${dateTime.second}',
    });
  }

  void clearCsvKeepHeader(String filename) {
    _sendJson({
      'type': 'CLEAR_CSV',
      'filename': filename,
    });
  }

  /// Send raw text (for terminal)
  void sendRaw(String text) {
    if (_port == null || !_port!.isOpen) return;
    final cmd = text.endsWith('\n') ? text : '$text\n';
    debugPrint('[SERIAL OUT] $cmd');
    _port!.write(Uint8List.fromList(utf8.encode(cmd)));
    _output.add('> $cmd');
    notifyListeners();
  }

  // --- Utility methods ---

  String _bytesToHex(Uint8List data) {
    return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  /// Initialize device after connection (called automatically)
  void initializeDevice() {
    if (!isConnected) return;

    // Sync UTC time on initialization
    final utcNow = DateTime.now().toUtc();
    debugPrint('[ESP] Initialization - syncing UTC time: ${utcNow.toIso8601String()}');
    syncTime(utcNow);

    // Request initial data
    listFiles();
    readConfig();
    getBoardSerial();
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    _fileListController.close();
    _configController.close();
    _serialController.close();
    _timeController.close();
    _errorController.close();
    _operationController.close();
    _downloadController.close();
    super.dispose();
  }
}
