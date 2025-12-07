import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'services/esp_service.dart';
import 'models.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({super.key});

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  List<FileSystemEntry> _files = [];
  bool _isLoading = false;
  StreamSubscription? _fileListSubscription;
  StreamSubscription? _operationSubscription;
  StreamSubscription? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    final esp = context.read<EspService>();
    
    _fileListSubscription = esp.fileListStream.listen((files) {
      if (mounted) {
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    });

    _operationSubscription = esp.operationStream.listen((msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        // Refresh file list after operations
        if (msg.contains('uploaded') || msg.contains('deleted')) {
          _refreshFiles();
        }
      }
    });

    _downloadSubscription = esp.downloadStream.listen((path) async {
      if (mounted) {
        final data = esp.lastDownloadedData;
        if (data != null) {
          try {
            final file = File(path);
            await file.writeAsBytes(data);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Datei gespeichert: $path')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Fehler beim Speichern: $e'), backgroundColor: Colors.red),
              );
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _fileListSubscription?.cancel();
    _operationSubscription?.cancel();
    _downloadSubscription?.cancel();
    super.dispose();
  }

  void _refreshFiles() {
    final esp = context.read<EspService>();
    if (esp.isConnected) {
      setState(() => _isLoading = true);
      esp.listFiles();
    }
  }

  Future<void> _uploadFile() async {
    final esp = context.read<EspService>();
    if (!esp.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final remoteName = result.files.single.name;
        
        setState(() => _isLoading = true);
        esp.uploadFile(remoteName, bytes);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lade hoch: $remoteName')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadFile(FileSystemEntry file) async {
    final esp = context.read<EspService>();
    if (!esp.isConnected) return;

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Datei speichern unter',
      fileName: file.name,
    );

    if (savePath != null) {
      // Strip /flash/ prefix
      String remoteName = file.name;
      if (file.fullPath.startsWith('/flash/')) {
        remoteName = file.fullPath.substring(7);
      }
      
      esp.downloadFile(remoteName, savePath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lade herunter: ${file.name}')),
      );
    }
  }

  Future<void> _deleteFile(FileSystemEntry file) async {
    final esp = context.read<EspService>();
    if (!esp.isConnected) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Löschen bestätigen'),
        content: Text('Möchten Sie "${file.name}" löschen?'),
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
      // Strip /flash/ prefix
      String remoteName = file.name;
      if (file.fullPath.startsWith('/flash/')) {
        remoteName = file.fullPath.substring(7);
      }
      
      esp.deleteFile(remoteName);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
                    'Speicher',
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
              
              // Action buttons
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: esp.isConnected ? _refreshFiles : null,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Liste aktualisieren'),
                  ),
                  ElevatedButton.icon(
                    onPressed: esp.isConnected ? _uploadFile : null,
                    icon: const Icon(Icons.upload),
                    label: const Text('Datei hochladen'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // File list
              Expanded(
                child: Card(
                  child: _files.isEmpty
                      ? Center(
                          child: Text(
                            esp.isConnected
                                ? 'Keine Dateien gefunden'
                                : 'Bitte verbinden Sie sich mit dem Gerät',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            final file = _files[index];
                            return ListTile(
                              leading: Icon(
                                file.isDirectory ? Icons.folder : Icons.insert_drive_file,
                                color: file.isDirectory ? Colors.amber : Colors.blue,
                              ),
                              title: Text(file.name),
                              subtitle: Text(_formatSize(file.size)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (file.isFile)
                                    IconButton(
                                      icon: const Icon(Icons.download),
                                      tooltip: 'Herunterladen',
                                      onPressed: () => _downloadFile(file),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'Löschen',
                                    onPressed: () => _deleteFile(file),
                                  ),
                                ],
                              ),
                              onTap: file.isFile ? () => _downloadFile(file) : null,
                            );
                          },
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