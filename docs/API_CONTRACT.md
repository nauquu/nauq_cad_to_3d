# API CONTRACT & DATA SCHEMAS — NAUQ CAD TO 3D

This document specifies function contracts, parameter types, return signatures, and hash data schemas exchanged between internal modules.

---

## 1. Standard Data Schemas

### 1.1 `Segment` Hash (from `WallDetector`)
```ruby
{
  start_pt: Geom::Point3d,   # Start coordinate (transformed to world coordinates)
  end_pt:   Geom::Point3d,   # End coordinate (transformed to world coordinates)
  length_mm: Float,          # Segment length in millimeters
  edge:     Sketchup::Edge   # Originating 2D CAD edge reference
}
```

### 1.2 `Cleaned Pair` Array (from `WallCleanup`)
```ruby
[
  Geom::Point3d, # p1: Start point after snapping / vertex clustering
  Geom::Point3d  # p2: End point after snapping / vertex clustering
]
```

### 1.3 `Wall Face 2D` Hash (from `WallBuilder.build_wall_reference`)
```ruby
{
  face_entity_id: Integer,                 # SketchUp Face entity ID
  points:         Array<Geom::Point3d>,    # Outer loop boundary vertices
  origin:         Geom::Point3d,           # Local origin (first vertex)
  u_vector:       Geom::Vector3d,          # Unit vector pointing along wall length
  n_vector:       Geom::Vector3d,          # Unit normal vector (across wall thickness)
  n_min:          Float,                   # Minimum transverse offset (inches)
  n_max:          Float,                   # Maximum transverse offset (inches)
  base_z:         Float,                   # Base elevation (inches)
  wall_top:       Float                    # Top elevation (inches)
}
```

### 1.4 `Opening` Hash (from `OpeningDetector` & `OpeningNormalizer`)
```ruby
{
  id:               String,                 # e.g., "DOOR_1", "WIN_1"
  type:             Symbol,                 # :door or :window
  position:         Geom::Point3d,          # Bottom-center coordinate of the opening
  width_mm:         Float,                  # Opening width in millimeters
  height_mm:        Float,                  # Opening height in millimeters
  offset_mm:        Float,                  # Sill height / bottom elevation offset in millimeters
  depth_mm:         Float,                  # Wall jamb thickness in millimeters
  u_vector:         Geom::Vector3d,         # Unit vector aligned with opening width
  n_vector:         Geom::Vector3d,         # Unit normal vector aligned with wall thickness
  source:           Symbol,                 # :block or :lines
  corner_radius_mm: Float                   # Optional top corner rounding radius in millimeters
}
```

---

## 2. Core Method Signatures

### 2.1 `DWGReader`
- `import_dwg_for_placement(file_path)` $\rightarrow$ `Sketchup::ComponentDefinition | nil`
- `find_or_create_cad_original_group(model)` $\rightarrow$ `Sketchup::Group`

### 2.2 `WallDetector`
- `collect_wall_edges(cad_group, layer_name)` $\rightarrow$ `Array<Segment>`

### 2.3 `WallCleanup`
- `cleanup_edges(segments, tolerance_mm)` $\rightarrow$ `Array<[Point3d, Point3d]>`

### 2.4 `WallBuilder`
- `build_wall_reference(cad_group)` $\rightarrow$ `Sketchup::Group`
- `build_walls(cad_group, walls_group, openings)` $\rightarrow$ `Sketchup::Group`

### 2.5 `OpeningDetector`
- `detect_all_openings(cad_group)` $\rightarrow$ `Array<Opening>`

### 2.6 `OpeningNormalizer`
- `normalize_all(raw_openings, walls_group, cad_group)` $\rightarrow$ `Array<Opening>`

### 2.7 `DoorBuilder` / `WindowBuilder`
- `DoorBuilder.build_doors(openings, container, cad_group)` $\rightarrow$ `void`
- `WindowBuilder.build_windows(openings, container, cad_group)` $\rightarrow$ `void`

### 2.8 `DoorGenerator` / `WindowBuilder` (Parametric 3D Assembly Generators)
- `DoorGenerator.generate(parent:, name:, width:, height:, panel_count:, is_sliding: false, corner_radius: 0.mm, ...)` $\rightarrow$ `Sketchup::Group`
- `WindowBuilder.generate(parent:, name:, width:, height:, panel_count:, is_sliding: false, corner_radius: 0.mm, ...)` $\rightarrow$ `Sketchup::Group`

### 2.9 `FrameBuilder`, `LeafBuilder` & `GlassBuilder`
- `FrameBuilder.build(parent_group, width, height, corner_radius: 0.mm, ...)` $\rightarrow$ `Sketchup::Group`
- `LeafBuilder.get_or_create_leaf_definition(model, leaf_width, leaf_height, frame_material, glass_material, prefix, corner_radius: 0.mm, round_sides: nil)` $\rightarrow$ `Sketchup::ComponentDefinition`
- `LeafBuilder.create_leaf_instance(parent_group, definition, index, leaf_width, exact_x:, material:)` $\rightarrow$ `Sketchup::ComponentInstance`
- `GlassBuilder.build_panel(parent_group, x0, x1, z0, z1, material, name, y_offset:, corner_radius: 0.mm, round_sides: nil)` $\rightarrow$ `Sketchup::Group | nil`
- `GlassBuilder.build_layout_glasses(parent_group, layout, material, include_active: false)` $\rightarrow$ `Array<Sketchup::Group>`

### 2.10 `OpeningDoorTool` (Interactive Placement Tool)
- `OpeningDoorTool#activate` / `deactivate`
- `OpeningDoorTool#detect_opening_from_context(context)` $\rightarrow$ `Hash | nil`
- `OpeningDoorTool#detect_opening_arch(face, loop_edges)` $\rightarrow$ `Float` (returns corner radius in mm)

### 2.11 `BlockParser` (CAD Block Collection & Recognition)
- `collect_blocks(cad_group, block_name = nil, layer_name = nil)` $\rightarrow$ `Array<Hash>`
- `collect_window_blocks(cad_group, block_name = nil, layer_name = nil)` $\rightarrow$ `Array<Hash>`

### 2.12 `ResizeToolDialog` (Door/Window Inspection & Resizing)
- `read_dimension(entity, key)` $\rightarrow$ `Float | nil` (Decodes attributes with multi-unit mm/inch auto-conversion)
- `read_fix_dimension(entity, direction)` $\rightarrow$ `Float` (Reads fix panel dimensions from attributes or 3D bounding boxes)
- `read_has_fix(entity, direction)` $\rightarrow$ `Boolean` (Determines fix existence via attributes or sub-group inspection)
- `execute_resize(data_hash)` $\rightarrow$ `void` (Updates door dimensions and synchronizes corresponding wall opening)

---

## Tóm tắt tiếng Việt (Vietnamese Summary)

### Cấu trúc dữ liệu & Hợp đồng module
1. **Dữ liệu chuẩn:**
   - `Segment`: Đoạn thẳng trích từ CAD kèm tọa độ thực và độ dài tính bằng mm.
   - `Cleaned Pair`: Cặp điểm sau khi đã snap đỉnh và làm sạch nét thừa/trùng lặp.
   - `Wall Face 2D`: Tiết diện mặt tường 2D kèm hệ vector cục bộ $U$ (dọc tường), $N$ (bề dày), $Z$ (chiều cao).
   - `Opening`: Thông số lỗ mở tường ($W \times H \times D$, cao độ bậu cửa, vector hướng).
2. **Quy ước chữ ký hàm chính:**
   - Toàn bộ tham số kích thước đầu vào và trả về cho người dùng/UI đều tính bằng **mm**.
   - `ResizeToolDialog`: Cung cấp bộ 3 hàm `read_dimension`, `read_fix_dimension`, `read_has_fix` giải mã thông minh đơn vị và đo trực tiếp từ 3D bounding box khi thuộc tính bị thiếu.
