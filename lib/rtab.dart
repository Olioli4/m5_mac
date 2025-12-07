import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class RTab extends StatefulWidget {
  const RTab({super.key});

  @override
  State<RTab> createState() => _RTabState();
}

class _RTabState extends State<RTab> {
  List<String> _reports = [];
  final TextEditingController _reportController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _reports = prefs.getStringList('rtab_reports') ?? [];
    });
  }

  Future<void> _saveReports() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('rtab_reports', _reports);
  }

  void _addReport() {
    if (_reportController.text.isNotEmpty) {
      setState(() {
        _reports.add(_reportController.text);
        _reportController.clear();
      });
      _saveReports();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report added!')),
      );
    }
  }

  void _deleteReport(int index) {
    setState(() {
      _reports.removeAt(index);
    });
    _saveReports();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report deleted!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RTab', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _reportController,
                  decoration: const InputDecoration(labelText: 'Add report'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addReport,
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _reports.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_reports[index]),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteReport(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reportController.dispose();
    super.dispose();
  }
}