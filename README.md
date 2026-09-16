# NAUQ CAD to 3D — SketchUp Extension

A professional SketchUp extension that automatically converts 2D architectural DWG drawings from AutoCAD into clean, layered 3D models with an interactive BIM-ready toolset.

---

## Key Features

1. **[3D BUILD] 1-Click Paste from AutoCAD (Ctrl+C):**
   - Select entities in AutoCAD -> `Ctrl + C` -> Click `[3D BUILD]` in SketchUp to automatically generate walls, doors, and windows in 3D.
2. **2D Wall Face Architecture (Zero Booleans):**
   - Smooth wall generation with clean topology, coplanar boundary alignment, and zero Boolean/intersection artifacts.
3. **[WALLFILL] Interactive Lintels & Sills:**
   - Click wall opening jamb faces directly to extrude lintels or window sills.
4. **[DOOR] Add Door to Wall Opening:**
   - Click an opening to compute $W \times H \times D$ aperture and insert a parametric V20 profile door (supports holding `Alt` for 2-point manual placement).
5. **[WALL] Hide Overlapping Edges:**
   - Hide coplanar seam edges across contiguous wall segments in one click.
6. **Resize Door/Window:**
   - Batch resize openings and doors without distorting profiles. Supports arched doors/windows with real-time SVG preview, parametric side/top fix panels, and auspicious Lỗ Ban 52.2cm clear opening guidance.
7. **[STAIR] 3D Parametric Staircase:**
   - Generate structural concrete/wood stairs with landing configurations, step calculations, and curved railings.
8. **[SNAPSHOT] Interactive Viewport Framing Tool:**
   - Frame views interactively (16:9, 4:3, 1:1, 3:4, 9:16, Full Screen), export antialiased 2K/4K images, and copy directly to Clipboard (for Google Flow, Photoshop, or messaging).

---

## Installation

1. Run `build_rbz.ps1` via PowerShell to produce the `nauq_cad_to_3d.rbz` package.
2. In SketchUp, open `Extensions` -> `Extension Manager` -> `Install Extension` -> Select `nauq_cad_to_3d.rbz`.

---

## Tóm tắt tiếng Việt (Vietnamese Summary)

Plugin tự động chuyển đổi bản vẽ 2D DWG kiến trúc từ AutoCAD thành mô hình 3D SketchUp phân lớp chuẩn xác:
- **Dựng 3D từ Clipboard:** Quét chọn trên AutoCAD -> `Ctrl+C` -> Bấm dựng trong SketchUp.
- **Kiến trúc Wall Face 2D:** Sử dụng mặt 2D làm gốc, không đục lỗ bằng Boolean, triệt tiêu lỗi rách mặt.
- **Bộ công cụ tương tác:** Bổ sung lanh-tô/bậu cửa (`WallFill`), gắn cửa thông minh (`OpeningDoorTool`), sửa kích thước (`ResizeTool`), dựng cầu thang (`StairBuilder`) và chụp ảnh phối cảnh 2K/4K (`SnapshotCropTool`).
- **Cài đặt:** Chạy `build_rbz.ps1` để đóng gói file `.rbz`, sau đó cài đặt qua Extension Manager của SketchUp.
