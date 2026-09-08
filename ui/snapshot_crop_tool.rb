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

      HANDLE_SIZE = 26.0 # Kích thước vùng bắt kéo góc

      # Pre-allocated frozen colors to eliminate Ruby Garbage Collection (GC) lag during mouse dragging
      COLOR_MASK    = Sketchup::Color.new(0, 0, 0, 160)
      COLOR_GRID    = Sketchup::Color.new(255, 255, 255, 60)
      COLOR_FRAME   = Sketchup::Color.new(37, 99, 235, 255)
      COLOR_BRACKET = Sketchup::Color.new(255, 255, 255, 255)
      COLOR_HANDLE  = Sketchup::Color.new(255, 255, 255, 220)
      COLOR_CROSS   = Sketchup::Color.new(255, 255, 255, 180)

      CURSOR_NWSE_SVG = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
          <path d="M 5,5 L 14,5 L 11,8 L 21,18 L 24,15 L 24,24 L 15,24 L 18,21 L 8,11 L 5,14 Z" fill="#FFFFFF" stroke="#000000" stroke-width="2" stroke-linejoin="round"/>
        </svg>
      SVG

      CURSOR_NESW_SVG = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
          <path d="M 27,5 L 27,14 L 24,11 L 14,21 L 17,24 L 8,24 L 8,15 L 11,18 L 21,8 L 18,5 Z" fill="#FFFFFF" stroke="#000000" stroke-width="2" stroke-linejoin="round"/>
        </svg>
      SVG

      CURSOR_MOVE_SVG = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
          <path d="M 16,3 L 21,8 L 18,8 L 18,14 L 24,14 L 24,11 L 29,16 L 24,21 L 24,18 L 18,18 L 18,24 L 21,24 L 16,29 L 11,24 L 14,24 L 14,18 L 8,18 L 8,21 L 3,16 L 8,11 L 8,14 L 14,14 L 14,8 L 11,8 Z" fill="#FFFFFF" stroke="#000000" stroke-width="2" stroke-linejoin="round"/>
        </svg>
      SVG

      def initialize
        @aspect_index = 0 # Mặc định 16:9
        @res_index = 0    # Mặc định 2K
        @scale = 0.85     # Tỉ lệ khung hình so với khung nhìn
        @center_x = nil
        @center_y = nil
        @drag_mode = nil  # nil, :move, :resize_tl, :resize_tr, :resize_br, :resize_bl
        @current_hit = nil
        @drag_start_x = 0
        @drag_start_y = 0
        @drag_orig_cx = 0
        @drag_orig_cy = 0
        @drag_orig_scale = 0.85
        @cursors_initialized = false
      end

      def initialize_cursors
        return if @cursors_initialized
        @cursors_initialized = true

        temp_dir = defined?(Sketchup) && Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : (ENV['TEMP'] || '/tmp')
        nwse_path = File.join(temp_dir, 'nauq_cursor_nwse.svg').tr('\\', '/')
        nesw_path = File.join(temp_dir, 'nauq_cursor_nesw.svg').tr('\\', '/')
        move_path = File.join(temp_dir, 'nauq_cursor_move.svg').tr('\\', '/')

        File.write(nwse_path, CURSOR_NWSE_SVG) rescue nil
        File.write(nesw_path, CURSOR_NESW_SVG) rescue nil
        File.write(move_path, CURSOR_MOVE_SVG) rescue nil

        @cursor_nwse = ::UI.create_cursor(nwse_path, 16, 16) rescue nil
        @cursor_nesw = ::UI.create_cursor(nesw_path, 16, 16) rescue nil
        @cursor_move = ::UI.create_cursor(move_path, 16, 16) rescue nil
      end

      def activate
        view = Sketchup.active_model.active_view
        initialize_cursors
        reset_frame(view)
        update_status_text
        view.invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def suspend(view)
        view.invalidate if view
      end

      # Framing overlay is drawn in screen space; the model bounds keep the
      # overlay from being clipped.
      def getExtents
        Sketchup.active_model.bounds
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

        # Căn chỉnh tâm: nếu khung bằng hoặc lớn hơn màn hình thì căn chính giữa mép
        cx = if bw >= vw
               vw / 2.0
             else
               [[@center_x, half_w].max, vw - half_w].min
             end

        cy = if bh >= vh
               vh / 2.0
             else
               [[@center_y, half_h].max, vh - half_h].min
             end

        left = cx - half_w
        top = cy - half_h
        right = cx + half_w
        bottom = cy + half_h

        [left, top, right, bottom, bw, bh]
      end

      # Nhận diện vị trí chuột đối với khung cắt: :tl, :tr, :br, :bl, :inside, :outside
      def hit_test(x, y, view)
        left, top, right, bottom, _bw, _bh = current_box(view)
        hs = HANDLE_SIZE

        # Kiểm tra 4 góc trước (ưu tiên bắt góc để đổi cursor 2 đầu)
        return :resize_tl if (x - left).abs <= hs && (y - top).abs <= hs
        return :resize_tr if (x - right).abs <= hs && (y - top).abs <= hs
        return :resize_br if (x - right).abs <= hs && (y - bottom).abs <= hs
        return :resize_bl if (x - left).abs <= hs && (y - bottom).abs <= hs

        # Kiểm tra bên trong hộp
        if x >= left && x <= right && y >= top && y <= bottom
          :move
        else
          :outside
        end
      end

      def onSetCursor
        initialize_cursors unless @cursors_initialized
        active_hit = @drag_mode || @current_hit
        case active_hit
        when :resize_tl, :resize_br
          ::UI.set_cursor(@cursor_nwse) if @cursor_nwse
        when :resize_tr, :resize_bl
          ::UI.set_cursor(@cursor_nesw) if @cursor_nesw
        when :move
          ::UI.set_cursor(@cursor_move) if @cursor_move
        else
          ::UI.set_cursor(0)
        end
      end

      def onLButtonDown(flags, x, y, view)
        hit = hit_test(x, y, view)
        @drag_mode = hit
        @drag_start_x = x
        @drag_start_y = y
        @drag_orig_cx = @center_x || (view.vpwidth.to_f / 2.0)
        @drag_orig_cy = @center_y || (view.vpheight.to_f / 2.0)
        @drag_orig_scale = @scale

        if hit == :outside
          # Click ra ngoài -> dời tâm khung về vị trí click và bắt đầu drag
          @center_x = x.to_f
          @center_y = y.to_f
          @drag_orig_cx = @center_x
          @drag_orig_cy = @center_y
          @drag_mode = :move
          view.invalidate
        end
      end

      def onMouseMove(flags, x, y, view)
        if @drag_mode == :move
          dx = x - @drag_start_x
          dy = y - @drag_start_y
          @center_x = @drag_orig_cx + dx
          @center_y = @drag_orig_cy + dy
          view.invalidate
        elsif @drag_mode.to_s.start_with?('resize_')
          # Co giãn kích thước theo khoảng cách kéo chuột từ tâm
          cx = @drag_orig_cx
          cy = @drag_orig_cy
          dist_orig = Math.hypot(@drag_start_x - cx, @drag_start_y - cy)
          dist_curr = Math.hypot(x - cx, y - cy)
          if dist_orig > 5.0
            scale_factor = dist_curr / dist_orig
            @scale = [[@drag_orig_scale * scale_factor, 0.15].max, 1.0].min
            view.invalidate
          end
        else
          # Rê chuột tự do -> Cập nhật vị trí để đổi Cursor mũi tên 2 đầu
          prev_hit = @current_hit
          @current_hit = hit_test(x, y, view)
          view.invalidate if prev_hit != @current_hit
        end
      end

      def onLButtonUp(flags, x, y, view)
        @drag_mode = nil
        @current_hit = hit_test(x, y, view)
        view.invalidate
      end

      def onLButtonDoubleClick(flags, x, y, view)
        execute_capture(view)
      end

      def onMouseWheel(flags, delta, x, y, view)
        step = delta > 0 ? 0.05 : -0.05
        @scale = [[@scale + step, 0.15].max, 1.0].min
        view.invalidate
        true # Consume wheel event to prevent 3D camera zooming while framing
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
          @center_x = (@center_x || (view.vpwidth.to_f / 2.0)) - 15
          view.invalidate
        when 39 # Mũi tên Phải
          @center_x = (@center_x || (view.vpwidth.to_f / 2.0)) + 15
          view.invalidate
        when 38 # Mũi tên Lên
          @center_y = (@center_y || (view.vpheight.to_f / 2.0)) - 15
          view.invalidate
        when 40 # Mũi tên Xuống
          @center_y = (@center_y || (view.vpheight.to_f / 2.0)) + 15
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
        Sketchup.status_text = "NAUQ Snapshot: Tỉ lệ [#{asp[:name]}] • Độ phân giải [#{res[:name]}] • [Kéo chuột] Move / Co giãn góc • [Lăn chuột] Phóng to/Thu nhỏ • [Enter / Click đúp] Chụp & Copy Clipboard • [1-6] Đổi tỉ lệ • [R] Đổi độ phân giải"
      end

      # High-performance 2D Overlay Rendering (Zero-allocation loop for 60-120fps smoothness)
      def draw(view)
        vw = view.vpwidth.to_f
        vh = view.vpheight.to_f
        left, top, right, bottom, bw, bh = current_box(view)

        # 1. Viền tối mờ che ngoài khung chụp (Cinematic Matte Overlay)
        view.drawing_color = COLOR_MASK

        # Top bar
        if top > 0
          view.draw2d(GL_QUADS, [
            [0, 0, 0], [vw, 0, 0], [vw, top, 0], [0, top, 0]
          ])
        end

        # Bottom bar
        if bottom < vh
          view.draw2d(GL_QUADS, [
            [0, bottom, 0], [vw, bottom, 0], [vw, vh, 0], [0, vh, 0]
          ])
        end

        # Left bar
        if left > 0
          view.draw2d(GL_QUADS, [
            [0, top, 0], [left, top, 0], [left, bottom, 0], [0, bottom, 0]
          ])
        end

        # Right bar
        if right < vw
          view.draw2d(GL_QUADS, [
            [right, top, 0], [vw, top, 0], [vw, bottom, 0], [right, bottom, 0]
          ])
        end

        # 2. Đường lưới bố cục 1/3 (Rule of Thirds)
        third_w = bw / 3.0
        third_h = bh / 3.0
        view.drawing_color = COLOR_GRID
        view.line_width = 1

        # Lưới dọc + ngang gộp chung trong 1 lệnh draw2d
        view.draw2d(GL_LINES, [
          [left + third_w, top, 0], [left + third_w, bottom, 0],
          [left + 2 * third_w, top, 0], [left + 2 * third_w, bottom, 0],
          [left, top + third_h, 0], [right, top + third_h, 0],
          [left, top + 2 * third_h, 0], [right, top + 2 * third_h, 0]
        ])

        # 3. Viền khung cắt chính (Xanh lam công nghệ SketchUp)
        view.drawing_color = COLOR_FRAME
        view.line_width = 2
        view.draw2d(GL_LINE_LOOP, [
          [left, top, 0], [right, top, 0], [right, bottom, 0], [left, bottom, 0]
        ])

        # 4. Góc vuông nhấn (Corner Brackets trắng & Handles)
        bracket_len = [28.0, bw * 0.1].min
        view.drawing_color = COLOR_BRACKET
        view.line_width = 3
        view.draw2d(GL_LINES, [
          # Top-Left
          [left, top + bracket_len, 0], [left, top, 0],
          [left, top, 0], [left + bracket_len, top, 0],
          # Top-Right
          [right - bracket_len, top, 0], [right, top, 0],
          [right, top, 0], [right, top + bracket_len, 0],
          # Bottom-Right
          [right, bottom - bracket_len, 0], [right, bottom, 0],
          [right, bottom, 0], [right - bracket_len, bottom, 0],
          # Bottom-Left
          [left + bracket_len, bottom, 0], [left, bottom, 0],
          [left, bottom, 0], [left, bottom - bracket_len, 0]
        ])

        # 4 Nút vuông góc kéo co giãn (High-performance Corner Handles)
        hr = 4.0
        view.drawing_color = COLOR_HANDLE
        view.draw2d(GL_QUADS, [
          # TL
          [left - hr, top - hr, 0], [left + hr, top - hr, 0], [left + hr, top + hr, 0], [left - hr, top + hr, 0],
          # TR
          [right - hr, top - hr, 0], [right + hr, top - hr, 0], [right + hr, top + hr, 0], [right - hr, top + hr, 0],
          # BR
          [right - hr, bottom - hr, 0], [right + hr, bottom - hr, 0], [right + hr, bottom + hr, 0], [right - hr, bottom + hr, 0],
          # BL
          [left - hr, bottom - hr, 0], [left + hr, bottom - hr, 0], [left + hr, bottom + hr, 0], [left - hr, bottom + hr, 0]
        ])

        # 5. Dấu hồng tâm căn trung tâm (Center Crosshair)
        cx = left + bw / 2.0
        cy = top + bh / 2.0
        cross_s = 7.0
        view.drawing_color = COLOR_CROSS
        view.line_width = 1
        view.draw2d(GL_LINES, [
          [cx - cross_s, cy, 0], [cx + cross_s, cy, 0],
          [cx, cy - cross_s, 0], [cx, cy + cross_s, 0]
        ])
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
          ps_script = "Add-Type -AssemblyName System.Drawing,System.Windows.Forms; $src = [System.Drawing.Bitmap]::FromFile('#{raw_path.gsub("'", "''")}'); $rect = [System.Drawing.Rectangle]::new(#{crop_x}, #{crop_y}, #{crop_w}, #{crop_h}); $dest = $src.Clone($rect, $src.PixelFormat); $src.Dispose(); [System.Windows.Forms.Clipboard]::SetImage($dest); $dest.Dispose(); Remove-Item '#{raw_path.gsub("'", "''")}' -Force -ErrorAction SilentlyContinue;"
          ps_cmd = %Q(powershell -NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -Command "#{ps_script}")

          # Run non-blocking background process for instant 0.1s capture experience
          begin
            pid = Process.spawn(ps_cmd)
            Process.detach(pid)
          rescue StandardError
            system(ps_cmd)
          end
        end

        Sketchup.status_text = "✓ Đã chụp & lưu Clipboard thành công (#{crop_w}x#{crop_h}px, tỉ lệ #{ASPECT_RATIOS[@aspect_index][:name]}) — Bấm Ctrl+V để dán ảnh ngay!"
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
