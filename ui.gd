extends VBoxContainer
## 本插件的设置界面 —— 由插件自己提供，主程序只负责挂载。
## 想改这个插件在这里长什么样、有哪些开关，改这个文件即可。

func build(plugin_id: String) -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(PluginUI.title("远程操作"))
	add_child(PluginUI.hint("把本机变成一个任务端点，或把任务发到另一台开着 Local-Harness 的机器。"))
	add_child(PluginUI.section("行为"))
	add_child(PluginUI.int_field(plugin_id, "port", "默认端口", 8799,
		"remote_serve / remote_call 不填端口时使用"))
	add_child(PluginUI.section("能力开关"))
	add_child(PluginUI.hint("每一项都能单独关掉；关掉后模型看不到这个能力，也调用不了。"))
	for t in Plugins.tools_of(plugin_id):
		var tname := str(t.get("name", ""))
		var human := tname
		var desc := str(t.get("description", ""))
		if tname == "remote_serve":
			human = "开放本机端点"
			desc = "局域网内其他机器可以往你这派任务"
		if tname == "remote_call":
			human = "调用远端"
			desc = "把任务发出去"
		if tname == "remote_ping":
			human = "探测端点"
			desc = "只读"
		if tname == "remote_stop":
			human = "关闭端点"
			desc = ""
		add_child(PluginUI.perm_row(tname, human, desc, bool(t.get("dangerous", false))))
	add_child(PluginUI.readme_box(plugin_id))
