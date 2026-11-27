# 远程操作 / Remote

把本机变成一个任务端点（HTTP），或者把任务发给另一台开着 Local-Harness 的机器。

Expose this machine as an HTTP task endpoint, or send tasks to another machine running Local-Harness.

Local-Harness（Godot 版）的独立插件。**不随主程序发布**，由主程序「设置 → 插件管理」从 GitHub 下载并自动部署到 `user://plugins/remote/`。

## 工具

- `remote_serve` —— 在本机开一个 HTTP 端点：POST /task {"prompt":"..."} 会用本地模型处理后返回 JSON。
  - `port`: int，可选，默认 8799
- `remote_call` —— 把一句任务发给另一台机器上的 Local-Harness 端点，拿回它的回答。
  - `host`: string，对方 IP 或主机名
  - `port`: int，对方端口，默认 8799
  - `prompt`: string，任务内容
- `remote_ping` —— 探测一个端点是否在线。
  - `host`: string
  - `port`: int，可选，默认 8799
- `remote_stop` —— 关掉本机端点。

## 安装

1. Local-Harness → 设置 → 插件管理 → 刷新列表
2. 找到「远程操作」点安装
3. 装完直接在对话里让模型调用（插件会出现在系统提示的工具清单里）

手动安装：把仓库解压到 `%LOCALAPPDATA%\Godot\app_userdata\Local-Harness\plugins\remote\`。

## 结构

```
manifest.json   清单：id / 版本 / 工具定义
main.gd         extends Node，实现 run(tool, args) -> {ok, output}
```

## 许可

GPL-3.0（与主程序一致）。
