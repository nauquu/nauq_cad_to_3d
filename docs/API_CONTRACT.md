# API CONTRACT & DATA SCHEMAS — NAUQ CAD TO 3D

Tài liệu định nghĩa chi tiết các hàm, tham số đầu vào, kiểu dữ liệu trả về và cấu trúc các bảng băm (Hash Schemas) truyền giữa các module.

---

## 1. Data Schemas (Cấu trúc dữ liệu chuẩn)

### 1.1 `Segment` Hash (từ `WallDetector`)
```ruby
{
  start_pt: Geom::Point3d,   # Điểm bắt đầu (đã nhân transform thế giới)
  end_pt:   Geom::Point3d,   # Điểm kết thúc (đã nhân transform thế giới)
  length_mm: Float,          # Chiều dài đoạn thẳng tính bằng mm
  edge:     Sketchup::Edge   # Thực thể Edge gốc từ CAD
}
```

### 1.2 `Cleaned Pair` Array (từ `WallCleanup`)
```ruby
[
  Geom::Point3d, # p1: Điểm đầu sau khi đã snap/cluster
  Geom::Point3d  # p2: Điểm cuối sau khi đã snap/cluster
]
```

### 1.3 `Wall Face 2D` Hash (từ `WallBuilder.build_wall_reference`)
```ruby
{
  face_entity_id: Integer,                 # ID thực thể của Face trong SketchUp
  points:         Array<Geom::Point3d>,    # Danh sách các đỉnh outer loop
  origin:         Geom::Point3d,           # Gốc tọa độ cục bộ (đỉnh đầu tiên)
  u_vector:       Geom::Vector3d,          # Vector đơn vị chỉ hướng dọc tường
  n_vector:       Geom::Vector3d,          # Vector đơn vị chỉ hướng vuông góc tường (ngang)
  n_min:          Float,                   # Tọa độ N nhỏ nhất (inch)
  n_max:          Float,                   # Tọa độ N lớn nhất (inch)
  base_z:         Float,                   # Cao độ đáy (inch)
  wall_top:       Float                    # Cao độ đỉnh tường (inch)
}
```

### 1.4 `Opening` Hash (từ `OpeningDetector` & `OpeningNormalizer`)
```ruby
{
  id:              String,                 # "DOOR_1", "WIN_1", ...
  type:            Symbol,                 # :door hoặc :window
  position:        Geom::Point3d,          # Tọa độ tâm đáy opening
  width_mm:        Float,                  # Chiều rộng mở cửa tính bằng mm
  height_mm:       Float,                  # Chiều cao cửa tính bằng mm
  offset_mm:       Float,                  # Cao độ bậu cửa (Window sill) tính bằng mm
  depth_mm:        Float,                  # Độ dày lòng tường tính bằng mm
  u_vector:        Geom::Vector3d,         # Vector đơn vị chỉ hướng dọc ngang cửa
  n_vector:        Geom::Vector3d,         # Vector đơn vị chỉ hướng chiều dày tường
  source:          Symbol                  # :block hoặc :lines
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
- `DoorGenerator.generate(parent:, name:, width:, height:, panel_count:, is_sliding: false, ...)` $\rightarrow$ `Sketchup::Group`
- `WindowBuilder.generate(parent:, name:, width:, height:, panel_count:, is_sliding: false, ...)` $\rightarrow$ `Sketchup::Group`

### 2.9 `LeafBuilder` & `GlassBuilder`
- `LeafBuilder.get_or_create_leaf_definition(model, leaf_width, leaf_height, frame_material, glass_material, prefix)` $\rightarrow$ `Sketchup::ComponentDefinition`
- `LeafBuilder.create_leaf_instance(parent_group, definition, index, leaf_width, exact_x:, material:)` $\rightarrow$ `Sketchup::ComponentInstance`
- `GlassBuilder.build_panel(parent_group, x0, x1, z0, z1, material, name, y_offset:)` $\rightarrow$ `Sketchup::Group | nil`
- `GlassBuilder.build_layout_glasses(parent_group, layout, material, include_active: false)` $\rightarrow$ `Array<Sketchup::Group>`

### 2.10 `OpeningDoorTool` (Interactive Placement Tool)
- `OpeningDoorTool#activate` / `deactivate`
- `OpeningDoorTool#detect_opening_from_context(context)` $\rightarrow$ `Hash | nil` (Opening alignment & coordinate definition)

