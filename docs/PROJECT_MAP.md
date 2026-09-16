# PROJECT MAP — NAUQ CAD TO 3D

Plugin architecture map, directory layout, and SketchUp entity group hierarchy.

---

## 1. Directory & File Map

```text
NAU_CAD_TO_3D/
├── nauq_cad_to_3d.rb            # Entry point, orchestrator & toolbar/menu initialization
├── main.rb                      # Proxy loader for backward compatibility
├── build_rbz.ps1                # Script to produce Trimble-compliant .rbz distribution
├── AGENTS.md                    # Workflow rules & SemVer guidelines
├── README.md                    # Overview, features & installation instructions
│
├── core/
│   ├── attribute.rb             # Tagging & metadata management on SketchUp entities
│   ├── config.rb                # Persistent settings & configuration dictionary
│   ├── geometry.rb              # Math helpers, conversions (mm <-> inch), point/vector math
│   ├── logger.rb                # Structured logger (debug/info/warn/error) & aggregation
│   └── progress.rb              # UI Progress notification bar
│
├── import/
│   ├── dwg_reader.rb            # DWG import, root container setup & entity adoption
│   ├── cad_clipboard.rb         # Scans OS temp directories for AutoCAD Ctrl+C DWG/DXF files
│   ├── layer_parser.rb          # Entity filtering by layer with recursive transform handling
│   └── block_parser.rb          # Block (ComponentInstance) parsing for doors/windows
│
├── wall/
│   ├── wall_detector.rb         # Scans 2D wall edges from specified CAD wall layers
│   ├── wall_cleanup.rb          # Snapping, deduplication, and auto-closing micro gaps
│   ├── wall_builder.rb          # 2D reference creation & final wall extrusion orchestrator
│   ├── wall_fill_builder.rb     # Generates base wall profiles + opening top/bottom WallFills
│   ├── wall_fill_tool.rb        # Interactive tool to create wallfill/lintels on clicked jambs
│   └── overlap_edge_cleaner.rb  # Hide / unhide coplanar overlapping wall seam edges
│
├── opening/
│   ├── opening_detector.rb      # Detects raw doors (blocks) & windows (parallel lines)
│   └── opening_normalizer.rb    # Snaps openings to wall reference, calculates depth & aligns
│
├── door/
│   ├── door_builder.rb          # Coordinates automatic door generation across CAD openings
│   ├── door_generator.rb        # Parametric door generator (V20 architecture, swing & sliding)
│   ├── frame_builder.rb         # Door & window frame 3D geometry builder with transom support
│   ├── leaf_builder.rb          # Door & window leaf 3D builder (FollowMe with embedded glass)
│   ├── glass_builder.rb         # Transom & fix glass panel builder with custom Y offsets
│   └── opening_door_tool.rb     # Interactive raycast door placement tool with opening highlight
│
├── window/
│   └── window_builder.rb        # Parametric window 3D geometry builder with grouping modes
│
├── stair/
│   ├── stair_builder.rb         # Parametric concrete/wood stair generator with landing calculations
│   └── railing_builder.rb       # Glass, metal, and wood staircase railing & handrail builder
│
├── library/
│   ├── material_loader.rb       # Architectural materials & color palettes
│   └── materials.json           # Material definitions
│
├── ui/
│   ├── settings_dialog.rb       # HTML/JS dialog for plugin preferences
│   ├── build_dialog.rb          # Dialog prompting heights (Wall, Door, Window) before 3D build
│   ├── report_dialog.rb         # Dialog displaying warnings/errors after execution
│   ├── replace_dialog.rb        # Visual door/window model replacer dialog
│   ├── resize_tool_dialog.rb    # Interactive batch door/window resizing tool dialog
│   ├── stair_dialog.rb          # Visual parametric stair configuration dialog
│   ├── placement_tool.rb        # Interactive mouse placement tool for imported CAD drawings
│   ├── manual_door_tool.rb      # 2-point manual door placement tool (triggered by Alt key)
│   └── snapshot_crop_tool.rb    # Interactive 2K/4K viewport framing, crop & clipboard tool
│
└── docs/
    ├── PROJECT_MAP.md           # [This file] File map & group hierarchy
    ├── ARCHITECTURE.md          # Architecture, pipeline & 2D source of truth design
    ├── MODULE_RULES.md          # Invariants, constraints & coding rules
    ├── API_CONTRACT.md          # Data structures & method contracts
    └── CHANGELOG.md             # Version history & migration notes
```

---

## 2. SketchUp Group Hierarchy

All output geometry is organized directly at the root level (`model.entities`) into dedicated container groups:

```text
Active Model
├── NAUQ_CAD_ORIGINAL (Group)  # Raw 2D CAD geometry (Layer 0, hidden edges)
├── NAUQ_WALLS (Group)         # Base walls and WallFill geometry
├── NAUQ_DOORS (Group)         # 3D door component instances
├── NAUQ_WINDOWS (Group)       # 3D window component instances
└── NAUQ_SLAB (Group)          # [Optional] Concrete ceiling slab (400mm beam exclusion)
```

---

## Tóm tắt tiếng Việt (Vietnamese Summary)

### Sơ đồ thư mục & Phân cấp mô hình SketchUp
- **Cấu trúc module:** Phân tách rõ ràng giữa `core/` (hạ tầng, hình học, log), `import/` (xử lý CAD DWG & Clipboard), `wall/` (dựng tường 2D & WallFill), `opening/` (nhận diện & chuẩn hóa khẩu độ), `door/` & `window/` (sinh cửa V20 tham số), `stair/` (cầu thang), `ui/` (hộp thoại HTML/JS phẳng & công cụ tương tác).
- **Phân nhóm trong SketchUp:** Mô hình xuất ra được gom vào 5 nhóm độc lập tại gốc model (`NAUQ_CAD_ORIGINAL`, `NAUQ_WALLS`, `NAUQ_DOORS`, `NAUQ_WINDOWS`, `NAUQ_SLAB`), không tạo group cha lồng nhau để đảm bảo quản lý phân lớp và xuất khối lượng thuận tiện.
