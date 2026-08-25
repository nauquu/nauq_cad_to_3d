# CHANGELOG — NAUQ CAD TO 3D

Toàn bộ lịch sử các phiên bản, các đợt tái cấu trúc kiến trúc (Refactoring) và sửa lỗi của plugin.

---

## [v1.9.4] - 2026-08-25 (Sliding Door 2-Track System, Leaf Alignment & Opening Highlight)
### Added
- **Interactive Opening Highlight (`OpeningDoorTool`):** Tự động highlight khung hộp 3D xanh lam ôm trọn hốc tường khi rê chuột, giúp nhận biết chính xác vị trí bắt điểm trước khi click.
- **Realistic 2-Track Sliding Geometry (`DoorGenerator` & `WindowBuilder`):**
  - Dựng hệ 2 ray so le lệch nhau $24\text{mm}$ theo chiều sâu Y giữa cánh trong và cánh ngoài.
  - Tự động cộng đoạn gối mí (overlap $30\text{mm}$) ở giữa 2 cánh theo chuẩn kỹ thuật cửa lùa nhôm kính.
  - Mặt kính của từng cánh tự động chạy đúng theo chiều sâu Y của từng cánh tương ứng.

### Fixed & Optimized
- **Leaf Instance Coordinate Calculation:** Sửa lỗi cộng dồn X offset trong `LeafBuilder.create_leaf_instance` khiến cánh cửa thứ 2 bị lệch ra ngoài khung bao.
- **Window Opening Definition:** Loại bỏ quy tắc tự động ép thêm ô kính Fix dưới không mong muốn khi tạo cửa sổ.

---

## [v1.9.3] - 2026-08-25 (Opening Door Tool Flush Alignment & UI Streamline)
### Added
- **Right-Click Context Menu (`OpeningDoorTool`):** Bổ sung menu chuột phải trực quan giúp lựa chọn nhanh chóng các loại cửa đi, cửa sổ, cửa lùa, vách kính cố định và đảo chiều đặt cửa.
- **Accented Vietnamese Standardization:** Chuẩn hóa 100% tiếng Việt có dấu đầy đủ, chuẩn chính tả trên thanh trạng thái, menu và hộp thoại thông báo.

### Fixed & Optimized
- **Exterior Flush Edge Placement:**
  - Khắc phục triệt để lỗi khung cửa bị lệch tâm ra ngoài mép tường.
  - Tự động đặt khung nhôm cửa bằng phẳng $100\%$ với mép ngoài hốc tường (mặc định) và ăn sâu vào lòng tường, hỗ trợ phím `Ctrl` đảo vào mép trong.
- **Lightweight Streamlined Interaction:** Loại bỏ render preview viewport để công cụ phản hồi tức thì, mượt mà và thao tác click đặt cửa chuẩn xác.

---

## [v1.9.2] - 2026-08-25 (Performance Optimization, Dynamic Cursors & Async Snapshot)
### Added
- **Dynamic 2-Headed & 4-Way Cursors (`SnapshotCropTool`):**
  - Tự động chuyển đổi con trỏ chuột sang mũi tên 2 đầu chéo ↖↘ (`NW-SE`) và ↗↙ (`NE-SW`) khi rê chuột vào 4 góc để báo hiệu co giãn khung hình.
  - Tự động chuyển đổi sang con trỏ 4 hướng ✥ (`Move`) khi rê chuột vào bên trong khung.
- **Asynchronous Instant Capture Engine:**
  - Nâng cấp tiến trình cắt pixel và nạp Clipboard chạy nền bất đồng bộ (`Process.spawn`), giúp SketchUp nhả thao tác chụp tức thì trong 0.1s không còn độ trễ chờ đợi.
  - Loại bỏ hộp thoại modal popup phiền toái, chuyển sang thông báo xác nhận tinh tế trên thanh trạng thái SketchUp.
- **Concrete (`betong`) Material Definition:** Bổ sung định nghĩa vật liệu bê tông vào `library/materials.json`.

### Fixed & Optimized
- **Zero-Allocation Rendering (60–120 FPS):**
  - Đóng băng hằng số màu (`COLOR_MASK`, `COLOR_GRID`, `COLOR_FRAME`, v.v.) và chuyển sang mảng tọa độ 2D phẳng `[x, y, 0]`, loại bỏ hoàn toàn việc cấp phát đối tượng Ruby trong vòng lặp vẽ màn hình, triệt tiêu hiện tượng micro-stutter / GC lag khi kéo chuột.
  - Sửa tên callback `draw(view)` chuẩn xác theo SketchUp Tool API.
  - Nâng trần scale lên $1.0$ (100% full viền không bị dính margin).
  - Gỡ bỏ dòng chữ HUD trên khung chụp để khung nhìn thông thoáng, chuẩn cinematic.
- **Prevent Toolbar Button Duplication:**
  - Loại bỏ việc reset `@menus_registered` trong hàm `reload!`, đảm bảo khi bấm Reload Plugin không bị nhân đôi các nút bấm trên thanh công cụ.
- **Door Edge Dimension Conversion:**
  - Chuẩn hóa kiểm tra chênh lệch chiều dài cạnh opening cửa bằng `Geometry.inch_to_mm(...)`.

---

## [v1.9.1] - 2026-08-25 (Fix UI Module Collision & Toolbar Boot Sequence)
### Fixed
- **Resolve `NAUQ::UI` Namespace Shadowing:**
  - Chuyển namespace của `SnapshotCropTool` từ `NAUQ::UI` sang `NAUQ::CadTo3D`, ngăn việc vô tình tạo ra module con trùng tên che khuất module `::UI` toàn cục của SketchUp.
  - Thêm tiền tố `::UI` cho toàn bộ các lệnh gọi menu, toolbar, messagebox và context menu.
- **Fix Extension Boot Sequence:**
  - Di chuyển lệnh gọi `reload!` và `init_ui` xuống cuối tệp `nauq_cad_to_3d.rb` sau khi mọi định nghĩa method đã được parse hoàn tất.
  - Sửa lỗi cú pháp do thừa từ khóa `end` ở cuối tệp.

---

## [v1.9.0] - 2026-08-25 (Interactive 3D Snapshot & Framing Tool)
### Added
- **Interactive Viewport Framing & Crop Tool (`SnapshotCropTool`):**
  - Khung cắt tương tác trực tiếp trên màn hình SketchUp với lưới bố cục 1/3 (Rule of Thirds) và viền mờ Cinematic Matte.
  - Hỗ trợ rê chuột di chuyển (Move/Pan) vùng cắt, lăn chuột co giãn kích thước.
  - Phím tắt nhanh chọn tỉ lệ khung hình: `1` (16:9), `2` (4:3), `3` (1:1), `4` (3:4), `5` (9:16), `6` (Toàn màn hình).
  - Phím tắt `R` chuyển đổi độ phân giải: `2K QHD (2560px)`, `4K UHD (3840px)`, `Full HD (1920px)`.
  - Phím `Enter` / Click đúp để xuất ảnh toàn cảnh siêu nét khử răng cưa antialias, cắt pixel hoàn hảo và copy trực tiếp vào Windows Clipboard.

---

## [v1.8.0] - 2026-08-24 (Stair Builder & Railings)
### Added
- **Parametric Stair Builder (`StairBuilder` & `StairDialog`):**
  - Dựng cầu thang 3D chữ I, chữ L, chữ U chuẩn kết cấu và phong thủy (Sinh - Lão - Bệnh - Tử).
  - Tích hợp lan can kính / inox / gỗ (`RailingBuilder`) tự động uốn theo chiếu nghỉ.

---

## [v1.7.0] - 2026-08-21 (Batch Resize Tool & Manual 2-Point Door)
### Added
- **Batch Resize Door/Window Dialog (`ResizeToolDialog`):**
  - Quét chọn nhiều cửa trên mô hình để sửa kích thước Dài/Rộng/Cao hàng loạt mà không làm biến dạng profile nhôm.
- **Manual 2-Point Door Placement Tool (`ManualDoorPlacementTool`):**
  - Giữ phím `[Alt]` khi dùng công cụ Thêm Cửa để chuyển sang chế độ click 2 điểm thủ công.

---

## [v1.6.0] - 2026-08-20 (Hide Overlapping Edges Cleaner)
### Added
- **Hide Overlapping Wall Edges (`Core::GeometryHelper.hide_coplanar_overlap_edges`):**
  - Tự động quét và ẩn toàn bộ các nét trùng lặp, nét giáp ranh giữa các khối tường, Group hoặc Component giáp mí.

---

## [v1.4.0] - 2026-08-18 (Interactive Tools & AutoCAD Direct Paste)
### Added
- **Direct 1-Click Paste from AutoCAD (`CADClipboard` & `[TẠO 3D]`):**
  - Tự động nhận diện dữ liệu vừa `Ctrl + C` (`COPYCLIP`) trong AutoCAD để dựng 3D trong 1 click.
- **Interactive WallFill Tool (`WallFillTool`):**
  - Click vào mặt hốc tường để đùn lanh-tô và bậu cửa sổ tự động.
- **Interactive Opening Door Tool (`OpeningDoorTool`):**
  - Click vào hốc tường để đo $W, H, D$ và lắp cửa nhôm kính 3D chuẩn kích thước.

---

## [v1.3.0] - 2026-08-16 (Spec v1 Completed)
### Added
- **Top Concrete Slab (`NAUQ_SLAB`) & Beam Deduction:**
  - Tự động trừ dầm 400mm và tạo khối sàn mái bê tông trên đỉnh tường.
- **Parametric Window 3D Builder (`WindowBuilder`):**
  - Dựng khung bao và cánh cửa sổ theo hệ Profile V20 FollowMe.

---

## [v1.2.0] - 2026-08-15 (Wall Face 2D Source of Truth)
### Changed
- Loại bỏ hoàn toàn phương pháp đục lỗ Boolean / WallCutter.
- Sử dụng trực tiếp các mặt Face 2D từ layer `0-netcat` làm Source of Truth.
- Base Wall và WallFill được extrude đồng thời trong 1 operation duy nhất.
