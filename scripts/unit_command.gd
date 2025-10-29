extends RefCounted
class_name UnitCommand

enum CommandType {
	MOVE,
	GATHER,
	BUILD,
	ATTACK,
	PATROL
}

var type: CommandType
var target_position: Vector3 = Vector3.ZERO
var target_entity: Node = null  # For gather/attack/build
var facing_angle: float = 0.0
var building_type: String = ""  # For build commands
var metadata: Dictionary = {}  # Extra data

func _init(cmd_type: CommandType):
	type = cmd_type

func _to_string() -> String:
	match type:
		CommandType.MOVE:
			return "MOVE to " + str(target_position)
		CommandType.GATHER:
			return "GATHER at " + str(target_position)
		CommandType.BUILD:
			return "BUILD " + building_type + " at " + str(target_position)
		CommandType.ATTACK:
			return "ATTACK " + str(target_entity)
		CommandType.PATROL:
			return "PATROL to " + str(target_position)
	return "UNKNOWN"

# Serialization for network sync
func to_dict() -> Dictionary:
	var dict = {
		"type": type,
		"target_position": target_position,
		"facing_angle": facing_angle,
		"building_type": building_type,
		"metadata": metadata
	}
	
	# Serialize entity path for network sync (can't send Node directly)
	if target_entity and is_instance_valid(target_entity):
		dict["target_entity_path"] = target_entity.get_path()
	
	return dict

static func from_dict(data: Dictionary) -> UnitCommand:
	var cmd = UnitCommand.new(data.get("type", CommandType.MOVE))
	cmd.target_position = data.get("target_position", Vector3.ZERO)
	cmd.facing_angle = data.get("facing_angle", 0.0)
	cmd.building_type = data.get("building_type", "")
	cmd.metadata = data.get("metadata", {})
	
	# Note: target_entity will be resolved in worker.gd based on position
	# since Node references can't be sent over network
	
	return cmd
