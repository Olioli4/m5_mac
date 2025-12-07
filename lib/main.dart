import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/esp_service.dart';
import 'config_tab.dart';
import 'data_tab.dart';
import 'files_tab.dart';
import 'serial_terminal_tab.dart';
import 'time_tab.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => EspService(),
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _selectedIndex = 0;
  final List<Widget> _tabs = const [
    DataTab(),
    ConfigTab(),
    FilesTab(),
    SerialTerminalTab(),
    TimeTab(),
  ];

  final List<String> _tabLabels = const [
    'Importieren',
    'Konfiguration',
    'Speicher',
    'Terminal',
    'Zeit',
  ];

  final List<IconData> _tabIcons = const [
    Icons.download,
    Icons.settings,
    Icons.folder,
    Icons.terminal,
    Icons.access_time,
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M5Stack Tough Kommunikationstool',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('M5Stack Tough Kommunikationstool'),
          actions: const [
            ConnectionWidget(),
          ],
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (var i = 0; i < _tabLabels.length; i++)
                  NavigationRailDestination(
                    icon: Icon(_tabIcons[i]),
                    selectedIcon: Icon(_tabIcons[i], color: Theme.of(context).colorScheme.primary),
                    label: Text(_tabLabels[i]),
                  ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _tabs[_selectedIndex]),
                  const StatusBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Connection widget shown in the app bar
class ConnectionWidget extends StatefulWidget {
  const ConnectionWidget({super.key});

  @override
  State<ConnectionWidget> createState() => _ConnectionWidgetState();
}

class _ConnectionWidgetState extends State<ConnectionWidget> {
  String? _selectedPort;
  List<String> _ports = [];
  StreamSubscription? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _refreshPorts();
    
    // Listen for errors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final esp = context.read<EspService>();
      _errorSubscription = esp.errorStream.listen((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    super.dispose();
  }

  void _refreshPorts() {
    final esp = context.read<EspService>();
    setState(() {
      _ports = esp.availablePorts;
      if (_ports.isNotEmpty && _selectedPort == null) {
        _selectedPort = _ports.first;
      }
    });
  }

  Future<void> _toggleConnection() async {
    final esp = context.read<EspService>();
    
    if (esp.isConnected) {
      await esp.disconnect();
    } else if (_selectedPort != null) {
      final success = await esp.connect(_selectedPort!);
      if (success) {
        // Wait for connection to be established
        await Future.delayed(const Duration(milliseconds: 600));
        if (esp.isConnected) {
          esp.initializeDevice();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EspService>(
      builder: (context, esp, child) {
        final isConnected = esp.isConnected;
        final isConnecting = esp.state == EspConnectionState.connecting;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Port dropdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: DropdownButton<String>(
                value: _selectedPort,
                hint: const Text('Anschluss wählen'),
                items: _ports.map((port) {
                  return DropdownMenuItem(
                    value: port,
                    child: Text(esp.getPortDescription(port)),
                  );
                }).toList(),
                onChanged: isConnected ? null : (value) {
                  setState(() {
                    _selectedPort = value;
                  });
                },
              ),
            ),
            // Refresh button
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Anschlüsse aktualisieren',
              onPressed: isConnected ? null : _refreshPorts,
            ),
            // Connect button
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ElevatedButton.icon(
                onPressed: (_selectedPort == null && !isConnected) || isConnecting
                    ? null
                    : _toggleConnection,
                icon: isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(isConnected ? Icons.link_off : Icons.link),
                label: Text(isConnected ? 'Trennen' : 'Verbinden'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected ? Colors.green : null,
                  foregroundColor: isConnected ? Colors.white : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Status bar at the bottom of the window
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EspService>(
      builder: (context, esp, child) {
        final stateIcon = switch (esp.state) {
          EspConnectionState.connected => Icons.check_circle,
          EspConnectionState.connecting => Icons.sync,
          EspConnectionState.disconnected => Icons.cancel,
        };
        
        final stateColor = switch (esp.state) {
          EspConnectionState.connected => Colors.green,
          EspConnectionState.connecting => Colors.orange,
          EspConnectionState.disconnected => Colors.grey,
        };

        return Container(
          height: 28,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(stateIcon, size: 16, color: stateColor),
              const SizedBox(width: 8),
              Text(
                esp.statusMessage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              if (esp.currentPortName != null)
                Text(
                  esp.currentPortName!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        );
      },
    );
  }
}
