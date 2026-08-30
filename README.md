# Bilibili Accelerator Client

在哔哩哔哩 Windows 桌面客户端的播放窗口中注入 [Bilibili Accelerator](https://github.com/realzza/bilibili-accelerator)，显示原版悬浮闪电按钮和完整控制面板，无需启动 Chrome 或安装油猴扩展。

> 当前基于哔哩哔哩桌面客户端 `1.17.9` 验证。该项目与哔哩哔哩及 Bilibili Accelerator 作者没有隶属或官方合作关系。

## 原理

启动器使用 Electron/Chromium 的本地调试接口发现客户端的 `player.html` 播放窗口，并在页面环境中执行上游 userscript。它不会修改官方客户端的 `app.asar` 或安装目录。

调试接口仅绑定 `127.0.0.1`，端口在每次启动时随机选择。启动器保持运行，负责处理后续创建的播放窗口。

## 使用

1. 从 Releases 下载 Windows 压缩包并解压。
2. 保证 `Bilibili Accelerator Client.exe` 与 `bilibili-accelerator.user.js` 位于同一目录。
3. 完全退出已经运行的哔哩哔哩客户端。
4. 运行 `Bilibili Accelerator Client.exe`。
5. 打开视频，在播放窗口右下角点击闪电按钮。

本地生成的程序没有代码签名，Windows 首次运行时可能显示安全提醒。

## 开发

需要 Node.js 22 或更新版本。

```powershell
npm install
npm run check
npm run build:win
```

构建结果位于 `dist/Bilibili Accelerator Client`。

如果哔哩哔哩安装在其他位置，可以设置 `BILIBILI_APP_PATH` 环境变量。

## 来源与借用

- `vendor/bilibili-accelerator.user.js` 原样取自 [realzza/bilibili-accelerator](https://github.com/realzza/bilibili-accelerator)，版本 `0.4.0`，依据 MIT License 使用。Accelerator 的 CDN 重写、测速、状态面板及 UI 均由该上游项目提供。
- 本项目只实现 Windows 客户端启动、播放窗口发现和脚本注入适配。
- 单文件 Windows 构建使用 [Node.js SEA](https://nodejs.org/api/single-executable-applications.html) 与 [postject](https://github.com/nodejs/postject)。

完整版权和许可证说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可

启动器代码采用 [MIT License](LICENSE)。第三方代码继续适用各自原有许可证。


