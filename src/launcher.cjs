const { readFile } = require('node:fs/promises');
const { spawn } = require('node:child_process');
const net = require('node:net');
const path = require('node:path');
const process = require('node:process');

const here = __dirname;
const appPath = process.env.BILIBILI_APP_PATH || 'C:\\Program Files\\bilibili\\哔哩哔哩.exe';
const scriptPaths = [
  path.join(here, 'bilibili-accelerator.user.js'),
  path.join(here, '..', 'vendor', 'bilibili-accelerator.user.js'),
];

async function readUserscript() {
  let lastError;
  for (const scriptPath of scriptPaths) {
    try { return await readFile(scriptPath, 'utf8'); } catch (error) { lastError = error; }
  }
  throw new Error(`找不到 bilibili-accelerator.user.js：${lastError?.message || '未知错误'}`);
}

function log(message) {
  process.stdout.write(`[Bilibili Accelerator] ${message}\n`);
}

function getFreePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : 0;
      server.close(error => error ? reject(error) : resolve(port));
    });
  });
}

async function waitForDebugger(port, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (response.ok) return;
    } catch (error) {
      lastError = error;
    }
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  throw new Error(`无法连接客户端调试接口${lastError ? `：${lastError.message}` : ''}`);
}

class PageConnection {
  constructor(url) {
    this.url = url;
    this.ws = null;
    this.nextId = 1;
    this.pending = new Map();
  }

  async connect() {
    this.ws = new WebSocket(this.url);
    await new Promise((resolve, reject) => {
      this.ws.addEventListener('open', resolve, { once: true });
      this.ws.addEventListener('error', () => reject(new Error('页面调试连接失败')), { once: true });
    });
    this.ws.addEventListener('message', event => this.onMessage(event.data));
    this.ws.addEventListener('close', () => {
      for (const { reject } of this.pending.values()) reject(new Error('页面调试连接已关闭'));
      this.pending.clear();
    });
  }

  onMessage(raw) {
    const message = JSON.parse(raw);
    if (!message.id || !this.pending.has(message.id)) return;
    const pending = this.pending.get(message.id);
    this.pending.delete(message.id);
    if (message.error) pending.reject(new Error(message.error.message));
    else pending.resolve(message.result || {});
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    try { this.ws?.close(); } catch {}
  }
}

class PlayerInjector {
  constructor(port, injectionSource) {
    this.port = port;
    this.injectionSource = injectionSource;
    this.connections = new Map();
    this.stopped = false;
    this.uiConfirmed = false;
  }

  async scan() {
    const response = await fetch(`http://127.0.0.1:${this.port}/json/list`);
    const targets = await response.json();
    const liveIds = new Set(targets.map(target => target.id));

    for (const [id, connection] of this.connections) {
      if (!liveIds.has(id)) {
        connection.close();
        this.connections.delete(id);
      }
    }

    for (const target of targets) {
      if (target.type !== 'page' || this.connections.has(target.id)) continue;
      this.connections.set(target.id, null);
      this.connectTarget(target).catch(error => {
        this.connections.delete(target.id);
        log(`页面注入失败：${error.message}`);
      });
    }
  }

  async connectTarget(target) {
    const connection = new PageConnection(target.webSocketDebuggerUrl);
    await connection.connect();
    this.connections.set(target.id, connection);
    await connection.send('Page.enable');
    await connection.send('Runtime.enable');
    // Keep the accelerator installed when player.html reloads from the panel's
    // Reload action or when the desktop client navigates within the same target.
    // A CDP target survives those navigations, while its JavaScript world and
    // DOM do not, so a one-shot Runtime.evaluate is not sufficient.
    await connection.send('Page.addScriptToEvaluateOnNewDocument', {
      source: this.injectionSource,
    });
    await connection.send('Runtime.evaluate', {
      expression: this.injectionSource,
      awaitPromise: true,
    });

    let status;
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const check = await connection.send('Runtime.evaluate', {
        expression: `(() => {
          const host = document.getElementById('bili-accelerator-button');
          return {
            player: /\\/player\\.html$/i.test(location.pathname),
            injected: Boolean(globalThis.__bilibiliAcceleratorClientInjected),
            core: Boolean(globalThis.BiliAccelerator),
            ui: Boolean(host && host.shadowRoot && host.shadowRoot.querySelector('.ba-toggle')),
            error: globalThis.__bilibiliAcceleratorClientError || '',
          };
        })()`,
        returnByValue: true,
      });
      status = check.result && check.result.value;
      if (!status?.player || status.ui || status.error) break;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    if (status && status.player && !this.uiConfirmed) {
      this.uiConfirmed = Boolean(status.ui);
      log(status.ui
        ? '播放窗口的 Accelerator 悬浮按钮和面板已成功挂载。'
        : `已找到播放窗口，但 Accelerator UI 尚未挂载${status.error ? `：${status.error}` : status.core ? '（核心已加载）' : '（核心未加载）'}`);
    }
  }

  async run() {
    while (!this.stopped) {
      try { await this.scan(); } catch {}
      await new Promise(resolve => setTimeout(resolve, 250));
    }
  }

  stop() {
    this.stopped = true;
    for (const connection of this.connections.values()) connection?.close();
    this.connections.clear();
  }
}

function buildInjection(userscript) {
  const guard = '/\\/player\\.html$/i.test(location.pathname)';
  return `(() => {
    if (!${guard}) return;
    if (globalThis.__bilibiliAcceleratorClientInjected) return;
    globalThis.__bilibiliAcceleratorClientInjected = true;
    try {
${userscript}
      console.info('[Bilibili Accelerator Client] UI and network hooks installed');
    } catch (error) {
      globalThis.__bilibiliAcceleratorClientInjected = false;
      globalThis.__bilibiliAcceleratorClientError = String(error && (error.stack || error.message) || error);
      console.error('[Bilibili Accelerator Client] injection failed', error);
    }
  })();`;
}

async function main() {
  const userscript = await readUserscript();
  const port = await getFreePort();
  log('正在启动哔哩哔哩客户端…');
  const app = spawn(appPath, [
    `--remote-debugging-port=${port}`,
    '--remote-debugging-address=127.0.0.1',
  ], {
    stdio: 'ignore',
    windowsHide: false,
  });
  app.once('error', error => { throw new Error(`无法启动哔哩哔哩客户端：${error.message}`); });

  await waitForDebugger(port);
  const injector = new PlayerInjector(port, buildInjection(userscript));
  injector.run();
  log('加速器已就绪。打开任意视频后，播放窗口右下角会出现闪电按钮。');
  log('请保持此窗口运行；关闭哔哩哔哩客户端后会自动退出。');

  await new Promise(resolve => app.once('exit', resolve));
  injector.stop();
}

main().catch(error => {
  process.stderr.write(`\n启动失败：${error.message}\n`);
  process.stderr.write('如果客户端已经在运行，请先完全退出后再试。\n');
  process.exitCode = 1;
});
