extends Node

signal commands_applied(command_type: String, unit_paths: Array, metadata: Dictionary)

const COMMAND_MOVE := "move"
const COMMAND_GATHER := "gather"
const COMMAND_BUILD := "build"

const FlowField := preload("res://scripts/flow_field.gd")
const ConstructionSite := preload("res://scripts/construction_site.gd")

func request_move_command(
        unit_paths: Array,
        target_positions: Array,
        facing_angle: float,
        queue_mode: bool,
        formation_center: Vector3,
        use_flow_field: bool
) -> void:
        var payload := {
                "units": unit_paths,
                "targets": target_positions,
                "angle": facing_angle,
                "queue": queue_mode,
                "center": formation_center,
                "flow": use_flow_field
        }

        if multiplayer.is_server():
                _apply_move_command(payload)
        else:
                rpc_id(1, "_server_receive_move_command", payload)

@rpc("any_peer", "call_remote", "reliable")
func _server_receive_move_command(payload: Dictionary) -> void:
        if not multiplayer.is_server():
                return
        _apply_move_command(payload)

func _apply_move_command(payload: Dictionary) -> void:
        if not payload.has("units"):
                return

        var unit_refs: Array = _resolve_units(payload.units)
        var target_positions: Array = payload.get("targets", [])
        var facing_angle: float = payload.get("angle", 0.0)
        var queue_mode: bool = payload.get("queue", false)
        var formation_center: Vector3 = payload.get("center", Vector3.ZERO)
        var use_flow_field: bool = payload.get("flow", false)

        if unit_refs.is_empty():
                return

        var flow_field_data: Dictionary = {}
        if use_flow_field:
                flow_field_data = _build_flow_field(unit_refs, formation_center)

        for i in range(min(unit_refs.size(), target_positions.size())):
                var unit: Node = unit_refs[i]
                if not unit:
                        continue

                if not unit.has_method("queue_command"):
                        continue

                var command := UnitCommand.new(UnitCommand.CommandType.MOVE)
                command.target_position = target_positions[i]
                command.facing_angle = facing_angle

                if use_flow_field and not flow_field_data.is_empty():
                        command.metadata = {
                                "flow_field": flow_field_data.get("field", []),
                                "flow_goal": flow_field_data.get("goal", formation_center),
                                "flow_bounds": flow_field_data.get("bounds", {})
                        }

                unit.queue_command(command, queue_mode)

        commands_applied.emit(COMMAND_MOVE, payload.units, payload)

func request_gather_command(unit_paths: Array, resource_path: NodePath, queue_mode: bool) -> void:
        var payload := {
                "units": unit_paths,
                "resource": resource_path,
                "queue": queue_mode
        }

        if multiplayer.is_server():
                _apply_gather_command(payload)
        else:
                rpc_id(1, "_server_receive_gather_command", payload)

@rpc("any_peer", "call_remote", "reliable")
func _server_receive_gather_command(payload: Dictionary) -> void:
        if not multiplayer.is_server():
                return
        _apply_gather_command(payload)

func _apply_gather_command(payload: Dictionary) -> void:
        var resource: Node = get_node_or_null(payload.get("resource", NodePath()))
        if not resource or not is_instance_valid(resource):
                return

        var unit_refs: Array = _resolve_units(payload.units)
        if unit_refs.is_empty():
                return

        for unit in unit_refs:
                if not unit or not unit.has_method("queue_command"):
                        continue

                var command := UnitCommand.new(UnitCommand.CommandType.GATHER)
                command.target_entity = resource
                command.target_position = resource.global_position

                unit.queue_command(command, payload.get("queue", false))

        commands_applied.emit(COMMAND_GATHER, payload.units, payload)

func request_build_command(unit_paths: Array, site_path: NodePath, queue_mode: bool) -> void:
        var payload := {
                "units": unit_paths,
                "site": site_path,
                "queue": queue_mode
        }

        if multiplayer.is_server():
                _apply_build_command(payload)
        else:
                rpc_id(1, "_server_receive_build_command", payload)

@rpc("any_peer", "call_remote", "reliable")
func _server_receive_build_command(payload: Dictionary) -> void:
        if not multiplayer.is_server():
                return
        _apply_build_command(payload)

func _apply_build_command(payload: Dictionary) -> void:
        var site: Node = get_node_or_null(payload.get("site", NodePath()))
        if not site or not is_instance_valid(site):
                return

        var unit_refs: Array = _resolve_units(payload.units)
        if unit_refs.is_empty():
                return

        var building_type := ""
        var rotation := site.global_rotation.y
        var size := Vector3.ZERO

        if site is ConstructionSite:
                building_type = site.building_type
                rotation = site.target_rotation
                size = site.building_size

        for unit in unit_refs:
                if not unit or not unit.has_method("queue_command"):
                        continue

                var command := UnitCommand.new(UnitCommand.CommandType.BUILD)
                command.target_position = site.global_position
                command.building_type = building_type
                command.metadata = {
                        "position": site.global_position,
                        "rotation": rotation,
                        "size": size,
                        "building_type": building_type
                }

                unit.queue_command(command, payload.get("queue", false))

        commands_applied.emit(COMMAND_BUILD, payload.units, payload)

func _resolve_units(unit_paths: Array) -> Array:
        var resolved: Array = []
        for item in unit_paths:
                var path := NodePath(item)
                var unit := get_node_or_null(path)
                if unit and is_instance_valid(unit):
                        resolved.append(unit)
        return resolved

func _build_flow_field(unit_refs: Array, formation_center: Vector3) -> Dictionary:
        if unit_refs.is_empty():
                return {}

        var world := get_tree().root.get_world_3d()
        if world == null:
                return {}

        var nav_map := world.navigation_map
        if not nav_map.is_valid():
                return {}

        var bounds_min := Vector3(INF, 0, INF)
        var bounds_max := Vector3(-INF, 0, -INF)

        for unit in unit_refs:
                if not unit:
                        continue
                var pos: Vector3 = unit.global_position
                bounds_min.x = min(bounds_min.x, pos.x)
                bounds_min.z = min(bounds_min.z, pos.z)
                bounds_max.x = max(bounds_max.x, pos.x)
                bounds_max.z = max(bounds_max.z, pos.z)

        bounds_min.x = min(bounds_min.x, formation_center.x)
        bounds_min.z = min(bounds_min.z, formation_center.z)
        bounds_max.x = max(bounds_max.x, formation_center.x)
        bounds_max.z = max(bounds_max.z, formation_center.z)

        bounds_min.x -= 10.0
        bounds_min.z -= 10.0
        bounds_max.x += 10.0
        bounds_max.z += 10.0

        var field := FlowField.calculate_flow_field(
                nav_map,
                formation_center,
                bounds_min,
                bounds_max
        )

        var field_entries: Array = []
        for cell in field.keys():
                field_entries.append({"cell": cell, "dir": field[cell]})

        return {
                "field": field_entries,
                "goal": formation_center,
                "bounds": {"min": bounds_min, "max": bounds_max}
        }
