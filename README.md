# NAUQ CAD to 3D — SketchUp Extension

Plugin chuyên nghiệp tự động chuyển đổi bản vẽ 2D DWG kiến trúc từ AutoCAD thành mô hình 3D SketchUp phân lớp chuẩn xác và bộ công cụ tương tác mạnh mẽ cho kiến trúc sư.

---

## 🚀 Các tính năng chính

1. **[TẠO 3D] 1-Click Paste từ AutoCAD (Ctrl+C):**
   - Quét chọn đối tượng trên AutoCAD $\rightarrow$ `Ctrl + C` $\rightarrow$ Quay lại SketchUp bấm `[TẠO 3D]` để dựng tường, cửa đi, cửa sổ 3D tự động.
2. **Kiến trúc Wall Face 2D (Không dùng Boolean):**
   - Dựng tường mượt mà, topology sạch sẽ, không lỗi mặt giáp mí.
3. **[WALLFILL] Tạo Lanh-tô & Bậu cửa Tương Tác:**
   - Click trực tiếp vào mặt hốc tường để đùn khối lanh-tô cửa đi hoặc bậu cửa sổ.
4. **[CỬA] Thêm Cửa vào Opening:**
   - Click hốc tường để tự động tính khẩu độ $W \times H \times D$ và lắp cửa nhôm kính Profile V20 chuẩn thi công (Hỗ trợ giữ `Alt` để click 2 điểm thủ công).
5. **[TƯỜNG] Ẩn Nét Trùng Lặp (Hide Overlap):**
   - Ẩn toàn bộ các đường nét phân chia, nét giáp ranh giữa các khối tường trong 1 click.
6. **Resize Door/Window:**
   - Sửa kích thước hàng loạt cửa mà không làm biến dạng profile nhôm kính.
7. **[THANG] Tạo Cầu Thang 3D:**
   - Dựng cầu thang chuẩn kết cấu thi công và số bậc phong thủy kèm lan can uốn lượn.
8. **[CHỤP 3D] Interactive 3D Snapshot & Framing Tool:**
   - Cắt khung hình trực quan (16:9, 4:3, 1:1, 3:4, 9:16, Full Screen), xuất ảnh 2K/4K khử răng cưa và copy vào Clipboard để dán ngay vào Google Flow, Photoshop, Zalo.

---

## 🛠 Cài đặt

1. Chạy file `build_rbz.ps1` bằng PowerShell để tạo file `nauq_cad_to_3d.rbz`.
2. Mở SketchUp $\rightarrow$ `Extensions` $\rightarrow$ `Extension Manager` $\rightarrow$ `Install Extension` $\rightarrow$ Chọn `nauq_cad_to_3d.rbz`.
