import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/esp_service.dart';
import 'models.dart';

class TimeTab extends StatefulWidget {
  const TimeTab({super.key});

  @override
  State<TimeTab> createState() => _TimeTabState();
}

class _TimeTabState extends State<TimeTab> {
  String _currentTime = '';
  EspTimeInfo _deviceTime = EspTimeInfo.empty();
  Timer? _clockTimer;
  StreamSubscription? _timeSubscription;
  StreamSubscription? _operationSubscription;

  @override
  void initState() {
    super.initState();
    _updateTime();
    // Update clock every second
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    final esp = context.read<EspService>();
    
    _timeSubscription = esp.timeStream.listen((info) {
      if (mounted) {
        setState(() {
          _deviceTime = info;
        });
      }
    });

    _operationSubscription = esp.operationStream.listen((msg) {
      if (mounted && msg.contains('SYNC_TIME')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zeit synchronisiert')),
        );
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _timeSubscription?.cancel();
    _operationSubscription?.cancel();
    super.dispose();
  }

  void _updateTime() {
    setState(() {
      _currentTime = DateTime.now().toString();
    });
  }

  void _copyTime() {
    Clipboard.setData(ClipboardData(text: _currentTime));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Zeit in Zwischenablage kopiert!')),
    );
  }

  void _syncTimeToDevice() {
    final esp = context.read<EspService>();
    if (!esp.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden'), backgroundColor: Colors.orange),
      );
      return;
    }

    final utcNow = DateTime.now().toUtc();
    esp.syncTime(utcNow);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Synchronisiere UTC: ${utcNow.toIso8601String()}')),
    );
  }

  void _fetchDeviceTime() {
    final esp = context.read<EspService>();
    if (!esp.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden'), backgroundColor: Colors.orange),
      );
      return;
    }

    esp.fetchDeviceTime();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gerätezeit wird abgefragt...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EspService>(
      builder: (context, esp, child) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Text(
                    'Zeit',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (!esp.isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Nicht verbunden'),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // PC Time
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PC Zeit',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.computer, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateTime.now().toLocal().toString().split('.')[0],
                                  style: const TextStyle(fontSize: 24, fontFamily: 'monospace'),
                                ),
                                Text(
                                  'UTC: ${DateTime.now().toUtc().toString().split('.')[0]}',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'Kopieren',
                            onPressed: _copyTime,
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Aktualisieren',
                            onPressed: _updateTime,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Device Time
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Gerätezeit',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const Spacer(),
                          if (_deviceTime.m5Available)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('M5 RTC verfügbar', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.developer_board, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_deviceTime.rtcTime.isNotEmpty) ...[
                                  Text(
                                    'RTC: ${_deviceTime.rtcTime}',
                                    style: const TextStyle(fontSize: 18, fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                if (_deviceTime.espTime.isNotEmpty)
                                  Text(
                                    'ESP: ${_deviceTime.espTime}',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                if (_deviceTime.localTime.isNotEmpty)
                                  Text(
                                    'Local: ${_deviceTime.localTime}',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                if (_deviceTime.rtcTime.isEmpty && 
                                    _deviceTime.espTime.isEmpty && 
                                    _deviceTime.localTime.isEmpty)
                                  Text(
                                    'Keine Daten - bitte abfragen',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.download),
                            tooltip: 'Gerätezeit abfragen',
                            onPressed: esp.isConnected ? _fetchDeviceTime : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Sync button
              Center(
                child: ElevatedButton.icon(
                  onPressed: esp.isConnected ? _syncTimeToDevice : null,
                  icon: const Icon(Icons.sync),
                  label: const Text('UTC Zeit zum Gerät synchronisieren'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(300, 48),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Info text
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Die Zeit wird automatisch beim Verbinden mit dem Gerät synchronisiert. '
                          'Die UTC-Zeit wird übertragen, das Gerät wendet seine konfigurierte Zeitzone an.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}