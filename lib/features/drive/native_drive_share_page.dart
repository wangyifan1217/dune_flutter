import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/dunes_defaults.dart';
import '../../core/theme/dunes_theme.dart';
import '../chat/dunes_pdf_view.dart';

class NativeDriveSharePage extends StatefulWidget {
  const NativeDriveSharePage({super.key, required this.token});

  final String token;

  @override
  State<NativeDriveSharePage> createState() => _NativeDriveSharePageState();
}

class _NativeDriveSharePageState extends State<NativeDriveSharePage> {
  String? _session;
  String? _error;
  bool _loading = true;
  Map<String, dynamic>? _data;
  final List<int> _folderStack = <int>[];

  Uri get _base =>
      Uri.parse(DunesDefaults.apiBase.replaceAll(RegExp(r'/$'), ''));

  Uri _uri(String path) =>
      Uri.parse('${_base.scheme}://${_base.authority}$path');

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  Future<void> _loadRoot() async {
    _folderStack.clear();
    await _loadPath(
      '/api/v1/public/drive/${Uri.encodeComponent(widget.token)}',
    );
  }

  Future<void> _loadItem(int id) async {
    _folderStack.add(id);
    await _loadPath(
      '/api/v1/public/drive/${Uri.encodeComponent(widget.token)}/items/$id',
    );
  }

  Future<void> _loadPath(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(_uri(path), headers: _headers);
      final body = _decode(response);
      if (response.statusCode == 401 &&
          body['data'] is Map &&
          body['data']['requiresPassword'] == true) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _data = null;
          _error = 'PASSWORD_REQUIRED';
        });
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw Exception('${body['message'] ?? '分享链接不可用'}');
      final data = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = '$error';
        });
    }
  }

  Map<String, String> get _headers => <String, String>{
    'Accept': 'application/json',
    if (_session != null) 'X-Drive-Share-Session': _session!,
  };

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _unlock() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入分享密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('解锁'),
          ),
        ],
      ),
    );
    if (password == null) return;
    final response = await http.post(
      _uri('/api/v1/public/drive/${Uri.encodeComponent(widget.token)}/unlock'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'password': password}),
    );
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (mounted) setState(() => _error = '${body['message'] ?? '密码错误'}');
      return;
    }
    setState(() => _session = '${body['data']?['session'] ?? ''}');
    await _loadRoot();
  }

  Future<void> _preview(Map<String, dynamic> item) async {
    final id = int.tryParse('${item['id']}') ?? 0;
    final mime = '${item['mimeType'] ?? ''}';
    final path =
        '/api/v1/public/drive/${Uri.encodeComponent(widget.token)}/content/$id?inline=1';
    try {
      final response = await http.get(_uri(path), headers: _headers);
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw Exception('下载失败');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${item['name'] ?? ''}'),
          content: mime.startsWith('image/')
              ? SizedBox(
                  width: 280,
                  child: Image.memory(
                    Uint8List.fromList(response.bodyBytes),
                    fit: BoxFit.contain,
                  ),
                )
              : mime == 'application/pdf'
              ? SizedBox(
                  width: 320,
                  height: 460,
                  child: DunesPdfView(
                    bytes: response.bodyBytes,
                    padding: 6,
                  ),
                )
              : Text(
                  '文件大小：${_formatBytes(response.bodyBytes.length)}\n分享链接仅支持查看和下载。',
                ),
          actions: [
            TextButton(
              onPressed: () {
                final suffix = _session == null || _session!.isEmpty
                    ? ''
                    : '&session=${Uri.encodeQueryComponent(_session!)}';
                unawaited(
                  launchUrl(
                    _uri('$path$suffix'),
                    mode: LaunchMode.externalApplication,
                  ),
                );
              },
              child: const Text('下载'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  String _formatBytes(int value) => value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(1)} KB'
      : '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    if (_error == 'PASSWORD_REQUIRED') {
      return _shell(
        const Center(child: Text('该分享链接需要密码')),
        action: FilledButton(onPressed: _unlock, child: const Text('输入密码')),
      );
    }
    if (_loading)
      return _shell(const Center(child: CircularProgressIndicator()));
    if (_error != null)
      return _shell(
        Center(child: Text(_error!)),
        action: TextButton(onPressed: _loadRoot, child: const Text('重试')),
      );
    final data = _data ?? const <String, dynamic>{};
    final rawItems = data['items'] is List
        ? data['items'] as List
        : const <dynamic>[];
    final isRootFile = '${data['type'] ?? ''}'.toLowerCase() == 'file';
    final displayItems = isRootFile ? <dynamic>[data] : rawItems;
    return _shell(
      ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: displayItems.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = displayItems[index] is Map
              ? Map<String, dynamic>.from(displayItems[index] as Map)
              : <String, dynamic>{};
          final folder = '${item['type']}'.toLowerCase() == 'folder';
          return ListTile(
            leading: Icon(
              folder ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
              color: folder ? const Color(0xFF7656D6) : DunesColors.text2,
            ),
            title: Text('${item['name'] ?? ''}'),
            subtitle: Text(
              folder
                  ? '文件夹'
                  : _formatBytes(int.tryParse('${item['sizeBytes']}') ?? 0),
            ),
            onTap: folder
                ? () => _loadItem(int.tryParse('${item['id']}') ?? 0)
                : () => _preview(item),
          );
        },
      ),
      title: '${data['name'] ?? '共享文件'}',
      back: _folderStack.isEmpty
          ? null
          : () {
              setState(() => _folderStack.removeLast());
              if (_folderStack.isEmpty) {
                _loadRoot();
              } else {
                _loadPath(
                  '/api/v1/public/drive/${Uri.encodeComponent(widget.token)}/items/${_folderStack.last}',
                );
              }
            },
    );
  }

  Widget _shell(
    Widget body, {
    Widget? action,
    String title = '企业微盘分享',
    VoidCallback? back,
  }) => Scaffold(
    backgroundColor: DunesColors.bgApp,
    appBar: AppBar(
      title: Text(title),
      leading: back == null
          ? null
          : IconButton(icon: const Icon(Icons.arrow_back), onPressed: back),
      actions: [if (action != null) action],
    ),
    body: body,
  );
}

