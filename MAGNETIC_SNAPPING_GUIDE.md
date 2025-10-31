# Magnetic Building Snapping System

## Overview

This RTS game now features a robust magnetic snapping system for building placement. Buildings automatically snap to edges and corners of existing buildings when dragged close, with smooth visual feedback and intelligent snap detection.

## Features

### 1. Magnetic Snapping Behavior
- Buildings snap to edges of existing buildings when within **4.5 units** (under 5 unit requirement)
- Supports both **edge-to-edge** and **corner-to-corner** snapping
- **Sticky behavior**: Once snapped, requires pulling beyond 7.0 units to release
- Smooth interpolation when snapping/unsnapping for natural feel
- Visual feedback with snap guide lines and snap point highlights

### 2. Multi-Size Building Support
Current building sizes:
- **Town Center**: 8x6x8 (Large)
- **Barracks**: 6x5x6 (Medium)
- **House**: 4x4x4 (Small)

The system automatically calculates snap points based on building dimensions and allows different size buildings to snap together properly without overlaps.

### 3. Grid Integration
- Buildings snap to a **4.0 unit grid** when not near other buildings
- When near buildings, magnetic snap takes priority over grid snap
- Grid alignment maintained for organized base building

### 4. Smart Snap Detection
The system uses a priority-based approach:
- **Edge alignments** prioritized over corner alignments
- Finds all valid snap points within range
- Selects best match based on distance and alignment type
- Spatial partitioning for performance with many buildings

### 5. Visual Feedback System
- **Ghost color coding**:
  - Green (transparent): Valid placement
  - Red (transparent): Invalid placement
- **Snap guide lines**: Draw connections between ghost and target building
- **Snap points**: Yellow cubes showing potential snap locations
  - Active snap point highlighted in bright green
- **Connection indicators**: Green line showing successful snap attachment
- **Grid overlay**: Optional grid visualization (can be toggled)

### 6. Construction Site Snapping
- Ghosts can snap to construction sites (buildings under construction)
- Construction sites act as "magnetic anchors"
- Allows planning base layout while buildings are being built

## Architecture

The magnetic snapping system uses a modular, component-based architecture:

```
scripts/placement/
├── snap_point_detector.gd      # Finds valid snap points (edges & corners)
├── building_snap_controller.gd # Main snapping logic & state management
├── grid_manager.gd              # Grid-based placement
└── placement_visualizer.gd      # Visual feedback rendering
```

### Component Responsibilities

#### SnapPointDetector
- Detects all potential snap points around existing buildings
- Calculates edge-to-edge and corner-to-corner positions
- Prioritizes snap points (edges > corners, closer > farther)
- Supports spatial partitioning for performance

**Key Methods:**
```gdscript
find_snap_points(ghost_pos, ghost_size, targets, max_distance) -> Array[SnapPoint]
```

#### BuildingSnapController
- Manages snapping state (snapped/unsnapped)
- Implements magnetic behavior with thresholds
- Smooth interpolation for natural feel
- Provides snap information for visualization

**Key Methods:**
```gdscript
update_snapping(ghost_pos, ghost_size, mouse_pos, targets, delta) -> Vector3
is_currently_snapping() -> bool
get_snap_target() -> Node
```

**Constants:**
- `SNAP_DISTANCE`: 4.5 units (trigger distance)
- `UNSNAP_DISTANCE`: 7.0 units (release distance)
- `SMOOTH_SNAP_SPEED`: 10.0 (interpolation speed)

#### GridManager
- Handles grid-based snapping when not magnetically snapping
- Grid size: 4.0 units
- Grid visualization support
- Building footprint calculations

**Key Methods:**
```gdscript
snap_to_grid(position, building_size) -> Vector3
is_grid_aligned(position, tolerance) -> bool
get_grid_visualization_data(camera_pos, view_distance) -> Dictionary
```

#### PlacementVisualizer
- Renders all visual feedback
- Snap guide lines (cyan)
- Snap points (yellow cubes, active = green)
- Connection indicators (bright green)
- Grid overlay (gray, semi-transparent)

**Key Methods:**
```gdscript
update_visualization(ghost_pos, snap_points, active_snap, grid_data)
set_snap_points_visible(visible)
set_snap_lines_visible(visible)
```

## Usage

### For Players

**Placing Buildings:**
1. Select workers
2. Click a building button (House, Barracks, Town Center)
3. Ghost preview appears following your mouse
4. Move near existing buildings to see snap points light up
5. Ghost automatically snaps to nearest valid edge/corner
6. Ghost turns **green** when placement is valid, **red** when invalid
7. Left-click to place
8. Right-click to cancel

**Keyboard Controls:**
- `J`: Rotate building -45°
- `K`: Rotate building +45°
- `Shift + Click`: Queue multiple buildings
- `Right-click`: Cancel placement

**Visual Indicators:**
- **Yellow cubes**: Available snap points nearby
- **Bright green cube**: Active snap point being used
- **Cyan line**: Snap guide showing alignment
- **Green line**: Connection indicator when snapped
- **Green ghost**: Valid placement
- **Red ghost**: Invalid placement (terrain too steep, obstacle, etc.)

### For Developers

**Using the Magnetic Snapping System:**

The BuildingGhost class automatically integrates all components:

```gdscript
# In BuildingGhost._ready()
func setup_placement_components():
    # Create snap controller
    snap_controller = BuildingSnapController.new()
    snap_controller.set_smooth_snapping(true)

    # Create grid manager
    grid_manager = GridManager.new(4.0)  # 4.0 grid size
    grid_manager.set_grid_enabled(true)

    # Create visualizer
    visualizer = PlacementVisualizer.new()
    add_child(visualizer)
```

**Checking for Snapping:**

```gdscript
# In BuildingPlacementManager.update_ghost_position()
if current_ghost.check_for_snapping(player_id, world_pos, delta):
    # Position already applied by snap controller
    pass
else:
    current_ghost.update_position(world_pos, terrain)
```

**Adding New Building Types:**

1. Define size in `BuildingGhost.set_building_type()`:
```gdscript
match building_type:
    "new_building":
        building_size = Vector3(5, 4, 5)
```

2. Add cost and construction time in `BuildingPlacementManager`:
```gdscript
const BUILDING_COSTS = {
    "new_building": {"wood": 100, "gold": 25}
}

const CONSTRUCTION_TIMES = {
    "new_building": 25.0
}
```

The snapping system automatically adapts to the new building size!

## Performance Optimizations

### Spatial Partitioning
The system uses distance-based filtering to only check nearby buildings:
```gdscript
# Only check buildings within 2x snap distance
filtered_targets = _filter_targets_by_distance(position, targets, max_distance * 2.0)
```

### Frame-by-Frame Updates
- Snap point detection runs every frame but uses cached results
- Visualization only updates when snap state changes
- Grid visualization uses camera-based LOD

### Collision Optimization
- Excludes snap target from obstacle checks
- Uses single box-shape query for all obstacles
- Checks only buildings layer (layer 8)

## Configuration

### Adjusting Snap Thresholds

Edit constants in `building_snap_controller.gd`:
```gdscript
const SNAP_DISTANCE: float = 4.5      # Distance to trigger snapping
const UNSNAP_DISTANCE: float = 7.0    # Distance to release snap
const SMOOTH_SNAP_SPEED: float = 10.0 # Interpolation speed
```

### Adjusting Grid Size

Edit in `grid_manager.gd`:
```gdscript
const DEFAULT_GRID_SIZE: float = 4.0  # Grid cell size
```

### Toggling Visual Features

```gdscript
# In BuildingGhost or visualization code
visualizer.set_snap_points_visible(true/false)
visualizer.set_snap_lines_visible(true/false)
visualizer.set_connections_visible(true/false)
visualizer.set_grid_visible(true/false)
```

## Technical Details

### Snap Point Calculation

**Edge Snapping:**
```gdscript
# North edge: Ghost placed north of target
snap_pos = Vector3(
    target_pos.x,
    ghost_pos.y,
    target_pos.z + target_half_z + ghost_half_z
)
```

**Corner Snapping:**
```gdscript
# Northeast corner: Ghost placed at NE corner of target
snap_pos = Vector3(
    target_pos.x + target_half_x + ghost_half_x,
    ghost_pos.y,
    target_pos.z + target_half_z + ghost_half_z
)
```

### Priority Calculation

```gdscript
# Lower priority = higher preference
base_priority = 1.0 for edges, 2.0 for corners
final_priority = base_priority + (distance / 10.0)
```

Edges are always prioritized over corners at the same distance.

### Smooth Snapping

Uses lerp interpolation:
```gdscript
snap_lerp_weight = min(snap_lerp_weight + delta * SMOOTH_SNAP_SPEED, 1.0)
return ghost_position.lerp(snap_position, snap_lerp_weight)
```

## Placement Validation

Buildings must pass these checks:
1. **Terrain slope** < 30% (MAX_TERRAIN_SLOPE: 0.3)
2. **No obstacles** at placement position (except snap target)
3. **On navigable terrain** (within 2.0 units of NavMesh)

Invalid placement shows **red ghost** with no ability to place.

## Multiplayer Support

The snapping system is client-side for responsive feedback, but placement validation and construction site creation is server-authoritative:

1. Client shows ghost with snapping (instant feedback)
2. Client requests placement from server
3. Server validates resources and placement
4. Server creates construction site
5. Server broadcasts to all clients

This prevents cheating while maintaining smooth UX.

## Future Enhancements

Possible improvements:
- **Smart wall chaining**: 1x1 wall segments that auto-connect
- **Foundation snapping**: Buildings snap to pre-designated foundation zones
- **Pattern recognition**: Auto-generate grids of buildings
- **Snap angle constraints**: Force 90° or 45° alignments
- **Custom snap points**: User-defined anchor points on buildings
- **Snap preview**: Show multiple potential snap positions simultaneously

## Troubleshooting

### Buildings not snapping
- Check snap distance (must be within 4.5 units)
- Verify buildings are in correct player groups: `"player_%d_buildings"`
- Ensure snap_controller is initialized in BuildingGhost

### Visual feedback not showing
- Check that visualizer child node exists
- Verify visibility flags are enabled
- Ensure _process() is running in BuildingGhost

### Collision detection issues
- Check collision layer (should be 8 for buildings)
- Verify snap target exclusion is working
- Check building sizes are set correctly

### Performance issues with many buildings
- Ensure spatial partitioning is enabled (use_spatial_partition: true)
- Increase filter distance threshold if needed
- Consider disabling visualizations for distant buildings

## Credits

Implemented using Godot 4.x with modular, extensible architecture following best practices for RTS building placement systems.
