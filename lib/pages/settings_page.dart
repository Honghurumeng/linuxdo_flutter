import 'package:flutter/material.dart';

import '../services/settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _ua;
  late final TextEditingController _proxy;
  late final TextEditingController _cookies;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance.value;
    _baseUrl = TextEditingController(text: s.baseUrl);
    _ua = TextEditingController(text: s.userAgent ?? '');
    _proxy = TextEditingController(text: s.proxy ?? '');
    _cookies = TextEditingController(text: s.cookies ?? '');
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _ua.dispose();
    _proxy.dispose();
    _cookies.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SettingsService.instance.update(
        baseUrl: _baseUrl.text.trim().isEmpty ? 'https://linux.do' : _baseUrl.text.trim(),
        userAgent: _ua.text.trim().isEmpty ? null : _ua.text.trim(),
        proxy: _proxy.text.trim().isEmpty ? null : _proxy.text.trim(),
        cookies: _cookies.text.trim().isEmpty ? null : _cookies.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('基础'),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrl,
            decoration: const InputDecoration(
              labelText: '站点地址（Base URL）',
              hintText: '例如：https://linux.do',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text('User-Agent'),
          const SizedBox(height: 8),
          TextField(
            controller: _ua,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '自定义 UA（可留空使用默认）',
              hintText: '留空使用内置移动端浏览器 UA',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text('HTTP 代理（可选）'),
          const SizedBox(height: 8),
          TextField(
            controller: _proxy,
            decoration: const InputDecoration(
              labelText: 'HTTP 代理地址',
              hintText: '例如：127.0.0.1:7890 或 http://127.0.0.1:7890',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '说明：填写后，网络请求将通过该代理（需要支持 HTTPS CONNECT）。安卓模拟器想使用宿主机 127.0.0.1，请改用 10.0.2.2。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const Text('Cookies（可选）'),
          const SizedBox(height: 8),
          TextField(
            controller: _cookies,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Cookie 请求头（如 cf_clearance=...; _forum_session=...）',
              hintText: '格式：k1=v1; k2=v2，留空则不带 Cookie',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '可在浏览器访问站点后，从开发者工具/扩展中复制 Cookie（至少含 cf_clearance）。注意隐私，不要随意外泄。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
