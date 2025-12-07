import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/esp_service.dart';
import 'utils/excel_exporter.dart';
import 'models.dart';

class DataTab extends StatefulWidget {
  const DataTab({super.key});

  @override
  State<DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<DataTab> {
  ExportConfig _exportConfig = ExportConfig.defaultConfig();
  bool _isExporting = false;
  
  final TextEditingController _folderController = TextEditingController();
  final TextEditingController _filenameController = TextEditingController();
  
  StreamSubscription? _downloadSubscription;
  StreamSubscription? _operationSubscription;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    final esp = context.read<EspService>();
    
    _downloadSubscription = esp.downloadStream.listen((path) {
      // Data file downloaded - process it
      if (_isExporting && esp.lastDownloadedData != null) {
        _processDownloadedData(esp.lastDownloadedData!);
      }
    });

    _operationSubscription = esp.operationStream.listen((msg) {
      if (mounted && msg.contains('heruntergeladen')) {
        // File downloaded notification
      }
    });
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _operationSubscription?.cancel();
    _folderController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await ExcelExporter.loadConfig();
    setState(() {
      _exportConfig = config;
      _folderController.text = config.exportFolder;
      _filenameController.text = config.filename;
    });
  }

  Future<void> _saveConfig() async {
    _exportConfig.exportFolder = _folderController.text.trim();
    _exportConfig.filename = _filenameController.text.trim();
    
    final success = await ExcelExporter.saveConfig(_exportConfig);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
              ? 'Export-Einstellungen gespeichert' 
              : 'Fehler beim Speichern'),
          backgroundColor: success ? null : Colors.red,
        ),
      );
    }
  }

  Future<void> _browseFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Export-Ordner wählen',
    );
    if (result != null) {
      setState(() {
        _folderController.text = result;
        _exportConfig.exportFolder = result;
      });
    }
  }

  Future<void> _exportData() async {
    final esp = context.read<EspService>();
    if (!esp.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_exportConfig.exportFolder.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte wählen Sie einen Export-Ordner'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isExporting = true);
    
    // Download data.csv from device
    // Use a temp path, we'll process when download completes
    esp.downloadFile('Data_jobs.csv', 'data_export_temp');
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Daten werden heruntergeladen...')),
    );
  }

  Future<void> _processDownloadedData(List<int> data) async {
    try {
      final csvContent = utf8.decode(data);
      
      // Update export config with current values
      _exportConfig.exportFolder = _folderController.text.trim();
      _exportConfig.filename = _filenameController.text.trim();
      
      final success = await ExcelExporter.exportWithConfig(csvContent, _exportConfig);
      
      if (mounted) {
        setState(() => _isExporting = false);
        
        if (success) {
          // Clear data on device after successful export
          final esp = context.read<EspService>();
          esp.clearCsvKeepHeader('Data_jobs.csv');
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export erfolgreich, Daten vom Gerät gelöscht'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export fehlgeschlagen'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openExportLocation() async {
    if (_exportConfig.exportFolder.isEmpty) return;
    
    String pathToOpen;
    if (_exportConfig.exportMode == 'single') {
      pathToOpen = '${_exportConfig.exportFolder}/${_exportConfig.filename}';
    } else {
      pathToOpen = _exportConfig.exportFolder;
    }
    
    final uri = Uri.file(pathToOpen);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Try opening folder
      final folderUri = Uri.file(_exportConfig.exportFolder);
      if (await canLaunchUrl(folderUri)) {
        await launchUrl(folderUri);
      }
    }
  }

  Future<void> _clearDeviceData() async {
    final esp = context.read<EspService>();
    if (!esp.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden'), backgroundColor: Colors.orange),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daten löschen'),
        content: const Text('Möchten Sie alle Daten auf dem Gerät löschen?\n\nDie Daten können nicht wiederhergestellt werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      esp.clearCsvKeepHeader('Data_jobs.csv');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daten werden gelöscht...')),
      );
    }
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
                    'Importieren',
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
              const SizedBox(height: 16),

              // Main action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (esp.isConnected && !_isExporting) ? _exportData : null,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: const Text('Importieren'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _exportConfig.exportFolder.isNotEmpty ? _openExportLocation : null,
                      icon: Icon(_exportConfig.exportMode == 'single' 
                          ? Icons.open_in_new 
                          : Icons.folder_open),
                      label: Text(_exportConfig.exportMode == 'single'
                          ? 'Exceldatei öffnen'
                          : 'Verzeichnis öffnen'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Export config
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Excel Export Optionen',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      
                      // Export mode
                      Row(
                        children: [
                          const Text('Export-Modus:'),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _exportConfig.exportMode,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'single', child: Text('Einzeldatei')),
                                DropdownMenuItem(value: 'multiple', child: Text('Mehrere Dateien')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _exportConfig.exportMode = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Export folder
                      Row(
                        children: [
                          const Text('Export-Ordner:'),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _folderController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _browseFolder,
                            child: const Text('Ordner wählen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Filename (only for single mode)
                      if (_exportConfig.exportMode == 'single') ...[
                        Row(
                          children: [
                            const Text('Dateiname:'),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _filenameController,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  hintText: 'export.xlsx',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      // Save button
                      ElevatedButton.icon(
                        onPressed: _saveConfig,
                        icon: const Icon(Icons.save),
                        label: const Text('Export-Einstellungen speichern'),
                      ),
                    ],
                  ),
                ),
              ),
              
              const Spacer(),
              
              // Danger zone
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text('Daten auf dem Gerät löschen (ohne Export)'),
                      ),
                      ElevatedButton(
                        onPressed: esp.isConnected ? _clearDeviceData : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Daten löschen'),
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