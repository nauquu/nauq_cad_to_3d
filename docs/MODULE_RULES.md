# MODULE RULES & CONSTRAINTS — NAUQ CAD TO 3D

Tài liệu quy định các nguyên tắc bất biến (Invariants), giới hạn và quy chuẩn lập trình bắt buộc khi phát triển hoặc sửa đổi plugin.

---

## 1. Các nguyên tắc cấm (STRICT "DO NOT" RULES)

1. **KHÔNG dùng `WallCutter` hay Boolean cutting:**
   - Tuyệt đối không gọi `cut_all_openings`, `intersect_with`, hoặc tạo khối hộp cutter đục xuyên qua tường.
   - Không được dựng solid tường bao trùm rồi cắt bỏ vùng cửa.

2. **KHÔNG pushpull tường trước khi biết Opening:**
   - Không được pushpull Wall Face 2D trong giai đoạn reference.
   - Toàn bộ pushpull chỉ diễn ra 1 lần duy nhất ở Phase 5 sau khi đã có đầy đủ danh sách `normalized_openings`.

3. **KHÔNG hardcode trục tọa độ toàn cục (Global X/Y):**
   - Mọi tính toán hình học trên tường/cửa phải dùng hệ vector cục bộ: $U$ (dọc tường), $N$ (ngang tường), $Z$ (thẳng đứng).

4. **KHÔNG nuốt Exception (Do NOT swallow exceptions):**
   - Mọi lỗi hình học hay add_face thất bại phải được ghi nhận qua `Logger.warn` hoặc `Logger.error` kèm tọa độ / ID đối tượng.
   - Nếu một opening bị lỗi không tạo được profile, bỏ qua opening đó và tiếp tục dựng các phần còn lại, **không làm crash toàn bộ quy trình**.

5. **KHÔNG thay đổi cấu trúc 4 Group Container cấp gốc:**
   - Mọi thực thể 3D phải nằm đúng trong một trong các nhóm: `NAUQ_CAD_ORIGINAL`, `NAUQ_WALLS`, `NAUQ_DOORS`, `NAUQ_WINDOWS`, `NAUQ_SLAB`.
   - Không tạo thêm group container cha bao bọc bên ngoài.

---

## 2. Quy chuẩn đơn vị đo lường (Units & Tolerances)

- **Giao diện & Cấu hình:** Luôn hiển thị và nhận đầu vào bằng đơn vị **Milimét (mm)**.
- **SketchUp Internal:** API SketchUp dùng đơn vị **Inches**.
- **Chuyển đổi:** Bắt buộc sử dụng các hàm tiện ích trong `Core::GeometryHelper` (`mm_to_inch`, `inch_to_mm`).
- **Dung sai hình học (Geometric Tolerances):**
  - Snap điểm nối nét (Vertex Clustering): `10.0 mm`
  - Sai số khoảng cách điểm tới mặt phẳng (Point-to-Plane): `5.0 mm`
  - Sai số song song giữa 2 vector: `0.001 radian (~0.05 độ)`

---

## 3. Code Quality / Lint (RuboCop-SketchUp)

Toàn bộ codebase phải giữ **0 offenses** khi quét bằng `rubocop-sketchup` (config mặc định của gem) — đây là bộ công cụ reviewer Extension Warehouse dùng để kiểm tra extension.

1. **Tên operation (Undo):** `start_operation` tối đa **25 ký tự**, Title Case, không dấu câu, không đuôi `.rbe/.rb` — theo `SketchupSuggestions/OperationName`.
2. **Tool vẽ overlay:** Mọi tool có `draw` bắt buộc implement `getExtents` (tránh bị cắt góc) và `suspend`/`deactivate` phải gọi `view.invalidate`; tool nhận input qua VCB phải có `enableVCB?`.
3. **`__FILE__` / `__dir__`:** Luôn `dup` + `force_encoding('UTF-8')` trước khi dùng (bug encoding Windows trên máy có tên user không phải ASCII).
4. **Root-context `model.entities` / `add_group`:** Cho phép ngoại lệ có chủ đích (build vào group container cấp gốc `NAUQ_*` bất kể active context), nhưng **bắt buộc** kèm directive `# rubocop:disable SketchupSuggestions/ModelEntities` (hoặc `AddGroup`) và **comment giải thích lý do** ngay tại dòng/module đó.
5. **Console output:** Chỉ in qua `NAUQ::CadTo3D.debug_puts` (gated bởi `DEBUG_MODE`), không dùng `puts` trần — yêu cầu của Extension Warehouse.
