# 远程操作 / Remote

把本机变成一个任务端点（HTTP），或者把任务发给另一台开着 Local-Harness 的机器。

Expose this machine as an HTTP task endpoint, or send tasks to another machine running Local-Harness.

> Local-Harness（Godot 版）的独立插件。不随主程序发布，由主程序
> 「设置 → 插件管理」从 GitHub 下载并自动部署到 `user://plugins/remote/`。

## 安装

1. 打开 Local-Harness → 设置 → 插件管理 → 刷新列表
2. 找到「远程操作」点「安装」
3. 装好后在侧栏底部点同名按钮，里面是这个插件自己的设置页

手动安装：把本仓库下载解压到 `%LOCALAPPDATA%\Godot\app_userdata\Local-Harness\plugins\remote\`

## 工具

- `remote_serve` —— 在本机开一个 HTTP 端点：POST /task {"prompt":"..."} 会用本地模型处理后返回 JSON。（高危）
  - `port`: int，可选，默认 8799
- `remote_call` —— 把一句任务发给另一台机器上的 Local-Harness 端点，拿回它的回答。（会产生操作）
  - `host`: string，对方 IP 或主机名
  - `port`: int，对方端口，默认 8799
  - `prompt`: string，任务内容
- `remote_ping` —— 探测一个端点是否在线。（只读）
  - `host`: string
  - `port`: int，可选，默认 8799
- `remote_stop` —— 关掉本机端点。（会产生操作）

## 命令

- `/serve [端口]` —— 开远程端点

## 设置项

- **默认端口**（`port`，默认 `8799`）remote_serve / remote_call 不填端口时用这个

## 权限

每个工具都能在插件设置页里单独开关。关掉之后它不会出现在模型的工具清单里，
就算模型硬要调用也会被主程序拒绝。协议里用 `level` 标了风险等级：

- `read` 只读：不会改动任何东西
- `act` 会产生操作：会读写文件、联网或占用设备
- `danger` 高危：会操作你的系统

## 怎么用

装好后直接在对话里提需求，例如：“在本机开一个 HTTP 端点：POST /task {"prompt":"..."} 会用本地模型处理后返回 JSON。”

模型会输出一行 ```tool 协议块，宿主解析后执行，再把结果喂回模型。
也可以直接用斜杠命令，不经过模型。

## 许可

GPL-3.0（与主程序一致）。完整协议文本见仓库根目录的 [LICENSE](LICENSE)。

---

# Remote

Expose this machine as an HTTP task endpoint, or send tasks to another machine running Local-Harness.

> An independent plugin for **Local-Harness (Godot edition)**. It is not bundled with the
> app; the app downloads it from this repository into `user://plugins/remote/` and hot-loads it.

## Install

1. Local-Harness → Settings → Plugins → Refresh
2. Find "Remote" and click Install
3. Open it from the button at the bottom of the sidebar for its own settings page

Manual: unzip this repo into `%LOCALAPPDATA%\Godot\app_userdata\Local-Harness\plugins\remote\`

## Tools

- `remote_serve` — 在本机开一个 HTTP 端点：POST /task {"prompt":"..."} 会用本地模型处理后返回 JSON。 (dangerous)
  - `port`: int，可选，默认 8799
- `remote_call` — 把一句任务发给另一台机器上的 Local-Harness 端点，拿回它的回答。 (has side effects)
  - `host`: string，对方 IP 或主机名
  - `port`: int，对方端口，默认 8799
  - `prompt`: string，任务内容
- `remote_ping` — 探测一个端点是否在线。 (read-only)
  - `host`: string
  - `port`: int，可选，默认 8799
- `remote_stop` — 关掉本机端点。 (has side effects)

## Commands

- `/serve [端口]` — 开远程端点

## Settings

- **默认端口** (`port`, default `8799`) remote_serve / remote_call 不填端口时用这个

## Permissions

Every tool can be toggled individually on the plugin settings page. A disabled tool is
removed from the model's tool list and rejected by the host even if the model still calls it.
`level` in the manifest marks the risk:

- `read` — no side effects
- `act` — reads/writes, network or devices
- `danger` — controls your system

## Usage

Just ask in the chat, e.g. “在本机开一个 HTTP 端点：POST /task {"prompt":"..."} 会用本地模型处理后返回 JSON。”

The model emits a ```tool block, the host executes it and feeds the result back.
You can also use the slash commands above, which skip the model entirely.

## License

GPL-3.0 (same as the host app). Full text: [LICENSE](LICENSE).
