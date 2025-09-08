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
  bool _useWebViewBackend = false;
  
  void _syncFromSettings() {
    final s = SettingsService.instance.value;
    // 只同步 UA 与 Cookies 到输入框，便于查看/确认
    _ua.text = s.userAgent ?? '';
    _cookies.text = s.cookies ?? '';
    if (mounted) setState(() {});
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
    _useWebViewBackend = s.useWebViewBackend;
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
        useWebViewBackend: _useWebViewBackend,
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
          SwitchListTile(
            value: _useWebViewBackend,
            onChanged: (v) => setState(() => _useWebViewBackend = v),
            title: const Text('使用后台 WebView 作为网络栈（更稳）'),
            subtitle: const Text('在后台常驻一个 WebView，用浏览器同源 fetch 加载数据，自动携带并刷新 Cloudflare Cookie。'),
          ),
          const SizedBox(height: 8),
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
          const Text('Cookies（只读镜像）'),
          const SizedBox(height: 8),
          TextField(
            controller: _cookies,
            maxLines: 3,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: '当前会话 Cookie（镜像，仅供查看/复制）',
              hintText: '由 WebView 会话自动同步与刷新，不可编辑',
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
            '该字段为只读镜像：应用会自动从 WebView 会话同步并刷新 Cookie，不可编辑。若需更新，请在“站内登录”中完成验证后保存返回。注意隐私，不要外泄。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
