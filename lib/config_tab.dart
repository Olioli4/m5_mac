import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/esp_service.dart';
import 'models.dart';

class ConfigTab extends StatefulWidget {
  const ConfigTab({super.key});

  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  final TextEditingController _machineController = TextEditingController();
  String _lastUpdated = 'Nie';
  String _serial = 'Wird automatisch abgerufen...';
  List<String> _drivers = [];
  List<String> _jobs = [];
  
  StreamSubscription? _configSubscription;
  StreamSubscription? _serialSubscription;
  StreamSubscription? _operationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    final esp = context.read<EspService>();
    
    _configSubscription = esp.configStream.listen((config) {
      if (mounted) {
        setState(() {
          _machineController.text = config.machine;
          _lastUpdated = config.lastUpdated.isEmpty ? 'Nie' : config.lastUpdated;
          if (config.boardSerial.isNotEmpty) {
            _serial = config.boardSerial;
          }
          _drivers = List.from(config.drivers);
          _jobs = List.from(config.jobs);
        });
      }
    });

    _serialSubscription = esp.serialStream.listen((serial) {
      if (mounted && serial.isNotEmpty) {
        setState(() {
          _serial = serial;
        });
      }
    });

    _operationSubscription = esp.operationStream.listen((msg) {
      if (mounted && msg.contains('ACK')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    });
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    _serialSubscription?.cancel();
    _operationSubscription?.cancel();
    _machineController.dispose();
    super.dispose();
  }

  void _loadConfig() {
    final esp = context.read<EspService>();
    if (esp.isConnected) {
      esp.readConfig();
      esp.getBoardSerial();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden'), backgroundColor: Colors.orange),
      );
    }
  }

  void _saveConfig() {
    final esp = context.read<EspService>();
    if (!esp.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden'), backgroundColor: Colors.orange),
      );
      return;
    }

    final config = EspConfig(
      boardSerial: _serial,
      machine: _machineController.text.trim(),
      lastUpdated: DateTime.now().toUtc().toIso8601String(),
      drivers: _drivers,
      jobs: _jobs,
    );

    esp.writeConfig(config);
    
    setState(() {
      _lastUpdated = config.lastUpdated;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Konfiguration wird gespeichert...')),
    );
  }

  void _addToList(List<String> list, void Function(List<String>) update, String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eintrag hinzufügen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name:'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      final newList = List<String>.from(list)..add(result.trim());
      update(newList);
    }
  }

  void _renameInList(List<String> list, void Function(List<String>) update, int index) async {
    final controller = TextEditingController(text: list[index]);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eintrag umbenennen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name:'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      final newList = List<String>.from(list);
      newList[index] = result.trim();
      update(newList);
    }
  }

  void _deleteFromList(List<String> list, void Function(List<String>) update, int index) {
    final newList = List<String>.from(list)..removeAt(index);
    update(newList);
  }

  Widget _buildListManager(String title, List<String> items, void Function(List<String>) update) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'Keine Einträge',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: items.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex--;
                        final newList = List<String>.from(items);
                        final item = newList.removeAt(oldIndex);
                        newList.insert(newIndex, item);
                        update(newList);
                      },
                      itemBuilder: (context, index) {
                        return ListTile(
                          key: ValueKey('$title-$index-${items[index]}'),
                          title: Text(items[index]),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                tooltip: 'Umbenennen',
                                onPressed: () => _renameInList(items, update, index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                tooltip: 'Löschen',
                                onPressed: () => _deleteFromList(items, update, index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _addToList(items, update, title),
              icon: const Icon(Icons.add),
              label: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EspService>(
      builder: (context, esp, child) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Text(
                      'Konfiguration',
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

                // General Info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Allgemeine Informationen',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _machineController,
                          decoration: const InputDecoration(
                            labelText: 'Maschine',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Zuletzt aktualisiert: '),
                            Text(_lastUpdated, style: const TextStyle(fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Seriennummer: '),
                            SelectableText(_serial, style: const TextStyle(fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Lists
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildListManager(
                        'Fahrer',
                        _drivers,
                        (list) => setState(() => _drivers = list),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildListManager(
                        'Aufträge',
                        _jobs,
                        (list) => setState(() => _jobs = list),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: esp.isConnected ? _loadConfig : null,
                      icon: const Icon(Icons.download),
                      label: const Text('Vom Gerät neu laden'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: esp.isConnected ? _saveConfig : null,
                      icon: const Icon(Icons.upload),
                      label: const Text('Auf Gerät speichern'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}