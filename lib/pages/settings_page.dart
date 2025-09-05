import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _ua;
  late final TextEditingController _proxy;
  late final TextEditingController _cookies;
  bool _saving = false;
  
  void _syncFromSettings() {
    final s = SettingsService.instance.value;
    // 只同步 UA 与 Cookies 到输入框，便于查看/确认
    _ua.text = s.userAgent ?? '';
    _cookies.text = s.cookies ?? '';
  }

  void _copyToClipboard(String text, String label) async {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label 为空，未复制')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 $label')),
    );
  }

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance.value;
    _ua = TextEditingController(text: s.userAgent ?? '');
    _proxy = TextEditingController(text: s.proxy ?? '');
    _cookies = TextEditingController(text: s.cookies ?? '');
    SettingsService.instance.addListener(_syncFromSettings);
  }

  @override
  void dispose() {
    _ua.dispose();
    _proxy.dispose();
    _cookies.dispose();
    SettingsService.instance.removeListener(_syncFromSettings);
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SettingsService.instance.update(
        // 空字符串表示清空（使用默认 UA / 不带 Cookie）
        userAgent: _ua.text.trim().isEmpty ? '' : _ua.text.trim(),
        proxy: _proxy.text.trim().isEmpty ? '' : _proxy.text.trim(),
        cookies: _cookies.text.trim().isEmpty ? '' : _cookies.text.trim(),
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
          // 移除 Base URL 设置，固定使用 https://linux.do
          const Text('User-Agent'),
          const SizedBox(height: 8),
          TextField(
            controller: _ua,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '自定义 UA（可留空使用默认）',
              hintText: '留空使用内置桌面 Chrome UA；建议与登录 UA 一致',
              border: OutlineInputBorder(),
            ).copyWith(
              suffixIcon: IconButton(
                tooltip: '复制 UA',
                icon: const Icon(Icons.copy_rounded),
                onPressed: _ua.text.trim().isEmpty
                    ? null
                    : () => _copyToClipboard(_ua.text.trim(), 'UA'),
              ),
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
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Cookie 请求头（如 cf_clearance=...; _forum_session=...）',
              hintText: '格式：k1=v1; k2=v2，留空则不带 Cookie',
              border: OutlineInputBorder(),
            ).copyWith(
              suffixIcon: IconButton(
                tooltip: '复制 Cookies',
                icon: const Icon(Icons.copy_rounded),
                onPressed: _cookies.text.trim().isEmpty
                    ? null
                    : () => _copyToClipboard(_cookies.text.trim(), 'Cookies'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final t = _cookies.text.trim();
            String preview;
            if (t.isEmpty) {
              preview = '（空）';
            } else {
              final names = t
                  .split(';')
                  .map((e) => e.trim())
                  .where((e) => e.contains('='))
                  .map((e) => e.substring(0, e.indexOf('=')))
                  .where((e) => e.isNotEmpty)
                  .toList();
              preview = names.isEmpty ? '（无有效键）' : names.join(', ');
            }
            return Text(
              'Cookie 键名预览：$preview',
              style: Theme.of(context).textTheme.bodySmall,
            );
          }),
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
