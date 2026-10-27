extends Node3D

func _input(event):
	if event.is_action_pressed("swap_mode"):
		# Sends you directly back to the 2D arena, skipping the multiplayer lobby
		get_tree().change_scene_to_file("res://scenes/2D/arena.tscn")
