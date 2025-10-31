extends Node

signal tick_started(tick_number: int, tick_duration: float)

const TICKS_PER_SECOND := 10
const SERVER_ID := 1

var _tick_interval := 1.0 / TICKS_PER_SECOND
var _accumulator := 0.0
var _current_tick: int = 0
var _running: bool = false

func _ready() -> void:
        set_process(false)

func start_clock() -> void:
        if _running:
                return
        _running = true
        _accumulator = 0.0
        set_process(true)

func stop_clock() -> void:
        _running = false
        set_process(false)

func get_current_tick() -> int:
        return _current_tick

func get_tick_interval() -> float:
        return _tick_interval

func get_deterministic_seed(player_id: int, label: String = "") -> int:
var base_seed: int = NetworkManager.game_seed
var label_hash: int = hash(label)
return int(base_seed) ^ int(player_id) ^ int(_current_tick) ^ int(label_hash)

func create_rng(player_id: int, label: String = "") -> RandomNumberGenerator:
        var rng := RandomNumberGenerator.new()
        rng.seed = get_deterministic_seed(player_id, label)
        return rng

func _process(delta: float) -> void:
        if not _running:
                return

        if multiplayer.is_server():
                _accumulator += delta
                while _accumulator >= _tick_interval:
                        _accumulator -= _tick_interval
                        _current_tick += 1
                        tick_started.emit(_current_tick, _tick_interval)
                        _sync_tick.rpc(_current_tick)

@rpc("authority", "call_local", "unreliable")
func _sync_tick(server_tick: int) -> void:
        _current_tick = server_tick

        if not _running:
                set_process(true)
                _running = true
