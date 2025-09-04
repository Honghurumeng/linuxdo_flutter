LinuxDo Reader (Flutter)

一个简单的 Flutter 应用：

- 抓取 linux.do 首页帖子列表（使用 Discourse JSON 接口：`/latest.json`）
- 点击帖子进入详情，渲染帖子内容（使用 `flutter_html` 渲染 `cooked` HTML，包括图片）

运行步骤

1) 确保已安装 Flutter SDK，并可用 `flutter --version` 正常工作。
2) 在本目录执行（首次）生成平台目录：

   flutter create .

3) 拉取依赖：

   flutter pub get

4) 运行到模拟器或真机：

   flutter run

说明

- 数据来源为 Discourse 提供的公开 JSON 接口：
  - 列表：`https://linux.do/latest.json?page=0&no_definitions=true`
  - 详情：`https://linux.do/t/{id}.json`
- 帖子内容使用 Discourse 的 `cooked` HTML 字段，应用内做了相对链接/图片到绝对地址的转换。
- 界面样式保持简单，只含文字、列表与图片展示。

设置（UA/代理/Base URL）

- 右上角“齿轮”图标进入设置：
  - Base URL：默认 `https://linux.do`
  - User-Agent：可自定义；留空使用移动端浏览器 UA
  - HTTP 代理：如 `127.0.0.1:7890` 或 `http://127.0.0.1:7890`
    - 安卓模拟器访问宿主机可用 `10.0.2.2:7890`
    - 代理需支持 HTTPS CONNECT

登录 & Cookies 获取

- 首页右上角“登录”图标会打开内置 WebView 到站点主页。
- 在 WebView 中完成站内登录或 Cloudflare 校验后，点击“保存Cookies”即可将 `document.cookie` 保存到应用，用于后续 API 请求。
- 若仍被拦截，可搭配自定义 User-Agent/代理一起使用。

注意

- 请遵守站点的使用条款与 robots 设置，避免高频访问。
- 如果某些帖子/图片需要登录权限，可能无法在未登录的情况下显示完整内容。
