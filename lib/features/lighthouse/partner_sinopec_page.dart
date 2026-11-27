import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';

class PartnerSinopecPage extends StatefulWidget {
  const PartnerSinopecPage({super.key, required this.session});
  final AuthSession session;

  @override
  State<PartnerSinopecPage> createState() => _PartnerSinopecPageState();
}

class _PartnerSinopecPageState extends State<PartnerSinopecPage> {
  late Future<Map<String, dynamic>> _data = _load();

  Future<Map<String, dynamic>> _load() async {
    final base = widget.session.apiBase.replaceAll(RegExp(r'/$'), '');
    final response = await http
        .get(
          Uri.parse('$base/lighthouse/partner/sinopec-scale'),
          headers: {'Authorization': 'Bearer ${widget.session.token}'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('数据暂时不可用（${response.statusCode}）');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('中石化数据')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('数据加载失败，请稍后重试'),
                TextButton(
                  onPressed: () => setState(() => _data = _load()),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('日期：${data['date']}'),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('WOA'),
              trailing: Text('${data['woa']}'),
            ),
            ListTile(
              title: const Text('GMV'),
              trailing: Text('${data['gmv']}'),
            ),
          ],
        );
      },
    ),
  );
}
