# PROJECT MAP — NAUQ CAD TO 3D

Plugin tự động chuyển đổi bản vẽ 2D DWG kiến trúc (AutoCAD) thành mô hình 3D SketchUp phân lớp chuẩn xác.

---

## 1. Directory & File Map

```text
NAU_CAD_TO_3D/
├── nauq_cad_to_3d.rb            # Entry point, orchestrator & toolbar/menu init
├── main.rb                      # Proxy loader for backward compatibility
├── build_rbz.ps1                # Script đóng gói Trimble-compliant .rbz
├── AGENTS.md                    # Quy tắc workflow & SemVer
├── README.md                    # Tổng quan giới thiệu & hướng dẫn sử dụng
│
├── core/
│   ├── attribute.rb             # Tagging & metadata management on SketchUp entities
│   ├── config.rb                # Persistent settings & configuration keys
│   ├── geometry.rb              # Math, conversions (mm <-> inch), point/plane/vector helpers
│   ├── logger.rb                # Structured logger (debug/info/warn/error) & error aggregator
│   └── progress.rb              # UI Progress notification bar
│
├── import/
│   ├── dwg_reader.rb            # DWG import, root container setup & entity adoption
│   ├── cad_clipboard.rb         # Scans OS temp directories for AutoCAD Ctrl+C DWG/DXF files
│   ├── layer_parser.rb          # Entity filtering by layer with recursive transform handling
│   └── block_parser.rb          # Block (ComponentInstance) parsing for doors/windows
│
├── wall/
│   ├── wall_detector.rb         # Scans 2D wall edges from '0-netcat' layer
│   ├── wall_cleanup.rb          # Level C cleanup (snapping, deduplication, auto-close gaps)
│   ├── wall_builder.rb          # Reference creation & final wall extrusion orchestrator
│   ├── wall_fill_builder.rb     # Generates base wall profiles + opening top/bottom WallFills
│   ├── wall_fill_tool.rb        # Interactive tool to create wallfill / lintels by clicking jamb faces
│   └── overlap_edge_cleaner.rb  # Hide / unhide coplanar overlapping wall seam edges
│
├── opening/
│   ├── opening_detector.rb      # Detects raw doors (blocks) & windows (parallel lines)
│   └── opening_normalizer.rb    # Snaps openings to wall reference, calculates depth & aligns
│
├── door/
│   ├── door_builder.rb          # Coordinates door generation across openings
│   ├── door_generator.rb        # Parametric door generator (V20 architecture)
│   ├── frame_builder.rb         # Door & window frame 3D geometry builder with transom support
│   ├── leaf_builder.rb          # Door & window leaf/panel 3D builder (FollowMe algorithm)
│   ├── glass_builder.rb         # Transom & glass insert builder
│   └── opening_door_tool.rb     # Interactive raycast door placement tool for wall openings
│
├── window/
│   └── window_builder.rb        # Parametric window 3D geometry builder with transom support
│
├── stair/
│   ├── stair_builder.rb         # Parametric concrete/wood stair generator with landing & feng-shui steps
│   └── railing_builder.rb       # Glass, metal, and wood staircase railing & handrail builder
│
├── library/
│   ├── template_loader.rb       # Dynamic component / SKP template loader
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

Toàn bộ mô hình đầu ra được tổ chức trực tiếp tại cấp gốc (`model.entities`) thành các group container độc lập:

```text
Active Model
├── NAUQ_CAD_ORIGINAL (Group)  # Chứa toàn bộ hình học 2D CAD DWG gốc (Layer 0, nét ẩn)
├── NAUQ_WALLS (Group)         # Chứa Base Wall và WallFill sau khi dựng 3D
├── NAUQ_DOORS (Group)         # Chứa toàn bộ ComponentInstance cửa đi 3D
├── NAUQ_WINDOWS (Group)       # Chứa toàn bộ ComponentInstance cửa sổ 3D
└── NAUQ_SLAB (Group)          # [Tùy chọn] Sàn bê tông trên đỉnh tường (trừ dầm 400mm)
```
