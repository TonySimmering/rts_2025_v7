extends Control

var selection_manager: Node = null
var box_color: Color = Color(0, 1, 0, 0.3)  # Green with transparency
var border_color: Color = Color(0, 1, 0, 1)  # Solid green border
var was_box_selecting: bool = false  # ADD THIS - track previous state

func _ready():
	# Make this Control fill the screen but not block input
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta):
	if not selection_manager:
		return
	
	# Redraw if box selection state changed OR if actively box selecting
	if selection_manager.is_box_selecting or was_box_selecting != selection_manager.is_box_selecting:
		queue_redraw()
	
	was_box_selecting = selection_manager.is_box_selecting  # UPDATE - store current state

func _draw():
	if not selection_manager or not selection_manager.is_box_selecting:
		return
	
	var start = selection_manager.box_select_start
	var end = selection_manager.box_select_end
	
	# Draw filled rectangle
	var rect = Rect2(start, end - start)
	draw_rect(rect, box_color)
	
	# Draw border
	draw_rect(rect, border_color, false, 2.0)
