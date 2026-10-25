extends Node2D

const PORT: int = 7000
const DEFAULT_IP: String = "127.0.0.1"
const INPUT_DEADZONE: float = 0.2

const PlayerScript := preload("res://player.gd")

const CHARACTERS: Dictionary = {
	"Bob": Color.CRIMSON,
	"Lexy": Color.MEDIUM_PURPLE,
	"Tony": Color.DODGER_BLUE,
	"Fran": Color(0.314, 0.784, 0.471), # Emerald (#50C878)
	"Dave": Color.GOLD,
}

var players_container: Node2D
var spawner: MultiplayerSpawner

var ui_layer: CanvasLayer
var main_panel: PanelContainer
var connect_box: VBoxContainer
var char_select_box: VBoxContainer
var host_button: Button
var join_button: Button
var ip_input: LineEdit
var status_label: Label


func _ready() -> void:
	_register_input_actions()
	_setup_world_and_spawner()
	_build_ui()
	_setup_multiplayer_signals()

	if OS.has_feature("web"):
		host_button.hide()

	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_start_headless_server()


func _start_headless_server() -> void:
	var port: int = int(OS.get_environment("PORT")) if OS.has_environment("PORT") else PORT
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		print("Failed to start headless WebSocket server on port %d (err %d)" % [port, err])
		return

	multiplayer.multiplayer_peer = peer
	if ui_layer:
		ui_layer.visible = false
	print("Headless WebSocket dedicated server started on port %d" % port)


func _register_input_actions() -> void:
	var action_defs: Dictionary = {
		"move_left": {"key": KEY_A, "axis": JOY_AXIS_LEFT_X, "axis_value": -1.0},
		"move_right": {"key": KEY_D, "axis": JOY_AXIS_LEFT_X, "axis_value": 1.0},
		"move_up": {"key": KEY_W, "axis": JOY_AXIS_LEFT_Y, "axis_value": -1.0},
		"move_down": {"key": KEY_S, "axis": JOY_AXIS_LEFT_Y, "axis_value": 1.0},
	}

	for action_name: String in action_defs.keys():
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)
		InputMap.add_action(action_name, INPUT_DEADZONE)

		var def: Dictionary = action_defs[action_name]

		var key_event := InputEventKey.new()
		key_event.keycode = def["key"]
		key_event.physical_keycode = def["key"]
		InputMap.action_add_event(action_name, key_event)

		var joy_event := InputEventJoypadMotion.new()
		joy_event.axis = def["axis"]
		joy_event.axis_value = def["axis_value"]
		InputMap.action_add_event(action_name, joy_event)


func _setup_world_and_spawner() -> void:
	players_container = Node2D.new()
	players_container.name = "Players"
	add_child(players_container)

	spawner = MultiplayerSpawner.new()
	spawner.name = "MultiplayerSpawner"
	spawner.spawn_function = _spawn_player
	add_child(spawner)
	spawner.spawn_path = spawner.get_path_to(players_container)


func _spawn_player(data: Variant) -> Node:
	var info: Dictionary = data if data is Dictionary else {}
	var peer_id: int = int(info.get("peer_id", 1))
	var char_name: String = str(info.get("char_name", "Player"))
	var char_color: Color = info.get("player_color", Color.WHITE)
	var spawn_pos: Vector2 = info.get("position", Vector2(576.0, 324.0))

	var player: CharacterBody2D = PlayerScript.new()
	player.name = str(peer_id)
	player.player_name = char_name
	player.player_color = char_color
	player.position = spawn_pos
	return player



func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(center)

	main_panel = PanelContainer.new()
	main_panel.name = "MainPanel"
	main_panel.custom_minimum_size = Vector2(320.0, 0.0)
	center.add_child(main_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(root_vbox)

	# State 1: Connect UI
	connect_box = VBoxContainer.new()
	connect_box.name = "ConnectBox"
	connect_box.add_theme_constant_override("separation", 10)
	root_vbox.add_child(connect_box)

	var title_label := Label.new()
	title_label.text = "DnD Brawler - Connect"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connect_box.add_child(title_label)

	host_button = Button.new()
	host_button.name = "HostButton"
	host_button.text = "Host Game"
	host_button.pressed.connect(_on_host_pressed)
	connect_box.add_child(host_button)

	ip_input = LineEdit.new()
	ip_input.name = "AddressInput"
	ip_input.text = DEFAULT_IP
	ip_input.placeholder_text = "Server IP or Render URL"
	ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	connect_box.add_child(ip_input)

	join_button = Button.new()
	join_button.name = "JoinButton"
	join_button.text = "Join Game"
	join_button.pressed.connect(_on_join_pressed)
	connect_box.add_child(join_button)

	# State 2: Character Select UI
	char_select_box = VBoxContainer.new()
	char_select_box.name = "CharacterSelectBox"
	char_select_box.add_theme_constant_override("separation", 8)
	char_select_box.visible = false
	root_vbox.add_child(char_select_box)

	var char_title := Label.new()
	char_title.text = "Select Your Character"
	char_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_select_box.add_child(char_title)

	for char_name: String in CHARACTERS.keys():
		var char_color: Color = CHARACTERS[char_name]
		var btn := Button.new()
		btn.name = char_name + "Button"
		btn.text = char_name
		btn.add_theme_color_override("font_color", char_color)
		btn.add_theme_color_override("font_hover_color", char_color.lightened(0.2))
		btn.add_theme_color_override("font_focus_color", char_color)
		btn.pressed.connect(_on_character_selected.bind(char_name))
		char_select_box.add_child(btn)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = ""
	root_vbox.add_child(status_label)


func _setup_multiplayer_signals() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_host_pressed() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		status_label.text = "Failed to host on port %d (err %d)" % [PORT, err]
		return

	multiplayer.multiplayer_peer = peer
	status_label.text = ""
	_enter_character_select_state()


func _format_websocket_url(raw_input: String) -> String:
	var ip := raw_input.strip_edges()
	if ip.is_empty():
		ip = DEFAULT_IP

	if ip.begins_with("ws://") or ip.begins_with("wss://"):
		return ip

	if ip == "127.0.0.1" or ip == "localhost" or ip.is_valid_ip_address():
		return "ws://" + ip + ":" + str(PORT)

	if ip.contains(".onrender.com") or not ip.contains(":"):
		return "wss://" + ip

	return "ws://" + ip


func _on_join_pressed() -> void:
	var url := _format_websocket_url(ip_input.text)

	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		status_label.text = "Failed to connect to %s (err %d)" % [url, err]
		join_button.disabled = false
		return

	multiplayer.multiplayer_peer = peer
	join_button.disabled = true
	status_label.text = "Connecting to server..."


func _on_connected_to_server() -> void:
	join_button.disabled = false
	status_label.text = ""
	_enter_character_select_state()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	join_button.disabled = false
	status_label.text = "Connection failed."
	connect_box.visible = true
	char_select_box.visible = false
	ui_layer.visible = true


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	join_button.disabled = false
	for child in players_container.get_children():
		child.queue_free()
	status_label.text = "Disconnected from server."
	connect_box.visible = true
	char_select_box.visible = false
	ui_layer.visible = true


func _enter_character_select_state() -> void:
	connect_box.visible = false
	char_select_box.visible = true


func _show_character_select() -> void:
	_enter_character_select_state()


func _on_character_selected(char_name: String) -> void:
	ui_layer.visible = false
	request_spawn_player.rpc_id(1, char_name)


@rpc("any_peer", "call_local", "reliable")
func request_spawn_player(char_name: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	# Remove existing player node for this peer if one already exists
	var existing := players_container.get_node_or_null(str(sender_id))
	if existing:
		existing.queue_free()

	var char_color: Color = CHARACTERS.get(char_name, Color.WHITE)
	var viewport_center := get_viewport_rect().size * 0.5
	if viewport_center == Vector2.ZERO:
		viewport_center = Vector2(576.0, 324.0)

	var offset := Vector2(
		randf_range(-120.0, 120.0),
		randf_range(-120.0, 120.0)
	)

	var spawn_data: Dictionary = {
		"peer_id": sender_id,
		"char_name": char_name,
		"player_color": char_color,
		"position": viewport_center + offset,
	}
	spawner.spawn(spawn_data)


func _on_peer_disconnected(peer_id: int) -> void:
	var player_node := players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
