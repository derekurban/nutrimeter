// A small JSON-RPC client for `codex app-server` over stdio (protocol: `codex app-server generate-ts`).
// One process serves every review; each review is its own thread, and notifications are routed by threadId.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';

const WIN = process.platform === 'win32';
const TARGET = {
  'win32-x64': 'x86_64-pc-windows-msvc', 'win32-arm64': 'aarch64-pc-windows-msvc',
  'darwin-x64': 'x86_64-apple-darwin', 'darwin-arm64': 'aarch64-apple-darwin',
  'linux-x64': 'x86_64-unknown-linux-musl', 'linux-arm64': 'aarch64-unknown-linux-musl',
}[`${process.platform}-${process.arch}`];

/** The native Codex binary: NUTRIMETER_CODEX_BIN, or the one behind the npm shim, or `codex` on PATH. */
export function locateCodex(env = process.env) {
  if (env.NUTRIMETER_CODEX_BIN) return env.NUTRIMETER_CODEX_BIN;
  const dirs = (env.PATH || env.Path || '').split(path.delimiter).filter(Boolean);
  if (WIN && env.APPDATA) dirs.push(path.join(env.APPDATA, 'npm'));
  for (const dir of dirs) {
    const pkg = WIN ? path.join(dir, 'node_modules', '@openai', 'codex') : path.join(dir, '..', 'lib', 'node_modules', '@openai', 'codex');
    if (fs.existsSync(pkg)) {
      const root = fs.realpathSync(pkg);
      for (const base of [path.join(root, 'node_modules', '@openai', `codex-${process.platform}-${process.arch}`, 'vendor'), path.join(root, 'vendor')]) {
        const exe = path.join(base, TARGET || '', 'bin', WIN ? 'codex.exe' : 'codex');
        if (fs.existsSync(exe)) return exe;
      }
    }
    const exe = path.join(dir, WIN ? 'codex.exe' : 'codex');
    if (fs.existsSync(exe) && fs.statSync(exe).isFile()) return exe;
  }
  return null;
}

export class AppServer {
  constructor({ exe = locateCodex(), args = ['app-server'], env = process.env, log = () => {} } = {}) {
    this.exe = exe;
    this.args = args;
    this.env = env;
    this.log = log;
    this.pending = new Map();
    this.listeners = new Map(); // threadId → fn(method, params)
    this.next = 1;
    this.ready = null;
    this.child = null;
  }

  start() {
    if (this.ready) return this.ready;
    if (!this.exe) return Promise.reject(new Error('Codex is not installed (npm i -g @openai/codex).'));
    this.child = spawn(this.exe, this.args, { env: this.env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stdin.on('error', () => {});
    this.child.stderr.on('data', (d) => this.log(String(d).trim()));
    readline.createInterface({ input: this.child.stdout }).on('line', (line) => this.receive(line));
    const fail = (error) => {
      for (const { reject, timer } of this.pending.values()) {
        clearTimeout(timer);
        reject(error);
      }
      this.pending.clear();
      for (const fn of this.listeners.values()) fn('server/stopped', { message: error.message });
      this.ready = null;
      this.child = null;
    };
    this.child.on('error', fail);
    this.child.on('close', () => fail(new Error('The Codex app server stopped.')));
    this.ready = this.call('initialize', {
      clientInfo: { name: 'nutrimeter-admin', title: 'Nutrimeter admin', version: '0.1.0' },
      capabilities: null,
    }).then((result) => {
      this.send({ method: 'initialized' });
      return result;
    });
    this.ready.catch(() => this.stop());
    return this.ready;
  }

  receive(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }
    if (message.id !== undefined && !message.method && this.pending.has(message.id)) {
      const { resolve, reject, timer } = this.pending.get(message.id);
      clearTimeout(timer);
      this.pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message || 'Codex refused the request.'));
      else resolve(message.result);
      return;
    }
    if (message.method && message.id !== undefined) {
      // A request from the server (approvals, user input). Reviews run with approvals off and need no input,
      // so anything here is unexpected: decline it and tell the run.
      const threadId = message.params?.threadId;
      this.listeners.get(threadId)?.('server/request', { method: message.method, params: message.params });
      this.send({ id: message.id, error: { code: -32601, message: 'Nutrimeter reviews do not take approvals or input.' } });
      return;
    }
    if (message.method) {
      const threadId = message.params?.threadId ?? message.params?.thread?.id;
      if (threadId && this.listeners.has(threadId)) this.listeners.get(threadId)(message.method, message.params);
    }
  }

  send(message) {
    this.child?.stdin.write(JSON.stringify(message) + '\n');
  }

  call(method, params, timeout = 60000) {
    return new Promise((resolve, reject) => {
      if (!this.child) return reject(new Error('The Codex app server is not running.'));
      const id = this.next++;
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Codex did not answer ${method} in time.`));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      this.send({ id, method, params });
    });
  }

  async request(method, params, timeout) {
    await this.start();
    return this.call(method, params, timeout);
  }

  listen(threadId, fn) {
    this.listeners.set(threadId, fn);
    return () => this.listeners.delete(threadId);
  }

  stop() {
    try {
      this.child?.kill();
    } catch {}
    this.child = null;
    this.ready = null;
  }
}
