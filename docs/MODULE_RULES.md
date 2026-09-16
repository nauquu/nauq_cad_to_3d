# MODULE RULES & CONSTRAINTS — NAUQ CAD TO 3D

This document specifies mandatory architectural invariants, constraints, and coding standards required when developing or refactoring the plugin.

---

## 1. Strict "DO NOT" Invariants

1. **DO NOT Use `WallCutter` or Boolean Cutting:**
   - Never invoke `cut_all_openings`, `intersect_with`, or construct bounding boxes to slice or punch through walls.
   - Never build a continuous solid wall to subsequently subtract opening volumes.

2. **DO NOT Pushpull Walls Before Normalizing Openings:**
   - Do not extrude 2D wall faces during the reference generation phase.
   - All wall pushpull operations must execute exactly once in Phase 5 after the complete `normalized_openings` list is finalized.

3. **DO NOT Hardcode Global Coordinates (Global X/Y):**
   - All geometric calculations on walls and openings must utilize the local vector basis: $U$ (longitudinal along wall), $N$ (transverse/thickness), and $Z$ (vertical).

4. **DO NOT Swallow Exceptions:**
   - Geometry generation failures or `add_face` errors must be logged via `Logger.warn` or `Logger.error` with entity coordinates and IDs.
   - If an opening fails to generate, isolate and skip that opening while completing the rest of the model; **never crash the entire execution pipeline**.

5. **DO NOT Alter the Root Container Group Structure:**
   - All 3D entities must reside within their designated root-level groups: `NAUQ_CAD_ORIGINAL`, `NAUQ_WALLS`, `NAUQ_DOORS`, `NAUQ_WINDOWS`, `NAUQ_SLAB`.
   - Do not introduce wrapping parent groups around these top-level containers.

6. **DO NOT Add Bottom Fix Panels to Doors (`has_fix_bottom`):**
   - Doors must never feature bottom fix panels (`has_fix_bottom`). Bottom fix logic is exclusively reserved for windows (`:window`). UI dialogs and generators must enforce `has_fix_bottom = false` for doors.

7. **DO NOT Pass Duplicate Adjacent Vertices to `entities.add_face`:**
   - SketchUp C++ kernel strictly raises `ArgumentError: Duplicate points in array` when consecutive or closing vertices have distance $< 0.001\text{mm}$. Always sanitize and deduplicate contour points before building faces for curved/arched profiles.

---

## 2. Measurement Units & Geometric Tolerances

- **User Interface & Configuration:** Always displayed and received in **Millimeters (mm)**.
- **SketchUp Internal Representation:** The SketchUp Ruby API internally measures lengths in **Inches**.
- **Unit Conversions:** Always use conversion helpers from `Core::GeometryHelper` (`mm_to_inch`, `inch_to_mm`).
- **Geometric Tolerances:**
  - Vertex Clustering / Snapping: `10.0 mm`
  - Point-to-Plane Distance Threshold: `5.0 mm`
  - Vector Parallelism Tolerance: `0.001 radian (~0.05 degrees)`

---

## 3. Code Quality & Linting (RuboCop-SketchUp Compliance)

The codebase must maintain **0 offenses** when scanned with `rubocop-sketchup` (standard ruleset required by the SketchUp Extension Warehouse technical review team):

1. **Operation Names (Undo Stack):** `start_operation` names must be $\le$ **25 characters**, Title Case, with no punctuation or file extensions (`.rb`/`.rbe`) per `SketchupSuggestions/OperationName`.
2. **Overlay Drawing Tools:** Every interactive tool implementing `draw` must implement `getExtents` (to prevent viewport clipping) and invalidate the view in `suspend` and `deactivate`. Tools accepting VCB typed inputs must implement `enableVCB?`.
3. **Encoding for `__FILE__` / `__dir__`:** Paths must be duplicated and UTF-8 forced (`.dup.force_encoding('UTF-8')`) before file operations to avoid Windows path encoding bugs on non-ASCII user profiles.
4. **Root-Context Geometry (`model.entities` / `add_group`):** Deliberately allowed for root-level container initialization, but **must** include `# rubocop:disable SketchupSuggestions/ModelEntities` (or `AddGroup`) with an accompanying explanatory comment.
5. **Console Output:** Raw `puts` is prohibited. Use `NAUQ::CadTo3D.debug_puts` (gated by `DEBUG_MODE`) to comply with Extension Warehouse guidelines.

---

## Tóm tắt tiếng Việt (Vietnamese Summary)

### Các nguyên tắc bất biến & Ràng buộc cốt lõi
1. **Tuyệt đối cấm:**
   - Không dùng Boolean/WallCutter để đục tường (phải dùng Face 2D + WallFill).
   - Không pushpull trước khi chuẩn hóa xong lỗ mở.
   - Không tính toán theo trục toàn cục $X, Y$ (bắt buộc dùng hệ vector cục bộ $U, N, Z$).
   - Không nuốt lỗi (phải log cảnh báo và cô lập lỗi từng cửa, không làm crash cả lệnh).
   - Không thay đổi 5 group gốc: `NAUQ_CAD_ORIGINAL`, `NAUQ_WALLS`, `NAUQ_DOORS`, `NAUQ_WINDOWS`, `NAUQ_SLAB`.
2. **Quy chuẩn đơn vị:**
   - Input/UI luôn là Milimét (mm), SketchUp nội bộ là Inch $\rightarrow$ Luôn đổi qua `GeometryHelper`.
   - Dung sai: Snap đỉnh `10mm`, sai số mặt phẳng `5mm`, góc song song `0.001 rad`.
3. **Chuẩn kiểm tra RuboCop-SketchUp (Extension Warehouse):**
   - Tên Undo $\le 25$ ký tự, Title Case.
   - Tool vẽ preview bắt buộc có `getExtents`, `suspend`, `deactivate` (`view.invalidate`).
   - Xử lý mã hóa UTF-8 cho đường dẫn file (`.dup.force_encoding('UTF-8')`).
   - Không dùng `puts` trực tiếp (chỉ in log console qua `debug_puts` khi bật `DEBUG_MODE`).
