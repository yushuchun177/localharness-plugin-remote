extends VBoxContainer
## 远程操作 —— 这个页面是插件自己提供的界面。
## 界面全部由插件自己拼，主程序只提供积木。

func build(plugin_id: String) -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	add_child(PluginUI.section("本机地址"))
	var ip := "未知"
	var out: Array = []
	OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-Command",
		"(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress"]), out, true)
	if out.size() > 0 and str(out[0]).strip_edges() != "":
		ip = str(out[0]).strip_edges()
	add_child(PluginUI.hint("这台机器在局域网里的地址：%s" % ip))

	add_child(PluginUI.section("端口"))
	add_child(PluginUI.slider_row(plugin_id, "port", "用哪个端口", 8000, 9000, 1, "", 8799,
		"对方连你的时候要填这个端口"))

	add_child(PluginUI.section("试一下"))
	add_child(PluginUI.action_row("开一个端点", "局域网里其他机器就能把任务发到这台", "开启",
		func(): return Plugins.invoke("remote_serve", {"port": int(PluginPrefs.get_value(plugin_id, "port", 8799))})))
	add_child(PluginUI.action_row("关掉端点", "", "关闭",
		func(): return Plugins.invoke("remote_stop", {})))
	add_child(PluginUI.overview(plugin_id))
	add_child(PluginUI.permissions_section(plugin_id))
	add_child(PluginUI.doc_section(plugin_id))
