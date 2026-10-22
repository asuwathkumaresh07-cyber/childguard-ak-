import 'package:flutter/material.dart';

import 'config.dart';
import 'supabase_service.dart';

/// Modal dialog allowing parents/admins to view or update Supabase URL and Anon Key.
class SupabaseConfigDialog extends StatefulWidget {
  const SupabaseConfigDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const SupabaseConfigDialog(),
    );
  }

  @override
  State<SupabaseConfigDialog> createState() => _SupabaseConfigDialogState();
}

class _SupabaseConfigDialogState extends State<SupabaseConfigDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  bool _testing = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: SupabaseConfig.url);
    _keyController = TextEditingController(text: SupabaseConfig.anonKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveAndConnect() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();

    if (url.isEmpty || key.isEmpty) {
      setState(() {
        _statusMessage = 'Both URL and Anon Key are required.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _testing = true;
      _statusMessage = null;
    });

    try {
      await SupabaseConfig.saveCustomConfig(url, key);
      final connected = await SupabaseService.instance.init();

      if (mounted) {
        setState(() {
          _testing = false;
          _isSuccess = connected;
          _statusMessage = connected
              ? 'Connected successfully to Supabase!'
              : 'Saved, but could not connect: '
                  '${SupabaseService.instance.initializationError ?? 'verify your credentials and network.'}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _isSuccess = false;
          _statusMessage = 'Error connecting: $e';
        });
      }
    }
  }

  Future<void> _reset() async {
    await SupabaseConfig.resetToDefaults();
    _urlController.text = SupabaseConfig.url;
    _keyController.text = SupabaseConfig.anonKey;
    setState(() {
      _statusMessage = 'Reset back to dummy demo defaults.';
      _isSuccess = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isReal = SupabaseConfig.isRealSupabaseConfigured;
    final isConnected = SupabaseService.instance.isInitialized;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.cloud_sync, color: Color(0xFF0B6E4F)),
          SizedBox(width: 8),
          Text('Supabase Backend'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isConnected ? Colors.green.shade50 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isConnected
                      ? Colors.green.shade300
                      : Colors.amber.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isConnected ? Icons.check_circle : Icons.info_outline,
                    color: isConnected
                        ? Colors.green.shade800
                        : Colors.amber.shade900,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isConnected
                          ? 'Connected to Supabase Cloud'
                          : (isReal
                              ? 'Credentials set, connecting...'
                              : 'Running in Local Demo Mode (dummy keys)'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isConnected
                            ? Colors.green.shade900
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter your Supabase project URL and anon/public key to sync rules and activity logs to your database:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Supabase URL',
                hintText: 'https://xyzcompany.supabase.co',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Supabase Anon Key',
                hintText: 'eyJhbGciOi...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: TextStyle(
                  color: _isSuccess ? Colors.green : Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: const Text('Reset Dummy'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _testing ? null : _saveAndConnect,
          child: _testing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save & Connect'),
        ),
      ],
    );
  }
}
