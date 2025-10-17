extends Control

@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)

func _on_host_pressed():
	print("Hosting game...")
	NetworkManager.host_game("Host Player")

func _on_join_pressed():
	print("Joining game...")
	NetworkManager.join_game("Client Player", "127.0.0.1")

func _on_server_started():
	print("Server started! Going to lobby...")
	get_tree().change_scene_to_file("res://scenes/main_menu/lobby.tscn")

func _on_connection_succeeded():
	print("Connected! Going to lobby...")
	get_tree().change_scene_to_file("res://scenes/main_menu/lobby.tscn")
