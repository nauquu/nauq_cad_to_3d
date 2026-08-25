Bạn là một lập trình viên chuyên sâu về SketchUp Ruby API, phát triển plugin SketchUp chuyên nghiệp.

Tôi cần bạn xây dựng một plugin SketchUp có tên tạm là:

NAUQ_CAD_TO_3D

Mục tiêu:

Chuyển bản vẽ kiến trúc DWG 2D (mm) thành mô hình SketchUp 3D tự động:

Tạo tường 3D
Tạo opening
Tạo cửa đi
Tạo cửa sổ
Giữ nguyên CAD gốc để đối chiếu
Có hệ thống Setting
Có Error Report + Highlight vị trí lỗi

Không được tự bịa thêm logic. Nếu thiếu thông tin phải hỏi lại trước khi code.

1. Công nghệ

Platform:

SketchUp Plugin
Ruby API
Không dùng thư viện ngoài nếu không cần thiết.

Yêu cầu code:

Modular
Dễ mở rộng
Không viết toàn bộ trong một file.
Comment rõ chức năng.
2. Kiến trúc thư mục

Tạo cấu trúc:

NAUQ_CAD_TO_3D/

├── nauq_cad_to_3d.rb

├── core/
│   ├── config.rb
│   ├── logger.rb
│   ├── attribute.rb
│   └── geometry.rb

├── import/
│   ├── dwg_reader.rb
│   ├── layer_parser.rb
│   └── block_parser.rb

├── wall/
│   ├── wall_builder.rb
│   ├── wall_cleanup.rb
│   └── wall_detector.rb

├── opening/
│   ├── opening_detector.rb
│   ├── opening_normalizer.rb
│   └── wall_cutter.rb

├── door/
│   ├── door_builder.rb
│   ├── frame_builder.rb
│   ├── leaf_builder.rb
│   └── glass_builder.rb

├── window/
│   └── window_builder.rb

├── library/
│   └── template_loader.rb

└── ui/
    ├── settings_dialog.rb
    └── report_dialog.rb
3. Luồng hoạt động chính

Khi người dùng bấm:

[TẠO 3D]

Plugin chạy:

Load Settings

↓

Import DWG

↓

Giữ CAD gốc

↓

Đọc layer

↓

Tạo tường

↓

Detect cửa

↓

Detect cửa sổ

↓

Tạo opening

↓

Insert cửa

↓

Insert cửa sổ

↓

Kiểm tra lỗi

↓

Hiển thị Error Report
4. Quản lý model SketchUp

Tạo các group chính:

NAUQ_Architecture

├── NAUQ_CAD_ORIGINAL

├── NAUQ_WALLS

├── NAUQ_DOORS

└── NAUQ_WINDOWS
5. Import CAD

Input:

DWG only
Unit: mm

Không xử lý:

DXF
inch
cm
m

CAD gốc:

NAUQ_CAD_ORIGINAL

Không được:

sửa line
move
trim
đổi layer
xóa dữ liệu

Mọi xử lý thực hiện trên dữ liệu copy/phân tích.

6. Setting

Tất cả phải nằm trong Dialog.

Wall

Default:

Layer:
0-netcat

Height:
(user nhập)

Tolerance:
5mm
Door

Default:

Layer:
0-cua

Block:
CUA DI

Max Width:
(user nhập)
Window

Default:

Layer:
nho

Height:
(user nhập)

Offset:
(user nhập)

Max Width:
(user nhập)
Global
Frame size:
50mm

Glass height:
350mm

Tolerance:
5mm
7. Wall Builder

Nguồn:

Layer 0-netcat

Đặc điểm:

Có thể là Line hoặc Polyline.
Là biên tường.
Không phải tim tường.
Không có wall thickness setting.

Tạo tường:

0-netcat

↓

Cleanup

↓

Tạo face kín

↓

Push/Pull theo chiều cao

↓

NAUQ_WALLS
8. Cleanup tường

Mức tự động:

C

Tức:

Tự sửa lỗi nhỏ:

Ví dụ:

điểm lệch nhỏ hơn tolerance
khe hở nhỏ
snap điểm gần nhau
Không tự sửa:
nhiều phương án nối
hình học không rõ

Phải tạo Report.

Ví dụ:

Không xác định được vùng tường kín

[Xem trên bản vẽ]
9. NAUQ_WALLS

Toàn bộ tường:

1 Group duy nhất

Không tạo:

Wall_001
Wall_002
10. Door Detection

Nguồn:

Layer:
0-cua

Block:
CUA DI

Sau này layer/block có thể đổi trong Setting.

11. Window Detection

Nguồn:

Layer:
nho

Không có block.

Cửa sổ:

nằm giữa hai biên tường.
width phủ bì bằng khoảng cách hai tường.
12. Opening

Cửa và cửa sổ:

Không sửa CAD.

Chỉ chỉnh model 3D.

Nếu kích thước không chia đẹp:

Ưu tiên:

Chia hết 10mm
Nếu không được chia hết 5mm

Chọn cạnh dịch:

tìm edge tường gần nhất.
giữ bên có kích thước đẹp hơn.
13. Door Library

File:

DOOR_TEMPLATE.skp

Cấu trúc:

FRAME (Group)

LEAF (Component)

GLASS (Group)
14. Frame

Trong group FRAME:

FRAME

├── F_LEFT
├── F_RIGHT
├── F_TOP
├── F_GLASS_BOTTOM
└── F_BOTTOM

Tất cả khung:

50mm

Khi đổi width:

Giữ:

F_LEFT
F_RIGHT

Scale/kéo dài:

F_TOP
F_GLASS_BOTTOM
F_BOTTOM

Không scale toàn bộ frame.

15. Leaf

LEAF là Component.

Cấu trúc:

LEAF

├── L_VERTICAL_LEFT

├── L_VERTICAL_RIGHT

├── L_HORIZONTAL_TOP

└── L_HORIZONTAL_BOTTOM

Khi đổi width:

Giữ:

L_VERTICAL_LEFT
L_VERTICAL_RIGHT

Kéo dài:

L_HORIZONTAL_TOP
L_HORIZONTAL_BOTTOM

Không scale toàn bộ leaf.

16. Glass

Quy tắc:

1 cửa = 1 tấm kính

Không chia theo cánh.

Ví dụ:

Cửa 4 cánh:

LEAF_01
LEAF_02
LEAF_03
LEAF_04

GLASS

Glass:

giữ material
scale theo kích thước mới
17. Chia cánh

Theo:

Max Width

Ví dụ:

Opening width = 2500
Max width = 900

=> 3 cánh.

Công thức:

Leaf width =
(Opening width - 100) / số cánh
18. Cửa sổ

Logic giống cửa đi 100%.

Khác:

Có thêm:

F_BOTTOM

F_BOTTOM:

luôn nằm đáy opening.
19. Chiều cao cửa
Có ô kính trên:

Từ trên xuống:

F_TOP       50mm

GLASS

F_GLASS_BOTTOM 50mm

LEAF


Công thức:

H_leaf = H_door - H_glass - 100
Không có ô kính:
F_TOP 50

LEAF

Công thức:

H_leaf = H_door - 50
20. Cửa sổ

Có thêm:

F_BOTTOM 50mm

Đáy opening:

Offset trong Dialog
21. Attribute Dictionary

Không quản lý bằng tên group.

Mỗi object phải có attribute.

Ví dụ:

entity.set_attribute(
"NAUQ_DOOR",
"type",
"door"
)

entity.set_attribute(
"NAUQ_DOOR",
"width",
1200
)

entity.set_attribute(
"NAUQ_DOOR",
"leaf_count",
2
)
22. Error Report

Không cần bảng thống kê.

Chỉ lỗi/cảnh báo.

Ví dụ:

CAD TO 3D REPORT

Warning:

Door #05
Không tìm thấy biên tường

[Xem trên bản vẽ]

Khi click:

zoom tới vị trí
highlight lỗi
23. Quy tắc code

Không được:

hard-code layer.
hard-code kích thước.
sửa CAD gốc.
scale toàn bộ cửa.
tạo nhiều group tường.

Mọi thông số phải đi qua Config.

24. Cách làm việc

Không viết toàn bộ plugin một lần.

Làm từng module:

Phase 1:

Plugin load
UI Settings
Import DWG
Layer reader

Phase 2:

Wall Builder

Phase 3:

Opening Detection

Phase 4:

Door Builder

Phase 5:

Window Builder

Phase 6:

Report System

Sau mỗi phase:

giải thích code;
đưa file;
hướng dẫn test trong SketchUp.

Nếu có điểm chưa rõ, hãy hỏi trước khi code.