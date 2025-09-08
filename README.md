LinuxDo Reader (Flutter)

一个简单的 Flutter 应用：

- 抓取 linux.do 首页帖子列表（使用 Discourse JSON 接口：`/latest.json`）
- 点击帖子进入详情，渲染帖子内容（使用 `flutter_widget_from_html_core` 渲染 `cooked` HTML，包括图片）

运行步骤

1) 确保已安装 Flutter SDK，并可用 `flutter --version` 正常工作。
2) 拉取依赖：

   flutter pub get

3) 开发运行：

   flutter run -d chrome

   或选择其它设备（Android/iOS/桌面）。

4) 分析与测试：

   flutter analyze

   flutter test

说明

- 数据来源为 Discourse 提供的公开 JSON 接口：
  - 列表：`https://linux.do/latest.json?page=0&no_definitions=true`
  - 详情：`https://linux.do/t/{id}.json`
- 帖子内容使用 Discourse 的 `cooked` HTML 字段，应用内做了相对链接/图片到绝对地址的转换。
- 界面样式保持简单，只含文字、列表与图片展示。

设置（UA/代理/网络栈）

- 右上角“齿轮”图标进入设置：
  - 使用后台 WebView 作为网络栈（默认开启）：在后台常驻一个 WebView，用浏览器同源 fetch 加载数据，自动携带并刷新 Cloudflare Cookie。
  - User-Agent：可自定义；留空使用内置桌面 Chrome UA（建议与登录 UA 一致）。
  - HTTP 代理：如 `127.0.0.1:7890` 或 `http://127.0.0.1:7890`
    - 安卓模拟器访问宿主机可用 `10.0.2.2:7890`
    - 代理需支持 HTTPS CONNECT
  - Base URL 固定为 `https://linux.do`，不支持修改。

登录与 Cookies/UA 获取

- 首页右上角“站内登录”会在内置 WebView 打开站点。
- 在 WebView 中完成站内登录或 Cloudflare 校验后，点击“保存Cookies并返回”。应用会同时保存 Cookies 与 UA（Cloudflare 会将 cf_clearance 与 UA 绑定）。
- 应用会自动从 WebView 同步并刷新 Cookie，并在 HTTP 响应的 Set-Cookie 中合并最新值；不再支持“锁定 Cookies”。
- 若仍被拦截，可搭配自定义 User-Agent/代理一起使用，或稍等片刻让后台刷新完成后重试。

注意

- 请遵守站点的使用条款与 robots 设置，避免高频访问。
- 如果某些帖子/图片需要登录权限，可能无法在未登录的情况下显示完整内容。
