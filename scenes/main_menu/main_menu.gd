extends Control

@onready var player_name_input: LineEdit = $VBoxContainer/PlayerNameInput
@onready var host_button: Button = $VBoxContainer/HBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/HBoxContainer/JoinButton
@onready var join_panel: VBoxContainer = $VBoxContainer/JoinPanel
@onready var ip_input: LineEdit = $VBoxContainer/JoinPanel/IPInput
@onready var connect_button: Button = $VBoxContainer/JoinPanel/ConnectButton
@onready var status_label: Label = $StatusLabel

func _ready():
	player_name_input.text = "Player"
	ip_input.text = "127.0.0.1"
	join_panel.visible = false
	
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	connect_button.pressed.connect(_on_connect_pressed)
	
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _on_host_pressed():
	var player_name = player_name_input.text.strip_edges()
	if player_name.is_empty():
		show_status("Please enter a player name", true)
		return
	
	disable_buttons()
	show_status("Starting server...", false)
	
	if NetworkManager.host_game(player_name):
		pass
	else:
		show_status("Failed to start server", true)
		enable_buttons()

func _on_join_pressed():
	join_panel.visible = not join_panel.visible
	if join_panel.visible:
		join_button.text = "Cancel"
	else:
		join_button.text = "Join Game"

func _on_connect_pressed():
	var player_name = player_name_input.text.strip_edges()
	var ip = ip_input.text.strip_edges()
	
	if player_name.is_empty():
		show_status("Please enter a player name", true)
		return
	
	if ip.is_empty():
		show_status("Please enter server IP", true)
		return
	
	disable_buttons()
	show_status("Connecting to " + ip + "...", false)
	
	if not NetworkManager.join_game(player_name, ip):
		show_status("Failed to connect", true)
		enable_buttons()

func _on_server_started():
	show_status("Server started! Waiting for players...", false)
	load_lobby()

func _on_connection_succeeded():
	show_status("Connected to server!", false)
	load_lobby()

func _on_connection_failed():
	show_status("Connection failed", true)
	enable_buttons()

func load_lobby():
	get_tree().change_scene_to_file("res://scenes/main_menu/lobby.tscn")

func disable_buttons():
	host_button.disabled = true
	join_button.disabled = true
	connect_button.disabled = true

func enable_buttons():
	host_button.disabled = false
	join_button.disabled = false
	connect_button.disabled = false

func show_status(text: String, is_error: bool):
	status_label.text = text
	status_label.modulate = Color.RED if is_error else Color.WHITE
