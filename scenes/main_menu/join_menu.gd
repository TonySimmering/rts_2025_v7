extends Control

@onready var ip_input: LineEdit = $VBoxContainer/IPInput
@onready var name_input: LineEdit = $VBoxContainer/NameInput
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var back_button: Button = $VBoxContainer/BackButton

func _ready():
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Connect to NetworkManager signals
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _exit_tree():
	# Disconnect signals when leaving scene
	if NetworkManager.connection_succeeded.is_connected(_on_connection_succeeded):
		NetworkManager.connection_succeeded.disconnect(_on_connection_succeeded)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)

func _on_join_pressed():
	var ip = ip_input.text.strip_edges()
	var player_name = name_input.text.strip_edges()
	
	if ip.is_empty():
		push_error("IP address cannot be empty")
		return
	
	if player_name.is_empty():
		player_name = "Client Player"
	
	print("Joining game at ", ip, " as ", player_name)
	join_button.disabled = true
	join_button.text = "Connecting..."
	NetworkManager.join_game(player_name, ip)

func _on_connection_succeeded():
	print("Connected! Going to lobby...")
	get_tree().change_scene_to_file("res://scenes/main_menu/lobby.tscn")

func _on_connection_failed():
	print("Connection failed!")
	join_button.disabled = false
	join_button.text = "Join"
	push_error("Failed to connect to host")

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
