import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/esp_service.dart';

class SerialTerminalTab extends StatefulWidget {
  const SerialTerminalTab({super.key});

  @override
  State<SerialTerminalTab> createState() => _SerialTerminalTabState();
}

class _SerialTerminalTabState extends State<SerialTerminalTab> {
  final TextEditingController _sendController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<String> _output = [];
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    final esp = context.read<EspService>();
    
    // Listen for all messages and update output
    _messageSubscription = esp.messageStream.listen((_) {
      if (mounted) {
        setState(() {
          _output = esp.output;
        });
        _scrollToBottom();
      }
    });
    
    // Initial output
    setState(() {
      _output = esp.output;
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _sendController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final esp = context.read<EspService>();
    if (!esp.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden'), backgroundColor: Colors.orange),
      );
      return;
    }

    final text = _sendController.text;
    if (text.isNotEmpty) {
      esp.sendRaw(text);
      _sendController.clear();
      setState(() {
        _output = esp.output;
      });
      _scrollToBottom();
    }
  }

  void _sendPing() {
    final esp = context.read<EspService>();
    if (esp.isConnected) {
      esp.sendPing();
    }
  }

  void _clearOutput() {
    setState(() {
      _output = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EspService>(
      builder: (context, esp, child) {
        // Update output from esp service
        if (esp.output != _output) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _output = esp.output;
              });
            }
          });
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Text(
                    'Serial Terminal',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  // Quick actions
                  ElevatedButton.icon(
                    onPressed: esp.isConnected ? _sendPing : null,
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('PING'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _clearOutput,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear'),
                  ),
                  const SizedBox(width: 16),
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

              // Output terminal
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _output.length,
                    itemBuilder: (context, index) {
                      final line = _output[index];
                      final isOutgoing = line.startsWith('>');
                      return SelectableText(
                        line,
                        style: TextStyle(
                          color: isOutgoing ? Colors.cyanAccent : Colors.greenAccent,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Input row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sendController,
                      decoration: const InputDecoration(
                        labelText: 'Befehl senden',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: esp.isConnected ? _send : null,
                    icon: const Icon(Icons.send),
                    label: const Text('Senden'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ],
              ),

              // Quick JSON commands
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildQuickButton(esp, 'LIST_FILES', () => esp.listFiles()),
                  _buildQuickButton(esp, 'READ_CONFIG', () => esp.readConfig()),
                  _buildQuickButton(esp, 'GET_SERIAL', () => esp.getBoardSerial()),
                  _buildQuickButton(esp, 'FETCH_TIME', () => esp.fetchDeviceTime()),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickButton(EspService esp, String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: esp.isConnected ? onPressed : null,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}