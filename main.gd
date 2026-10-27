extends Node2D

const PORT: int = 7000
const DEFAULT_IP: String = "dnd-brawler-server.onrender.com"

const PlayerScene: PackedScene = preload("res://scenes/2D/player.tscn")

const CHARACTERS: Dictionary = {
	"Bob": Color.CRIMSON,
	"Lexy": Color.MEDIUM_PURPLE,
	"Tony": Color.DODGER_BLUE,
	"Fran": Color(0.314, 0.784, 0.471), # Emerald (#50C878)
	"Dave": Color.GOLD,
}

@onready var players_container: Node2D = $Players
@onready var projectiles_container: Node2D = $Projectiles
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

@onready var ui_layer: CanvasLayer = $UI
@onready var menu_panel: PanelContainer = $UI/MenuPanel
@onready var connect_box: VBoxContainer = $UI/MenuPanel/MarginContainer/VBoxContainer/ConnectBox
@onready var char_select_box: VBoxContainer = $UI/MenuPanel/MarginContainer/VBoxContainer/CharacterSelectBox
@onready var host_button: Button = $UI/MenuPanel/MarginContainer/VBoxContainer/ConnectBox/HostButton
@onready var join_button: Button = $UI/MenuPanel/MarginContainer/VBoxContainer/ConnectBox/JoinButton
@onready var ip_input: LineEdit = $UI/MenuPanel/MarginContainer/VBoxContainer/ConnectBox/AddressInput
@onready var status_label: Label = $UI/MenuPanel/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	_setup_ui_signals()
	_setup_multiplayer_signals()

	ip_input.text = (
		DEFAULT_IP
		if OS.has_feature("web") and not ("--local" in OS.get_cmdline_args() or "--local" in OS.get_cmdline_user_args())
		else "127.0.0.1"
	)

	if OS.has_feature("web"):
		host_button.hide()

	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_start_headless_server()


func _start_headless_server() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		print("Failed to start headless WebSocket server on port %d (err %d)" % [PORT, err])
		return

	multiplayer.multiplayer_peer = peer
	if ui_layer:
		ui_layer.visible = false
	print("Headless WebSocket dedicated server started on port 7000")


func _setup_ui_signals() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	for char_name: String in CHARACTERS.keys():
		var btn := char_select_box.get_node_or_null(char_name + "Button") as Button
		if btn:
			btn.pressed.connect(_on_character_selected.bind(char_name))


func _spawn_player(data: Variant) -> Node:
	var info: Dictionary = data if data is Dictionary else {}
	var peer_id: int = int(info.get("peer_id", 1))
	var char_name: String = str(info.get("char_name", "Player"))
	var char_color: Color = info.get("player_color", Color.WHITE)
	var spawn_pos: Vector2 = info.get("position", Vector2(576.0, 324.0))

	var player: CharacterBody2D = PlayerScene.instantiate()
	player.name = str(peer_id)
	player.player_name = char_name
	player.player_color = char_color
	player.position = spawn_pos
	return player


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

	if ip.begins_with("https://"):
		ip = ip.trim_prefix("https://")
	elif ip.begins_with("http://"):
		ip = ip.trim_prefix("http://")

	while ip.ends_with("/"):
		ip = ip.left(-1)

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
	for child in projectiles_container.get_children():
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

func _input(event):
	if event.is_action_pressed("swap_mode"):
		# This forces the scene to change directly to your new 3D world
		get_tree().change_scene_to_file("res://scenes/3D/world_3d.tscn")
