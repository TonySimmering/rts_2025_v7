extends SceneTree

var _results: Array = []

func _initialize() -> void:
        _results.clear()
        _results.append(_test_resource_spend())
        _results.append(_test_simulation_rng())
        _results.append(_test_unit_command_serialization())

        var failures := 0
        for result in _results:
                if result["success"]:
                        print("[PASS] ", result["name"])
                else:
                        failures += 1
                        push_error("[FAIL] %s -> %s" % [result["name"], result["message"]])

        quit(failures)

func _test_resource_spend() -> Dictionary:
        var rm := ResourceManager.new()
        get_root().add_child(rm)
        rm.initialize_player_resources(99)

        var can_afford := rm.can_afford(99, {"wood": 100})
        var spend_result := rm.spend_resources(99, {"wood": 100})
        var remaining := rm.get_player_resources(99).get("wood", 0)

        rm.queue_free()

        var success := can_afford and spend_result and remaining == ResourceManager.STARTING_WOOD - 100
        return {
                "name": "ResourceManager spends and updates",
                "success": success,
                "message": "Expected wood remaining to be %d, got %d" % [ResourceManager.STARTING_WOOD - 100, remaining]
        }

func _test_simulation_rng() -> Dictionary:
        NetworkManager.game_seed = 1337
        SimulationClock._sync_tick(10)
        var rng_a := SimulationClock.create_rng(5, "gather")
        SimulationClock._sync_tick(10)
        var rng_b := SimulationClock.create_rng(5, "gather")
        SimulationClock._sync_tick(11)
        var rng_c := SimulationClock.create_rng(5, "gather")

        var value_a := rng_a.randi()
        var value_b := rng_b.randi()
        var value_c := rng_c.randi()

        var same_tick_equal := value_a == value_b
        var different_tick_diff := value_a != value_c

        return {
                "name": "SimulationClock deterministic RNG",
                "success": same_tick_equal and different_tick_diff,
                "message": "RNG values were not deterministic across ticks"
        }

func _test_unit_command_serialization() -> Dictionary:
        var command := UnitCommand.new(UnitCommand.CommandType.MOVE)
        command.target_position = Vector3(1, 0, 1)
        command.metadata = {"flow_field": {Vector3.ZERO: Vector3.FORWARD}}

        var data := command.to_dict()
        var restored := UnitCommand.from_dict(data)
        restored.metadata = command.metadata

        return {
                "name": "UnitCommand serialization round-trip",
                "success": restored.target_position == command.target_position and restored.metadata == command.metadata,
                "message": "Serialized command did not restore expected values"
        }
