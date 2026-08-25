# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Interactive Viewport Framing & Crop Tool for SketchUp
    # Cho phép kiến trúc sư điều chỉnh khung cắt, chọn tỉ lệ (16:9, 4:3, 1:1, 3:4, 9:16)
    # và độ phân giải xuất (2K/4K/FHD) trực quan trên màn hình rồi copy ngay vào Clipboard.
    class SnapshotCropTool
      ASPECT_RATIOS = [
        { key: :r16_9, name: '16:9 (Landscape)', ratio: 16.0 / 9.0, key_num: '1' },
        { key: :r4_3,  name: '4:3 (Interior)',   ratio: 4.0 / 3.0,  key_num: '2' },
        { key: :r1_1,  name: '1:1 (Square)',     ratio: 1.0,        key_num: '3' },
        { key: :r3_4,  name: '3:4 (Portrait)',   ratio: 3.0 / 4.0,  key_num: '4' },
        { key: :r9_16, name: '9:16 (Story/Reels)', ratio: 9.0 / 16.0, key_num: '5' },
        { key: :free,  name: 'Toàn Màn Hình',   ratio: nil,        key_num: '6' }
      ].freeze

      RESOLUTIONS = [
        { name: '2K QHD (2560px)', width: 2560 },
        { name: '4K UHD (3840px)', width: 3840 },
        { name: 'Full HD (1920px)', width: 1920 }
      ].freeze

      def initialize
        @aspect_index = 0 # Mặc định 16:9
        @res_index = 0    # Mặc định 2K
        @scale = 0.85     # Tỉ lệ khung hình so với khung nhìn
        @center_x = nil
        @center_y = nil
        @dragging = false
        @drag_start_x = 0
        @drag_start_y = 0
        @drag_orig_cx = 0
        @drag_orig_cy = 0
      end

      def activate
        view = Sketchup.active_model.active_view
        reset_frame(view)
        update_status_text
        view.invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def resume(view)
        update_status_text
        view.invalidate if view
      end

      def reset_frame(view)
        vw = view.vpwidth.to_f
        vh = view.vpheight.to_f
        @center_x = vw / 2.0
        @center_y = vh / 2.0
      end

      # Tính toán toạ độ hộp cắt thực tế trên màn hình: [left, top, right, bottom, width, height]
      def current_box(view)
        vw = view.vpwidth.to_f
        vh = view.vpheight.to_f
        @center_x ||= vw / 2.0
        @center_y ||= vh / 2.0

        current_ratio = ASPECT_RATIOS[@aspect_index][:ratio]
        if current_ratio.nil?
          bw = vw * @scale
          bh = vh * @scale
        else
          vp_ratio = vw / vh
          if current_ratio >= vp_ratio
            bw = vw * @scale
            bh = bw / current_ratio
          else
            bh = vh * @scale
            bw = bh * current_ratio
          end
        end

        half_w = bw / 2.0
        half_h = bh / 2.0

        # Giữ tâm không bị trượt ra ngoài màn hình quá xa
        cx = [[@center_x, half_w].max, vw - half_w].min
        cy = [[@center_y, half_h].max, vh - half_h].min

        left = cx - half_w
        top = cy - half_h
        right = cx + half_w
        bottom = cy + half_h

        [left, top, right, bottom, bw, bh]
      end

      def onLButtonDown(flags, x, y, view)
        left, top, right, bottom, _bw, _bh = current_box(view)
        if x >= left && x <= right && y >= top && y <= bottom
          @dragging = true
          @drag_start_x = x
          @drag_start_y = y
          @drag_orig_cx = @center_x
          @drag_orig_cy = @center_y
        else
          @center_x = x.to_f
          @center_y = y.to_f
          view.invalidate
        end
      end

      def onMouseMove(flags, x, y, view)
        if @dragging
          dx = x - @drag_start_x
          dy = y - @drag_start_y
          @center_x = @drag_orig_cx + dx
          @center_y = @drag_orig_cy + dy
          view.invalidate
        end
      end

      def onLButtonUp(flags, x, y, view)
        @dragging = false
      end

      def onLButtonDoubleClick(flags, x, y, view)
        execute_capture(view)
      end

      def onMouseWheel(flags, delta, x, y, view)
        step = delta > 0 ? 0.05 : -0.05
        @scale = [[@scale + step, 0.2].max, 0.98].min
        view.invalidate
      end

      def onKeyDown(key, repeat, flags, view)
        case key
        when 13, 32 # Enter hoặc Space
          execute_capture(view)
        when 27 # Escape
          Sketchup.active_model.select_tool(nil)
        when 49..54 # Phím số '1' đến '6'
          @aspect_index = key - 49
          update_status_text
          view.invalidate
        when 82, 114 # Phím 'R' / 'r' -> Đổi độ phân giải
          @res_index = (@res_index + 1) % RESOLUTIONS.size
          update_status_text
          view.invalidate
        when 37 # Mũi tên Trái
          @center_x -= 15
          view.invalidate
        when 39 # Mũi tên Phải
          @center_x += 15
          view.invalidate
        when 38 # Mũi tên Lên
          @center_y -= 15
          view.invalidate
        when 40 # Mũi tên Xuống
          @center_y += 15
          view.invalidate
        end
      end

      def getMenu(menu, flags, x, y, view)
        menu.add_item("📸 Chụp & Copy Clipboard (Enter)") { execute_capture(view) }
        menu.add_separator

        aspect_sub = menu.add_submenu("Tỉ lệ khung hình (Aspect Ratio)")
        ASPECT_RATIOS.each_with_index do |asp, idx|
          checked = (idx == @aspect_index)
          item = aspect_sub.add_item("#{asp[:key_num]}. #{asp[:name]}") do
            @aspect_index = idx
            update_status_text
            view.invalidate
          end
          aspect_sub.set_validation_proc(item) { checked ? MF_CHECKED : MF_UNCHECKED }
        end

        res_sub = menu.add_submenu("Độ phân giải xuất (Resolution)")
        RESOLUTIONS.each_with_index do |res, idx|
          checked = (idx == @res_index)
          item = res_sub.add_item(res[:name]) do
            @res_index = idx
            update_status_text
            view.invalidate
          end
          res_sub.set_validation_proc(item) { checked ? MF_CHECKED : MF_UNCHECKED }
        end

        menu.add_separator
        menu.add_item("Căn giữa khung nhìn (Reset Frame)") do
          reset_frame(view)
          @scale = 0.85
          view.invalidate
        end
        menu.add_item("Thoát chế độ chụp (Esc)") do
          Sketchup.active_model.select_tool(nil)
        end
      end

      def update_status_text
        asp = ASPECT_RATIOS[@aspect_index]
        res = RESOLUTIONS[@res_index]
        Sketchup.status_text = "NAUQ Snapshot: Tỉ lệ [#{asp[:name]}] • Độ phân giải [#{res[:name]}] • [Kéo chuột] Move vùng cắt • [Lăn chuột] Co giãn • [Enter] Chụp & Copy Clipboard • [1-6] Đổi tỉ lệ • [R] Đổi độ phân giải"
      end

      def draw2d(view)
        vw = view.vpwidth.to_f
        vh = view.vpheight.to_f
        left, top, right, bottom, bw, bh = current_box(view)

        # 1. Viền tối mờ che ngoài khung chụp (Cinematic Matte Overlay)
        mask_color = Sketchup::Color.new(0, 0, 0, 160)
        view.drawing_color = mask_color

        # Top bar
        view.draw2d(GL_QUADS, [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(vw, 0, 0),
          Geom::Point3d.new(vw, top, 0),
          Geom::Point3d.new(0, top, 0)
        ]) if top > 0

        # Bottom bar
        view.draw2d(GL_QUADS, [
          Geom::Point3d.new(0, bottom, 0),
          Geom::Point3d.new(vw, bottom, 0),
          Geom::Point3d.new(vw, vh, 0),
          Geom::Point3d.new(0, vh, 0)
        ]) if bottom < vh

        # Left bar
        view.draw2d(GL_QUADS, [
          Geom::Point3d.new(0, top, 0),
          Geom::Point3d.new(left, top, 0),
          Geom::Point3d.new(left, bottom, 0),
          Geom::Point3d.new(0, bottom, 0)
        ]) if left > 0

        # Right bar
        view.draw2d(GL_QUADS, [
          Geom::Point3d.new(right, top, 0),
          Geom::Point3d.new(vw, top, 0),
          Geom::Point3d.new(vw, bottom, 0),
          Geom::Point3d.new(right, bottom, 0)
        ]) if right < vw

        # 2. Đường lưới bố cục 1/3 (Rule of Thirds)
        third_w = bw / 3.0
        third_h = bh / 3.0
        view.drawing_color = Sketchup::Color.new(255, 255, 255, 75)
        view.line_width = 1

        # Lưới dọc
        view.draw2d(GL_LINES, [
          Geom::Point3d.new(left + third_w, top, 0),
          Geom::Point3d.new(left + third_w, bottom, 0),
          Geom::Point3d.new(left + 2 * third_w, top, 0),
          Geom::Point3d.new(left + 2 * third_w, bottom, 0)
        ])

        # Lưới ngang
        view.draw2d(GL_LINES, [
          Geom::Point3d.new(left, top + third_h, 0),
          Geom::Point3d.new(right, top + third_h, 0),
          Geom::Point3d.new(left, top + 2 * third_h, 0),
          Geom::Point3d.new(right, top + 2 * third_h, 0)
        ])

        # 3. Viền khung cắt chính (Xanh lam công nghệ SketchUp)
        view.drawing_color = Sketchup::Color.new(37, 99, 235, 255)
        view.line_width = 2
        view.draw2d(GL_LINE_LOOP, [
          Geom::Point3d.new(left, top, 0),
          Geom::Point3d.new(right, top, 0),
          Geom::Point3d.new(right, bottom, 0),
          Geom::Point3d.new(left, bottom, 0)
        ])

        # 4. Góc vuông nhấn (Corner Brackets trắng)
        bracket_len = [30, bw * 0.1].min
        view.drawing_color = Sketchup::Color.new(255, 255, 255, 255)
        view.line_width = 3
        # Top-Left
        view.draw2d(GL_LINES, [
          Geom::Point3d.new(left, top + bracket_len, 0), Geom::Point3d.new(left, top, 0),
          Geom::Point3d.new(left, top, 0), Geom::Point3d.new(left + bracket_len, top, 0)
        ])
        # Top-Right
        view.draw2d(GL_LINES, [
          Geom::Point3d.new(right - bracket_len, top, 0), Geom::Point3d.new(right, top, 0),
          Geom::Point3d.new(right, top, 0), Geom::Point3d.new(right, top + bracket_len, 0)
        ])
        # Bottom-Right
        view.draw2d(GL_LINES, [
          Geom::Point3d.new(right, bottom - bracket_len, 0), Geom::Point3d.new(right, bottom, 0),
          Geom::Point3d.new(right, bottom, 0), Geom::Point3d.new(right - bracket_len, bottom, 0)
        ])
        # Bottom-Left
        view.draw2d(GL_LINES, [
          Geom::Point3d.new(left + bracket_len, bottom, 0), Geom::Point3d.new(left, bottom, 0),
          Geom::Point3d.new(left, bottom, 0), Geom::Point3d.new(left, bottom - bracket_len, 0)
        ])

        # 5. Dấu hồng tâm căn trung tâm (Center Crosshair)
        cx = left + bw / 2.0
        cy = top + bh / 2.0
        cross_s = 8
        view.drawing_color = Sketchup::Color.new(255, 255, 255, 200)
        view.line_width = 1
        view.draw2d(GL_LINES, [
          Geom::Point3d.new(cx - cross_s, cy, 0), Geom::Point3d.new(cx + cross_s, cy, 0),
          Geom::Point3d.new(cx, cy - cross_s, 0), Geom::Point3d.new(cx, cy + cross_s, 0)
        ])

        # 6. Nhãn thông tin HUD
        asp = ASPECT_RATIOS[@aspect_index]
        res = RESOLUTIONS[@res_index]
        hud_text = "Tỉ lệ: #{asp[:name]} | #{res[:name]} | [Kéo chuột] Move | [Enter / Click đúp] Chụp"
        view.draw_text(Geom::Point3d.new(left + 10, [top - 20, 10].max, 0), hud_text)
      end

      # Thực hiện chụp ảnh và cắt pixel chính xác theo khung
      def execute_capture(view)
        left, top, right, bottom, bw, bh = current_box(view)
        vw = view.vpwidth.to_f
        vh = view.vpheight.to_f

        res = RESOLUTIONS[@res_index]
        export_scale = res[:width].to_f / bw
        export_vw = (vw * export_scale).round
        export_vh = (vh * export_scale).round

        temp_dir = defined?(Sketchup) && Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : (ENV['TEMP'] || '/tmp')
        stamp = Time.now.strftime('%Y%m%d_%H%M%S')
        raw_path = File.join(temp_dir, "nauq_raw_#{stamp}.png").tr('/', '\\')
        final_path = File.join(temp_dir, "nauq_crop_#{stamp}.png").tr('/', '\\')

        # Xuất ảnh toàn cảnh độ nét cao antialiased
        view.write_image({
          filename: raw_path,
          width: export_vw,
          height: export_vh,
          antialias: true,
          compression: 0.9,
          transparent: false
        })

        unless File.exist?(raw_path) && File.size(raw_path) > 0
          ::UI.messagebox("Không thể chụp ảnh từ khung nhìn SketchUp.", MB_OK)
          return
        end

        # Cắt pixel chính xác theo toạ độ vùng cắt
        crop_x = (left * export_scale).round
        crop_y = (top * export_scale).round
        crop_w = (bw * export_scale).round
        crop_h = (bh * export_scale).round

        # Đảm bảo không tràn kích thước
        crop_w = [crop_w, export_vw - crop_x].min
        crop_h = [crop_h, export_vh - crop_y].min

        if Gem.win_platform? || RUBY_PLATFORM =~ /mswin|mingw|cygwin/
          ps_cmd = <<~POWERSHELL
            powershell -NoProfile -ExecutionPolicy Bypass -Command "
              Add-Type -AssemblyName System.Drawing;
              Add-Type -AssemblyName System.Windows.Forms;
              $src = [System.Drawing.Bitmap]::FromFile('#{raw_path.gsub("'", "''")}');
              $rect = [System.Drawing.Rectangle]::new(#{crop_x}, #{crop_y}, #{crop_w}, #{crop_h});
              $dest = $src.Clone($rect, $src.PixelFormat);
              $src.Dispose();
              $dest.Save('#{final_path.gsub("'", "''")}');
              [System.Windows.Forms.Clipboard]::SetImage($dest);
              $dest.Dispose();
            "
          POWERSHELL
          system(ps_cmd.tr("\n", ' '))
        end

        File.delete(raw_path) rescue nil

        Sketchup.status_text = "✓ Đã chụp & cắt khung hình #{crop_w}x#{crop_h}px lưu vào Clipboard! (Bấm Ctrl+V để dán)"
        ::UI.messagebox("✓ Đã chụp và cắt ảnh thành công!\n\n• Kích thước: #{crop_w} x #{crop_h} px\n• Tỉ lệ: #{ASPECT_RATIOS[@aspect_index][:name]}\n• Đã sao chép vào Clipboard\n\nBạn chỉ cần bấm Ctrl+V trên trình duyệt (Google Flow / Zalo / Photoshop / AI) để dán ảnh ngay!", MB_OK)

        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
