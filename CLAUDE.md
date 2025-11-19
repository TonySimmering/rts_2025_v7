# CLAUDE.md - AI Assistant Guide for RTS 2025 v7

> **Last Updated:** 2025-11-19
> **Godot Version:** 4.5 (Forward Plus)
> **Project Type:** Real-Time Strategy (RTS) Game
> **Total Lines of Code:** ~11,000 (scripts + scenes)

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture & Key Systems](#architecture--key-systems)
3. [Directory Structure](#directory-structure)
4. [Core Game Systems](#core-game-systems)
5. [Development Workflows](#development-workflows)
6. [Code Conventions](#code-conventions)
7. [Common Tasks & Patterns](#common-tasks--patterns)
8. [Testing & Debugging](#testing--debugging)
9. [Important Gotchas](#important-gotchas)
10. [Git Workflow](#git-workflow)

---

## Project Overview

### What is This?

This is a **multiplayer RTS game** built in Godot 4.5 featuring:
- **Networked multiplayer** (2-8 players via ENet)
- **Advanced building placement** with magnetic snapping system
- **Worker units** that gather resources and construct buildings
- **Economy system** (wood, gold, stone, food, population)
- **Fog of war** with 3-state visibility per player
- **Formation-based unit control** (Line, Square, Wedge, Circle)
- **Procedurally generated terrain** with FastNoise

### Key Features

1. **Magnetic Building Snapping** - Buildings snap to edges/corners of nearby buildings within 4.5 units with smooth interpolation and visual feedback
2. **Server-Authoritative Multiplayer** - Client-side prediction for responsiveness, server validation for security
3. **Component-Based Placement** - Modular architecture (SnapPointDetector, BuildingSnapController, GridManager, PlacementVisualizer)
4. **Smart Unit AI** - Command queues, stuck detection, path recalculation, formation management
5. **Visibility System** - Per-player fog of war with unexplored/explored/visible states

### Current State

- **Playable:** Yes, multiplayer functional
- **Production Ready:** Prototype/MVP stage
- **Recent Work:** Fog of war rendering fixes, magnetic snapping system overhaul
- **Active Development:** Building placement, unit AI, multiplayer stability

---

## Architecture & Key Systems

### Autoload Singletons (Global Managers)

These are **always available** via their names (e.g., `NetworkManager.method()`):

```gdscript
NetworkManager        # scripts/autoloads/network_manager.gd
ResourceManager       # scripts/autoloads/resource_manager.gd
FogOfWarManager       # scripts/autoloads/fog_of_war_manager.gd
```

**NetworkManager** responsibilities:
- Hosts/joins games via ENet
- Player connection tracking
- RPC routing and synchronization
- Game seed distribution for deterministic terrain

**ResourceManager** responsibilities:
- Per-player resource tracking (wood, gold, stone, food)
- Population cap management
- Server-authoritative resource validation
- Network sync via RPC

**FogOfWarManager** responsibilities:
- Per-player 128x128 visibility grids
- 3-state system (UNEXPLORED=0, EXPLORED=1, VISIBLE=2)
- Vision range calculations (units: 10, buildings: 15-20)
- Multiplayer-safe independent grids

### Main Game Flow

```
MainMenu (main_menu.tscn)
  └─> Lobby (lobby.tscn)
      └─> Host creates server OR Client joins
          └─> Game scene (game.tscn) loaded for all players
```

**Game scene initialization order:**
1. NetworkManager connects players
2. SpawnManager distributes starting units/buildings
3. Terrain generates with shared seed (deterministic)
4. CameraRig, UI, SelectionManager, BuildingPlacementManager initialized
5. FogOfWarManager sets up per-player grids
6. Game loop starts

### Building Placement System Architecture

**Most sophisticated system in the codebase.** See `MAGNETIC_SNAPPING_GUIDE.md` for full 350-line documentation.

```
BuildingPlacementManager (workflow controller)
  └─> creates BuildingGhost (preview)
      ├─> BuildingSnapController (snap state machine)
      │   └─> SnapPointDetector (finds snap points)
      ├─> GridManager (4.0 unit grid alignment)
      └─> PlacementVisualizer (visual feedback)
```

**Key constants:**
- `SNAP_DISTANCE: 4.5` - Trigger magnetic snap
- `UNSNAP_DISTANCE: 7.0` - Release from snap (magnetic "stickiness")
- `SMOOTH_SNAP_SPEED: 10.0` - Interpolation speed
- `DEFAULT_GRID_SIZE: 4.0` - Grid cell size

**Placement validation pipeline:**
```
1. Terrain slope < 30% (MAX_TERRAIN_SLOPE: 0.3)
2. No obstacle collision (except snap target)
3. NavMesh proximity within 2.0 units
4. Resource affordability check
5. Construction site space available
```

### Unit Command System

**Pattern:** Command queue with sequential execution

```gdscript
# Command types (UnitCommand class)
MOVE      # Move to position
GATHER    # Gather from resource node
BUILD     # Construct building
ATTACK    # Attack enemy
PATROL    # Patrol between points

# Worker execution flow
Worker receives commands → Queues commands → Executes sequentially → Signals completion
```

**Key files:**
- `scripts/unit_command.gd` - Command data structure
- `scripts/units/worker.gd` - Command execution logic
- `scripts/formation_manager.gd` - Formation calculations

### Multiplayer Architecture

**Authority model:**
- **Server-authoritative** for: Resource spending, building placement validation, unit spawning
- **Client-side prediction** for: Ghost placement, unit selection, camera movement
- **RPC synchronization** for: Resource updates, construction progress, unit commands

**Player organization:**
```gdscript
# Groups (used for queries)
"player_%d_units" % player_id
"player_%d_buildings" % player_id
"player_%d_construction_sites" % player_id

# Each entity sets multiplayer authority
set_multiplayer_authority(player_id)
```

---

## Directory Structure

```
rts_2025_v7/
├── addons/
│   └── GDTerminal/                 # Debug terminal addon
│
├── assets/
│   ├── models/
│   │   └── worker.glb              # Worker 3D model with animations
│   └── textures/
│       └── terrain/                # Grass, dirt, rock, snow textures + normals
│
├── scenes/
│   ├── buildings/                  # Building prefabs (.tscn + .gd)
│   │   ├── town_center.*           # 8x6x8, worker production, 10 pop cap
│   │   ├── barracks.*              # 6x5x6, soldier training
│   │   └── house.*                 # 4x4x4, population housing
│   ├── camera/
│   │   └── camera_rig.*            # Isometric camera with WASD + Q/E rotation
│   ├── game/
│   │   └── game.*                  # Main game scene (entry point)
│   ├── main_menu/
│   │   ├── main_menu.*
│   │   ├── lobby.*
│   │   └── join_menu.*
│   ├── terrain/
│   │   └── terrain.*               # Procedural terrain + shaders
│   └── units/
│       └── worker.*                # Worker unit prefab
│
├── scripts/
│   ├── autoloads/                  # Global singletons (see above)
│   ├── placement/                  # Building placement system (4 files)
│   ├── resources/                  # Resource nodes (gold, stone, trees)
│   ├── ui/                         # All UI controllers
│   ├── building_base.gd            # Base class for all buildings
│   ├── building_ghost.gd           # Placement preview
│   ├── building_placement_manager.gd
│   ├── construction_site.gd        # In-progress building state
│   ├── formation_manager.gd        # Formation calculations
│   ├── flow_field.gd               # Flow field pathfinding
│   ├── fog_of_war_overlay.gd       # Fog rendering
│   ├── selection_manager.gd        # Unit/building selection
│   ├── spawn_manager.gd            # Initial unit/building spawns
│   └── unit_command.gd             # Command data structure
│
├── shaders/
│   ├── fog_of_war.gdshader         # Fog visibility shader
│   └── glass_ui.gdshader           # UI glass effect
│
├── project.godot                   # Godot project config
├── MAGNETIC_SNAPPING_GUIDE.md      # 350+ line placement guide
└── CLAUDE.md                       # This file
```

---

## Core Game Systems

### 1. Building System

**Base class:** `scripts/building_base.gd`

All buildings inherit from BuildingBase:
```gdscript
extends BuildingBase
class_name TownCenter

# Override these as needed
func _ready():
    super._ready()
    # Custom initialization
```

**Building sizes (hardcoded in BuildingGhost.set_building_type()):**
```gdscript
Town Center:  Vector3(8, 6, 8)
Barracks:     Vector3(6, 5, 6)
House:        Vector3(4, 4, 4)
```

**Building costs (BuildingPlacementManager.BUILDING_COSTS):**
```gdscript
{
    "town_center": {"wood": 400, "gold": 200},
    "barracks": {"wood": 150, "gold": 50},
    "house": {"wood": 50}
}
```

**Construction times (BuildingPlacementManager.CONSTRUCTION_TIMES):**
```gdscript
{
    "town_center": 60.0,   # seconds
    "barracks": 30.0,
    "house": 20.0
}
```

**Adding a new building type:**
1. Create scene in `scenes/buildings/new_building.tscn`
2. Create script extending BuildingBase
3. Add size to `BuildingGhost.set_building_type()`
4. Add cost to `BuildingPlacementManager.BUILDING_COSTS`
5. Add construction time to `BuildingPlacementManager.CONSTRUCTION_TIMES`
6. Add UI button in `command_panel_ui.tscn`

### 2. Unit System

**Worker unit:** `scripts/units/worker.gd`

Key properties:
- `move_speed: 3.0` - Units per second
- `gathering_range: 2.5` - Distance to gather resources
- `building_range: 3.0` - Distance to build
- `carry_capacity: 20` - Max resources carried

**Worker state machine:**
```
IDLE → MOVING → GATHERING → RETURNING → BUILDING → IDLE
```

**Stuck detection:**
- Checks position every 0.5s
- If stuck for 2.0s, attempts recovery
- Max 3 recovery attempts before giving up

**Path recalculation:**
- Every 2.0s during movement
- Handles dynamic obstacles (new buildings)

### 3. Resource System

**Resource types:**
- `wood` - From trees (not yet implemented)
- `gold` - From gold deposits
- `stone` - From stone deposits
- `food` - From farms (not yet implemented)

**Population system:**
- Town Center: +10 max population
- House: +5 max population (configurable)
- Workers: 1 population each
- Population tracked per player

**ResourceManager API:**
```gdscript
# Query resources
ResourceManager.get_resource(player_id, "wood")
ResourceManager.get_population(player_id)

# Spend resources (server-authoritative)
ResourceManager.can_afford(player_id, costs_dict)
ResourceManager.spend_resources(player_id, costs_dict)

# Add resources
ResourceManager.add_resource(player_id, "gold", 100)
```

### 4. Fog of War System

**3-state visibility per player:**
```gdscript
UNEXPLORED = 0  # Black fog, never seen
EXPLORED = 1    # Grey fog, previously seen
VISIBLE = 2     # No fog, currently visible
```

**Vision ranges:**
- Worker units: 10 units
- Town Center: 20 units
- Barracks: 15 units
- House: 15 units

**FogOfWarManager API:**
```gdscript
# Update visibility (called automatically)
FogOfWarManager.update_visibility(player_id, units_array, buildings_array)

# Query visibility
FogOfWarManager.is_position_visible(player_id, world_pos)
FogOfWarManager.is_position_explored(player_id, world_pos)
```

**Rendering:**
- Custom shader in `shaders/fog_of_war.gdshader`
- Applied to fog plane mesh in `scripts/fog_of_war_overlay.gd`

### 5. Selection System

**Selection Manager:** `scripts/selection_manager.gd`

**Selection modes:**
1. **Single-click** - Select individual unit/building
2. **Box-select** - Drag rectangle to select multiple units
3. **Shift-click** - Add to existing selection

**Input handling:**
```gdscript
# Uses _unhandled_input() to avoid conflicting with UI
func _unhandled_input(event):
    if event is InputEventMouseButton:
        # Handle clicks
    elif event is InputEventMouseMotion:
        # Handle box select dragging
```

**Rally point mode:**
- Right-click building → Right-click destination
- Sets rally point for spawned units

### 6. Camera System

**Camera Rig:** `scenes/camera/camera_rig.gd`

**Controls:**
- `WASD` - Pan camera
- `Q/E` - Rotate 45° increments
- `Scroll wheel` - Zoom in/out
- `Mouse edge panning` - Move to screen edges (optional)

**Camera properties:**
```gdscript
pan_speed: 20.0
rotation_speed: 2.0
zoom_speed: 5.0
min_height: 10.0
max_height: 50.0
```

**Isometric setup:**
- Fixed 45° pitch angle
- Rotates around pivot point
- Follows terrain height (optional)

### 7. Terrain Generation

**Terrain:** `scenes/terrain/terrain.gd`

**Generation parameters (export vars):**
```gdscript
@export var size: Vector2i = Vector2i(128, 128)
@export var height_scale: float = 20.0
@export var noise_frequency: float = 0.02
@export var noise_octaves: int = 3
```

**Generation pipeline:**
1. FastNoise generates height values
2. Mesh constructed with SurfaceTool
3. NavMesh baked automatically
4. Resource nodes placed procedurally
5. Forests generated (optional)

**Texture blending (height-based):**
- Low: Grass
- Medium: Dirt
- High: Rock
- Very high: Snow

---

## Development Workflows

### Running the Game

**In Godot Editor:**
1. Open project in Godot 4.5
2. Press `F5` (Run Project)
3. Main menu appears
4. Host or join multiplayer game

**Multiplayer testing (local):**
1. Run main scene (`F5`)
2. Click "Host Game"
3. Run scene again in new window (`Shift+F5` or external editor instance)
4. Click "Join Game" with localhost IP

### Debugging

**Godot debugger:**
- `F5` - Run with debugger attached
- `Ctrl+Shift+F5` - Run without debugger
- Use `print()` and `print_debug()` liberally
- Remote inspector shows live scene tree

**Common debug locations:**
```gdscript
# Print resource state
print(ResourceManager.get_all_resources(player_id))

# Print selection
print(SelectionManager.get_selected_units())

# Print fog state
print(FogOfWarManager.get_visibility_at(player_id, pos))
```

**Terminal addon:**
- `addons/GDTerminal/` provides in-game console
- Execute GDScript commands during runtime
- Enable in Project → Project Settings → Plugins

### Building for Export

**Export presets:** `export_presets.cfg`

Currently configured for:
- Windows Desktop
- Linux Desktop
- macOS

**To export:**
1. Project → Export
2. Select preset
3. Click "Export Project"
4. Choose destination

---

## Code Conventions

### GDScript Style

**Follow these patterns (already established in codebase):**

```gdscript
# Use class_name for type safety
class_name BuildingBase
extends StaticBody3D

# Type hints everywhere
var current_health: float = 100.0
var player_id: int = -1

# Export variables for editor configuration
@export var max_health: float = 500.0
@export var vision_range: float = 15.0

# Signals for decoupled communication
signal health_changed(new_health: float)
signal building_destroyed()

# Constants in SCREAMING_SNAKE_CASE
const MAX_UNITS: int = 200
const SNAP_DISTANCE: float = 4.5

# Private variables prefixed with underscore
var _cached_position: Vector3

# Function names in snake_case
func take_damage(amount: float) -> void:
    current_health -= amount
    health_changed.emit(current_health)
```

### Networking Patterns

**RPC decorators:**
```gdscript
# Call on all peers
@rpc("any_peer", "call_local", "reliable")
func sync_construction_progress(progress: float):
    pass

# Server-only authority
@rpc("authority", "call_local", "reliable")
func server_validate_placement(building_type: String, position: Vector3):
    pass
```

**Authority checks:**
```gdscript
func _physics_process(delta):
    # Only run on authoritative instance
    if not is_multiplayer_authority():
        return

    # Movement logic here
```

**Player ID convention:**
```gdscript
# Player IDs match multiplayer peer IDs
var player_id: int = multiplayer.get_unique_id()

# Groups follow pattern
add_to_group("player_%d_units" % player_id)
```

### File Organization

**Scene + Script pairs:**
```
town_center.tscn    # Scene file
town_center.gd      # Script file (same name)
```

**Script locations:**
- `scripts/` - Core game logic (not scene-specific)
- `scenes/*/` - Scene-specific scripts (e.g., `scenes/buildings/town_center.gd`)

**Autoloads:**
- Always in `scripts/autoloads/`
- Registered in `project.godot` under `[autoload]`

### Collision Layers

```
Layer 1: Terrain (default)
Layer 2: Units
Layer 3: Resources
Layer 8: Buildings & Construction Sites
```

**Setting collision layers:**
```gdscript
# Buildings use layer 8
collision_layer = 1 << 7  # Bit 8
collision_mask = 0        # Don't collide with anything
```

### Signals vs Direct Calls

**Prefer signals for:**
- UI updates (e.g., `resources_changed`)
- Cross-system communication (e.g., `building_completed`)
- Event broadcasting (e.g., `unit_selected`)

**Use direct calls for:**
- Same-system operations
- Performance-critical paths
- Simple getter/setter operations

---

## Common Tasks & Patterns

### Adding a New Building Type

**Step-by-step:**

1. **Create scene** (`scenes/buildings/farm.tscn`):
   ```gdscript
   Farm (StaticBody3D)
   ├── MeshInstance3D (visual)
   ├── CollisionShape3D
   └── NavigationObstacle3D
   ```

2. **Create script** (`scenes/buildings/farm.gd`):
   ```gdscript
   extends BuildingBase
   class_name Farm

   func _ready():
       super._ready()
       vision_range = 10.0
       max_health = 300.0
   ```

3. **Add size to BuildingGhost** (`scripts/building_ghost.gd`):
   ```gdscript
   func set_building_type(type: String):
       match type:
           "farm":
               building_size = Vector3(5, 4, 5)
   ```

4. **Add costs** (`scripts/building_placement_manager.gd`):
   ```gdscript
   const BUILDING_COSTS = {
       "farm": {"wood": 75, "gold": 25}
   }

   const CONSTRUCTION_TIMES = {
       "farm": 25.0
   }
   ```

5. **Add UI button** (`scenes/ui/command_panel_ui.tscn`):
   - Add Button node
   - Connect `pressed` signal to `_on_farm_button_pressed()`

6. **Update SpawnManager** (if it should spawn at game start):
   ```gdscript
   # In spawn_manager.gd
   func create_starting_buildings(player_id: int, spawn_pos: Vector3):
       # Add farm if needed
   ```

### Adding a New Unit Type

**Similar to buildings, but extends CharacterBody3D:**

1. **Create scene** (`scenes/units/soldier.tscn`)
2. **Create script extending worker or custom base**
3. **Add to spawn system**
4. **Add training to barracks production queue**

### Modifying Snap Behavior

**Adjust snapping distance:**
```gdscript
# In scripts/placement/building_snap_controller.gd
const SNAP_DISTANCE: float = 6.0      # Increased from 4.5
const UNSNAP_DISTANCE: float = 9.0    # Increased from 7.0
```

**Change snap priority:**
```gdscript
# In scripts/placement/snap_point_detector.gd
func _calculate_snap_priority(snap_point: SnapPoint, distance: float) -> float:
    var base_priority = 1.0 if snap_point.type == SnapType.EDGE else 3.0  # Increased corner penalty
    return base_priority + (distance / 10.0)
```

### Adding Visual Feedback

**Placement visualizer:**
```gdscript
# In scripts/placement/placement_visualizer.gd

# Add new visualization type
func draw_custom_indicator(position: Vector3):
    var mesh = MeshInstance3D.new()
    mesh.mesh = SphereMesh.new()
    mesh.position = position
    add_child(mesh)
```

### Debugging Multiplayer Issues

**Common debugging patterns:**

```gdscript
# Print on server only
if multiplayer.is_server():
    print("Server: ", message)

# Print with peer ID
print("[Peer %d] %s" % [multiplayer.get_unique_id(), message])

# Verify authority
if not is_multiplayer_authority():
    push_warning("Attempted action without authority!")
    return
```

**Test multiplayer locally:**
- Use `--server` command line flag for dedicated server
- Run multiple editor instances
- Use `NetworkManager.DEBUG_MODE = true` for verbose logging

---

## Testing & Debugging

### Manual Testing Checklist

**Building placement:**
- [ ] Ghost appears when building selected
- [ ] Ghost snaps to nearby buildings
- [ ] Green when valid, red when invalid
- [ ] Placement creates construction site
- [ ] Resources deducted correctly

**Unit commands:**
- [ ] Single unit move commands work
- [ ] Formation move commands work
- [ ] Gathering commands work
- [ ] Building commands work
- [ ] Stuck detection recovers

**Multiplayer:**
- [ ] Can host and join games
- [ ] Resources sync between clients
- [ ] Construction progress syncs
- [ ] Unit movements sync
- [ ] Fog of war is per-player

**Fog of war:**
- [ ] Unexplored areas are black
- [ ] Explored areas are grey
- [ ] Visible areas are clear
- [ ] Updates with unit movement

### Performance Profiling

**Godot profiler:**
- Debug → Profiler
- Monitor → Monitors (FPS, memory, etc.)

**Performance targets:**
- 60 FPS with 100+ units
- < 100ms network latency
- < 500 MB memory usage

**Common bottlenecks:**
- Snap point detection (spatial partitioning helps)
- NavMesh queries (cache results)
- Fog of war updates (only update changed regions)
- Mesh rendering (use LOD for distant buildings)

### Common Issues & Solutions

**Issue: Buildings won't snap**
- Check `SNAP_DISTANCE` constant
- Verify buildings are in correct player group
- Ensure `BuildingSnapController` is initialized

**Issue: Units get stuck**
- Increase stuck detection threshold
- Check NavMesh is properly baked
- Verify obstacle avoidance is enabled

**Issue: Resources don't sync**
- Ensure `ResourceManager.spend_resources()` is called on server
- Check RPC decorators are correct
- Verify multiplayer authority

**Issue: Fog of war doesn't update**
- Check `FogOfWarManager.update_visibility()` is called
- Verify vision ranges are set correctly
- Ensure fog plane shader is assigned

---

## Important Gotchas

### 1. Building Sizes are Hardcoded

Building sizes are **not** read from scenes - they're hardcoded in `BuildingGhost.set_building_type()`. If you change a building's visual size, **you must update the size in BuildingGhost** or snapping will be incorrect.

```gdscript
# In building_ghost.gd - MUST match visual size
func set_building_type(type: String):
    match type:
        "town_center":
            building_size = Vector3(8, 6, 8)  # Must match actual model
```

### 2. Multiplayer Authority Must Be Set

Every networked entity **must** call `set_multiplayer_authority()` or it won't sync:

```gdscript
func _ready():
    set_multiplayer_authority(player_id)
```

### 3. RPC Calls Require Decorators

All RPC functions **must** have `@rpc()` decorator:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func sync_data():
    pass
```

### 4. Terrain Generation is Deterministic

Terrain uses a **shared seed** across all clients. Don't use `randf()` or other non-deterministic functions in terrain generation.

### 5. Collision Layers Matter

Buildings use **layer 8** (bit 3). If you change this, update:
- `BuildingBase._ready()` collision setup
- Placement validation queries
- NavMesh obstacle configuration

### 6. Snap Target Exclusion

When validating placement, **always exclude the snap target** from obstacle checks or buildings won't snap properly:

```gdscript
# In building_ghost.gd
func _check_for_obstacles() -> bool:
    # Exclude snap target from query
    if snap_controller.is_currently_snapping():
        exclude = snap_controller.get_snap_target()
```

### 7. Scene Loading Order

Autoloads are initialized **before** main scene. Don't access scene nodes from autoload `_ready()` functions.

### 8. Navigation Baking is Async

NavMesh baking happens on next frame. Use `await get_tree().process_frame` before querying NavMesh after changes:

```gdscript
navigation_region.bake_navigation_mesh()
await get_tree().process_frame
# Now safe to query NavMesh
```

### 9. Ghost Positioning is Client-Side

Building ghost position is **client-side** for responsiveness. Server validates on placement request. Don't trust ghost position for server logic.

### 10. Resource Validation is Server-Side

Always validate resources on server before spending:

```gdscript
# Client requests
rpc_id(1, "request_build", building_type, position)

# Server validates
@rpc("any_peer", "call_local", "reliable")
func request_build(building_type: String, position: Vector3):
    if not multiplayer.is_server():
        return

    if not ResourceManager.can_afford(player_id, costs):
        return  # Reject

    # Proceed with build
```

---

## Git Workflow

### Branch Strategy

- **Main branch:** Production-ready code
- **Feature branches:** `claude/feature-name-sessionid` format
- **Hotfix branches:** `hotfix/issue-description`

### Commit Messages

Use descriptive commit messages:

```
Good:
- "Add farm building type with resource generation"
- "Fix curtain wall triangle winding for correct normals"
- "Implement magnetic snapping for construction sites"

Bad:
- "fix bug"
- "update"
- "changes"
```

### Before Committing

1. **Test the change** - Run the game and verify
2. **Check for errors** - No console errors/warnings
3. **Format code** - Use GDScript formatter if available
4. **Review diff** - Make sure only intended changes are included

### Pushing Changes

Always push to the designated feature branch:

```bash
# Verify current branch
git branch

# Should show: claude/claude-md-mi620aeuny8t71fv-01XPX4emN6QLCr3TTf5tKaLD

# Push with upstream tracking
git push -u origin <branch-name>
```

### Pull Request Guidelines

When creating PRs:
1. **Title:** Clear, concise description
2. **Summary:** What changed and why
3. **Test plan:** How to verify the changes work
4. **Screenshots:** If UI changes involved

---

## Quick Reference

### File Locations Cheat Sheet

```
Need to add/modify...              → Edit this file...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Building size                      → scripts/building_ghost.gd
Building cost                      → scripts/building_placement_manager.gd
Snap behavior                      → scripts/placement/building_snap_controller.gd
Grid size                          → scripts/placement/grid_manager.gd
Unit speed                         → scripts/units/worker.gd
Formation spacing                  → scripts/formation_manager.gd
Camera controls                    → scenes/camera/camera_rig.gd
Resource amounts                   → scripts/autoloads/resource_manager.gd
Vision ranges                      → scripts/buildings/*.gd (per building)
Fog colors                         → shaders/fog_of_war.gdshader
Terrain generation                 → scenes/terrain/terrain.gd
Network settings                   → scripts/autoloads/network_manager.gd
UI layout                          → scenes/ui/*.tscn
```

### Constants Quick Reference

```gdscript
# Snapping
SNAP_DISTANCE: 4.5
UNSNAP_DISTANCE: 7.0
SMOOTH_SNAP_SPEED: 10.0

# Grid
DEFAULT_GRID_SIZE: 4.0

# Units
WORKER_SPEED: 3.0
GATHERING_RANGE: 2.5
CARRY_CAPACITY: 20

# Formation
UNIT_SPACING: 2.0
LINE_WIDTH: 8

# Terrain
MAX_TERRAIN_SLOPE: 0.3
TERRAIN_SIZE: 128x128

# Vision
WORKER_VISION: 10.0
BUILDING_VISION: 15.0-20.0

# Collision
BUILDINGS_LAYER: 8 (bit 3)
```

### Useful Commands

```bash
# Run game
godot --path . scenes/main_menu/main_menu.tscn

# Run as server
godot --path . --server

# Export game
godot --export "Windows Desktop" build/game.exe

# View git log
git log --oneline --graph --decorate --all
```

---

## Additional Resources

### Documentation Files

- **MAGNETIC_SNAPPING_GUIDE.md** - 350+ line guide to building placement system
- **project.godot** - Project configuration and autoloads
- **export_presets.cfg** - Export settings for builds

### External Documentation

- **Godot 4.5 Docs:** https://docs.godotengine.org/en/stable/
- **GDScript Style Guide:** https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html
- **Multiplayer Docs:** https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html

### Getting Help

When encountering issues:
1. Check console output for errors
2. Review relevant section in this guide
3. Check MAGNETIC_SNAPPING_GUIDE.md for placement issues
4. Use Godot debugger to inspect scene tree
5. Search Godot documentation
6. Review recent git commits for similar changes

---

## Changelog

- **2025-11-19** - Initial CLAUDE.md creation
  - Comprehensive codebase documentation
  - Architecture and system overviews
  - Development workflows and conventions
  - Common tasks and troubleshooting

---

**End of CLAUDE.md**

> This guide is maintained for AI assistants working on this codebase. Keep it updated as the project evolves.
