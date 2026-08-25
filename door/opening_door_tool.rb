# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Interactive Tool to automatically detect wall openings or manually place 3D Doors & Windows via 2 Diagonal Opposite Corners (Toggle with Alt)
    # Positions door/window frame flush with exterior face of the opening.
    class OpeningDoorTool
      GEOMETRY_TOLERANCE = 0.001 unless const_defined?(:GEOMETRY_TOLERANCE)
      MIN_OPENING_WIDTH_MM = 300.0 unless const_defined?(:MIN_OPENING_WIDTH_MM)
      MAX_OPENING_WIDTH_MM = 6000.0 unless const_defined?(:MAX_OPENING_WIDTH_MM)
      FRAME_DEPTH = 80.0.mm unless const_defined?(:FRAME_DEPTH)

      ITEM_TYPES = %i[
        auto
        door_1
        door_2
        door_4
        door_sliding
        window_1
        window_2
        window_4
        window_sliding
        fix_glass
      ].freeze

      COLOR_HIGHLIGHT_FILL = Sketchup::Color.new(59, 130, 246, 45)
      COLOR_HIGHLIGHT_EDGE = Sketchup::Color.new(37, 99, 235, 255)
      COLOR_LINE           = Sketchup::Color.new(37, 99, 235, 220)

      def initialize
        @type_index = 0 # 0 = :auto
        @flipped = false
        @manual_mode = false # Toggle with Alt key

        @input_point = Sketchup::InputPoint.new
        @input_point_1 = nil
        @pt1 = nil
        @pt2 = nil
        @hover_opening = nil
        @current_manual_opening = nil
      end

      def activate
        update_status_text
        Sketchup.active_model.active_view.invalidate rescue nil
      end

      def resume(view)
        update_status_text
        view.invalidate rescue nil
      end

      def deactivate(view)
        @hover_opening = nil
        @current_manual_opening = nil
        @pt1 = nil
        @pt2 = nil
        view.invalidate rescue nil
      end

      def update_status_text
        type_name = current_type_label
        flip_str = @flipped ? ' [Mặt trong]' : ' [Mặt ngoài]'
        if @manual_mode
          if @pt1.nil?
            Sketchup.status_text = "[NAUQ VẼ CỬA THỦ CÔNG - #{type_name}#{flip_str}] Click Góc 1 (Chân cửa) | [Alt]: Tự Động | [TAB / Chuột phải]: Đổi kiểu | [Ctrl]: Đảo mặt"
          else
            Sketchup.status_text = "[NAUQ VẼ CỬA THỦ CÔNG - #{type_name}#{flip_str}] Click Góc 2 (Góc chéo đối diện) | [ESC]: Hủy điểm 1 | [Alt]: Tự Động | [TAB]: Đổi kiểu"
          end
        else
          Sketchup.status_text = "[NAUQ THÊM CỬA - #{type_name}#{flip_str}] Click vào hốc tường | [TAB / Chuột phải]: Đổi kiểu cửa | [Ctrl]: Đảo mặt | [Alt]: Vẽ Thủ Công"
        end
      end

      def current_type_label
        case ITEM_TYPES[@type_index]
        when :auto then 'Tự động (Auto)'
        when :door_1 then 'Cửa đi 1 cánh'
        when :door_2 then 'Cửa đi 2 cánh'
        when :door_4 then 'Cửa đi 4 cánh'
        when :door_sliding then 'Cửa đi lùa (trượt 2 cánh)'
        when :window_1 then 'Cửa sổ 1 cánh'
        when :window_2 then 'Cửa sổ 2 cánh'
        when :window_4 then 'Cửa sổ 4 cánh'
        when :window_sliding then 'Cửa sổ lùa (trượt 2 cánh)'
        when :fix_glass then 'Vách kính cố định'
        end
      end

      def onMouseMove(_flags, x, y, view)
        if @manual_mode
          @hover_opening = nil
          if @pt1.nil?
            @input_point.pick(view, x, y)
          else
            @input_point.pick(view, x, y, @input_point_1)
            @pt2 = @input_point.position
            update_manual_opening
          end
        else
          @input_point.pick(view, x, y)
          context = pick_context(@input_point, view, x, y)
          @hover_opening = context ? detect_opening_from_context(context) : nil
        end

        view.invalidate
      end

      def draw(view)
        # Draw active input point inference
        @input_point.draw(view) if @input_point&.valid?

        # Highlight detected opening cleanly
        if @hover_opening && !@manual_mode
          op = @hover_opening
          org = op[:origin]
          xv = op[:x_axis]
          yv = op[:y_axis]
          zv = op[:z_axis]
          w = op[:width_len]
          h = op[:height_len]
          d = FRAME_DEPTH

          p0 = org
          p1 = org.offset(xv, w)
          p2 = p1.offset(zv, h)
          p3 = p0.offset(zv, h)
          front_quad = [p0, p1, p2, p3]

          b0 = p0.offset(yv, d)
          b1 = p1.offset(yv, d)
          b2 = p2.offset(yv, d)
          b3 = p3.offset(yv, d)
          back_quad = [b0, b1, b2, b3]

          # Semi-transparent face fill
          view.drawing_color = COLOR_HIGHLIGHT_FILL
          view.draw(GL_QUADS, front_quad)
          view.draw(GL_QUADS, back_quad)

          # Crisp wireframe outlines
          view.drawing_color = COLOR_HIGHLIGHT_EDGE
          view.line_width = 3
          view.draw(GL_LINE_LOOP, front_quad)
          view.draw(GL_LINE_LOOP, back_quad)
          view.draw(GL_LINES, [p0, b0, p1, b1, p2, b2, p3, b3])
        end

        # Draw manual mode 2-point drag line if in manual mode
        if @manual_mode && @pt1
          view.draw_points([@pt1], 8, 1, COLOR_LINE)
          if @pt2
            view.drawing_color = COLOR_LINE
            view.line_width = 2
            view.draw(GL_LINES, [@pt1, @pt2])
          end
        end
      end

      # Right-Click Context Menu for instant style selection
      def getMenu(menu, _flags, x, y, view)
        menu.add_item('Đặt Cửa Tại Đây (Click)') do
          if @manual_mode && @pt1 && @pt2
            handle_manual_click(view, x, y)
          else
            handle_auto_click(view, x, y)
          end
        end
        menu.add_separator

        style_sub = menu.add_submenu('Kiểu Cửa (Door & Window Style)')
        ITEM_TYPES.each_with_index do |type, idx|
          label = case type
                  when :auto then 'Tự động (Auto nhận diện)'
                  when :door_1 then 'Cửa đi 1 cánh mở quay'
                  when :door_2 then 'Cửa đi 2 cánh mở quay'
                  when :door_4 then 'Cửa đi 4 cánh mở quay'
                  when :door_sliding then 'Cửa đi lùa (trượt 2 cánh)'
                  when :window_1 then 'Cửa sổ 1 cánh mở quay'
                  when :window_2 then 'Cửa sổ 2 cánh mở quay'
                  when :window_4 then 'Cửa sổ 4 cánh mở quay'
                  when :window_sliding then 'Cửa sổ lùa (trượt 2 cánh)'
                  when :fix_glass then 'Vách kính cố định'
                  end
          item = style_sub.add_item(label) do
            @type_index = idx
            update_status_text
            update_manual_opening if @manual_mode && @pt1 && @pt2
            view.invalidate
          end
          style_sub.set_validation_proc(item) { idx == @type_index ? MF_CHECKED : MF_UNCHECKED }
        end

        menu.add_item('Đảo mặt trong / ngoài (Ctrl)') do
          @flipped = !@flipped
          update_status_text
          update_manual_opening if @manual_mode && @pt1 && @pt2
          view.invalidate
        end

        mode_label = @manual_mode ? 'Chuyển sang: Tự Động Hốc Tường (Alt)' : 'Chuyển sang: Vẽ Thủ Công 2 Góc Chéo (Alt)'
        menu.add_item(mode_label) do
          @manual_mode = !@manual_mode
          @pt1 = nil
          @pt2 = nil
          @input_point_1 = nil
          @current_manual_opening = nil
          update_status_text
          view.invalidate
        end

        menu.add_separator
        menu.add_item('Thoát công cụ (Esc)') do
          Sketchup.active_model.select_tool(nil)
        end
      end

      def onLButtonDown(_flags, x, y, view)
        if @manual_mode
          handle_manual_click(view, x, y)
        else
          handle_auto_click(view, x, y)
        end
      end

      def onKeyDown(key, _repeat, _flags, view)
        if key == 18 # VK_ALT / VK_MENU: Toggle manual 2-corner mode
          @manual_mode = !@manual_mode
          @pt1 = nil
          @pt2 = nil
          @input_point_1 = nil
          @current_manual_opening = nil
          update_status_text
          view.invalidate
          return true
        elsif key == 9 # VK_TAB: Cycle types
          @type_index = (@type_index + 1) % ITEM_TYPES.size
          update_status_text
          update_manual_opening if @manual_mode && @pt1 && @pt2
          view.invalidate
          return true
        elsif key == 17 # VK_CONTROL: Toggle flip orientation
          @flipped = !@flipped
          update_status_text
          update_manual_opening if @manual_mode && @pt1 && @pt2
          view.invalidate
          return true
        elsif key == 27 # VK_ESCAPE: Cancel pending manual point
          if @manual_mode && @pt1
            @pt1 = nil
            @pt2 = nil
            @input_point_1 = nil
            @current_manual_opening = nil
            update_status_text
            view.invalidate
            return true
          end
        end
        false
      end

      private

      def handle_manual_click(view, x, y)
        if @pt1.nil?
          @input_point.pick(view, x, y)
          if @input_point.valid?
            @pt1 = @input_point.position
            @input_point_1 = @input_point.clone
            update_status_text
            view.invalidate
          end
        else
          @input_point.pick(view, x, y, @input_point_1)
          @pt2 = @input_point.position

          horiz_dist = Geom::Vector3d.new(@pt2.x - @pt1.x, @pt2.y - @pt1.y, 0).length
          if horiz_dist < 100.0.mm
            ::UI.messagebox('Bề rộng cửa quá nhỏ (tối thiểu 100mm). Vui lòng click chọn lại Góc chéo thứ 2.')
            return
          end

          update_manual_opening
          if @current_manual_opening
            model = Sketchup.active_model
            is_win = decide_is_window(@current_manual_opening)
            op_label = is_win ? 'Cửa Sổ' : 'Cửa Đi'
            model.start_operation("NAUQ Vẽ Thủ Công #{op_label}", true)

            begin
              assembly = build_item_for_opening(@current_manual_opening)
              if assembly && assembly.valid?
                model.commit_operation
                Logger.info("Đã vẽ thủ công #{op_label} thành công (Rộng: #{@current_manual_opening[:width_mm].round(0)}mm, Cao: #{@current_manual_opening[:height_mm].round(0)}mm).") if defined?(Logger)
              else
                model.abort_operation
                ::UI.messagebox("Không thể tạo hình học #{op_label}.")
              end
            rescue StandardError => e
              model.abort_operation
              ::UI.messagebox("Lỗi khi vẽ thủ công #{op_label}: #{e.message}")
            end
          end

          # Reset for next placement
          @pt1 = nil
          @pt2 = nil
          @input_point_1 = nil
          @current_manual_opening = nil
          update_status_text
          view.invalidate
        end
      end

      def handle_auto_click(view, x, y)
        @input_point.pick(view, x, y)
        context = pick_context(@input_point, view, x, y)
        unless context
          ::UI.messagebox("Vui lòng click vào mặt phẳng cạnh hốc cửa (mặt tường đứng tại vị trí mở cửa).\n\nGợi ý: Bạn có thể bấm phím [Alt] để chuyển sang chế độ Vẽ Thủ Công 2 Góc Chéo.")
          return
        end

        opening = detect_opening_from_context(context)
        unless opening
          ::UI.messagebox("Không nhận diện được khoảng trống đối diện của hốc cửa.\n\nGợi ý: Bấm [Alt] để vẽ cửa thủ công bằng cách click 2 góc chéo.")
          return
        end

        model = Sketchup.active_model
        is_win = decide_is_window(opening)
        op_label = is_win ? 'Cửa Sổ' : 'Cửa Đi'
        model.start_operation("NAUQ Thêm #{op_label} vào Opening", true)

        begin
          assembly = build_item_for_opening(opening)
          if assembly && assembly.valid?
            model.commit_operation
            Logger.info("Đã thêm thành công #{op_label} vào opening (#{opening[:width_mm].round(0)}x#{opening[:height_mm].round(0)}mm).") if defined?(Logger)
          else
            model.abort_operation
            ::UI.messagebox("Không thể tạo hình học #{op_label}.")
          end
        rescue StandardError => e
          model.abort_operation
          ::UI.messagebox("Lỗi khi thêm #{op_label}: #{e.message}")
        end

        view.invalidate
      end

      def update_manual_opening
        return unless @pt1 && @pt2

        # 1. Horizontal vector and width
        horiz_vec = Geom::Vector3d.new(@pt2.x - @pt1.x, @pt2.y - @pt1.y, 0)
        w = horiz_vec.length
        return if w < 10.0.mm

        x_axis = horiz_vec.normalize
        z_axis = Geom::Vector3d.new(0, 0, 1)
        y_axis = z_axis * x_axis
        y_axis.reverse! if @flipped

        # 2. Vertical height from 2 diagonal opposite corners
        z_min = [@pt1.z, @pt2.z].min
        z_max = [@pt1.z, @pt2.z].max
        delta_z = z_max - z_min

        is_win = decide_is_window_manual(z_min)

        if delta_z >= 100.0.mm
          h_val = delta_z
          h_mm = h_val.to_mm
        else
          h_mm = is_win ? (Config.get(:window_height) || 1200.0).to_f : (Config.get(:door_height) || 2200.0).to_f
          h_val = h_mm.mm
        end

        # 3. Origin anchored at the lower base position
        origin = Geom::Point3d.new(@pt1.x, @pt1.y, z_min)
        glass_h = (Config.get(:glass_height) || 350.0).to_f
        has_transom = glass_h > 0 && (h_mm > 2400.0)

        @current_manual_opening = {
          origin: origin,
          x_axis: x_axis,
          y_axis: y_axis,
          z_axis: z_axis,
          width_len: w,
          height_len: h_val,
          width_mm: w.to_mm,
          height_mm: h_mm,
          has_transom: has_transom,
          glass_height_mm: glass_h,
          has_bottom_fix: is_win && h_mm > 1600.0,
          fix_bottom_height_mm: is_win && h_mm > 1600.0 ? 400.0 : 0.0,
          is_window_auto: is_win
        }
      end

      def decide_is_window_manual(z_min = 0.0)
        selected_type = ITEM_TYPES[@type_index]
        case selected_type
        when :window_1, :window_2, :window_4, :window_sliding then true
        when :door_1, :door_2, :door_4, :door_sliding, :fix_glass then false
        else
          # Auto: If starting above 500mm off ground, recognize as window
          z_min > 500.0.mm
        end
      end

      public

      # Batch create doors from selected faces
      def create_from_selected_faces(faces)
        model = Sketchup.active_model
        count = 0
        model.start_operation('NAUQ Thêm Cửa từ Selection', true)

        faces.each do |face|
          next unless face.valid? && face.normal.z.abs <= 0.2
          ctx = { face: face, transformation: Geom::Transformation.new, instance_path: nil }
          opening = detect_opening_from_context(ctx)
          next unless opening

          item = build_item_for_opening(opening)
          count += 1 if item && item.valid?
        end

        if count > 0
          model.commit_operation
          Logger.info("Đã tạo thành công #{count} bộ cửa từ các mặt phẳng đã chọn.") if defined?(Logger)
          ::UI.messagebox("Đã tự động tạo #{count} bộ cửa từ các mặt phẳng được chọn!")
        else
          model.abort_operation
          ::UI.messagebox('Không tìm thấy hốc cửa hợp lệ trong các mặt phẳng đang chọn.')
        end
      end

      private

      # Traverses input point context to find valid vertical opening face
      def pick_context(ip, view, x, y)
        # 1. Try ip.instance_path (Most accurate in SketchUp)
        if ip.respond_to?(:instance_path) && ip.instance_path && !ip.instance_path.empty?
          leaf = ip.instance_path.to_a.last
          if leaf.is_a?(Sketchup::Face)
            tr = ip.instance_path.transformation
            return { face: leaf, transformation: tr, instance_path: ip.instance_path.to_a } if valid_vertical_face?(leaf, tr)
          end
        end

        # 2. Try raw ip.face
        if ip.face && ip.face.is_a?(Sketchup::Face)
          tr = Geom::Transformation.new
          return { face: ip.face, transformation: tr, instance_path: nil } if valid_vertical_face?(ip.face, tr)
        end

        # 3. Raytest backup from camera pickray
        ray = view.pickray(x, y)
        hit = Sketchup.active_model.raytest(ray)
        if hit
          hit_point, path = hit
          leaf = path.last
          if leaf.is_a?(Sketchup::Face)
            tr = Geom::Transformation.new
            path.each { |ent| tr *= ent.transformation if ent.respond_to?(:transformation) }
            return { face: leaf, transformation: tr, instance_path: path } if valid_vertical_face?(leaf, tr)
          end
        end

        nil
      end

      def valid_vertical_face?(face, tr = nil)
        return false unless face && face.is_a?(Sketchup::Face) && face.valid?
        normal = face.normal
        normal = (tr * normal).normalize if tr
        normal.z.abs <= 0.35 # Must be vertical wall face
      end

      # Raycasts from the source face along its normal to locate the opposite parallel opening face
      def detect_opening_from_context(context)
        face = context[:face]
        tr = context[:transformation] || Geom::Transformation.new

        source_normal = (tr * face.normal).normalize
        source_normal = Geom::Vector3d.new(source_normal.x, source_normal.y, 0).normalize
        return nil if source_normal.length < 0.001

        model = Sketchup.active_model
        all_faces = find_candidate_faces(model.active_entities)

        best_target = nil
        min_distance = Float::INFINITY
        best_overlap = nil

        center_pt = tr * face.bounds.center
        ray = [center_pt.offset(source_normal, 2.0.mm), source_normal]
        hit = model.raytest(ray)

        if hit
          hit_pt, hit_path = hit
          hit_face = hit_path.last if hit_path
          if hit_face.is_a?(Sketchup::Face)
            hit_tr = Geom::Transformation.new
            hit_path.each { |ent| hit_tr *= ent.transformation if ent.respond_to?(:transformation) }
            hit_normal = (hit_tr * hit_face.normal).normalize
            hit_normal = Geom::Vector3d.new(hit_normal.x, hit_normal.y, 0).normalize

            dot = source_normal.dot(hit_normal)
            if dot < -0.85 # Opposite parallel face
              dist = center_pt.distance(hit_pt)
              if dist >= MIN_OPENING_WIDTH_MM.mm && dist <= MAX_OPENING_WIDTH_MM.mm
                overlap = calculate_face_overlap(face, tr, hit_face, hit_tr, source_normal)
                if overlap && overlap[:length] >= 20.0.mm
                  best_target = { face: hit_face, transformation: hit_tr }
                  min_distance = dist
                  best_overlap = overlap
                end
              end
            end
          end
        end

        # Exhaustive search across candidate faces if raycast misses
        unless best_target
          all_faces.each do |candidate|
            next if candidate[:face] == face

            c_norm = (candidate[:transformation] * candidate[:face].normal).normalize
            c_norm = Geom::Vector3d.new(c_norm.x, c_norm.y, 0).normalize
            next if c_norm.length < 0.001

            dot = source_normal.dot(c_norm)
            next unless dot < -0.85 # Opposite parallel face

            c_center = candidate[:transformation] * candidate[:face].bounds.center
            vec = c_center - center_pt
            dist = vec.dot(source_normal)
            next unless dist >= MIN_OPENING_WIDTH_MM.mm && dist <= MAX_OPENING_WIDTH_MM.mm

            overlap = calculate_face_overlap(face, tr, candidate[:face], candidate[:transformation], source_normal)
            next unless overlap && overlap[:length] >= 20.0.mm

            if dist < min_distance
              min_distance = dist
              best_target = candidate
              best_overlap = overlap
            end
          end
        end

        return nil unless best_target && best_overlap

        construct_opening_definition(face, tr, best_target[:face], best_target[:transformation], source_normal, min_distance, best_overlap)
      end

      def find_candidate_faces(container)
        faces = []
        entities = container.respond_to?(:entities) ? container.entities : container
        entities.grep(Sketchup::Face).each do |f|
          faces << { face: f, transformation: Geom::Transformation.new } if valid_vertical_face?(f)
        end

        entities.grep(Sketchup::Group).each do |g|
          next unless g.valid?
          g_tr = g.transformation
          g.entities.grep(Sketchup::Face).each do |f|
            faces << { face: f, transformation: g_tr } if valid_vertical_face?(f)
          end
        end

        entities.grep(Sketchup::ComponentInstance).each do |ci|
          next unless ci.valid?
          ci_tr = ci.transformation
          ci.definition.entities.grep(Sketchup::Face).each do |f|
            faces << { face: f, transformation: ci_tr } if valid_vertical_face?(f)
          end
        end

        faces
      end

      # Construct exact 3D coordinate system for door alignment (perfectly flush with exterior face)
      def construct_opening_definition(f_src, tr_src, f_tgt, tr_tgt, forward_normal, width, overlap)
        src_bb = f_src.bounds
        src_pts = [src_bb.min, src_bb.max].map { |p| tr_src * p }
        z_min = [src_pts[0].z, src_pts[1].z].min
        z_max = [src_pts[0].z, src_pts[1].z].max

        tgt_bb = f_tgt.bounds
        tgt_pts = [tgt_bb.min, tgt_bb.max].map { |p| tr_tgt * p }
        z_min = [z_min, tgt_pts[0].z, tgt_pts[1].z].min
        z_max = [z_max, tgt_pts[0].z, tgt_pts[1].z].max
        height = [z_max - z_min, 1000.0.mm].max

        # Lateral vector (across the wall thickness)
        up_vec = Geom::Vector3d.new(0, 0, 1)
        lateral_vec = (up_vec * forward_normal).normalize

        # Center of source jamb face
        center_src = tr_src * f_src.bounds.center
        center_src_proj = center_src.to_a.zip(lateral_vec.to_a).map { |a, b| a * b }.sum

        # Align exterior face of door frame flush with exterior edge of opening (extends inwards)
        if @flipped
          # Flush with opposite wall face and extends inward
          delta_lateral = overlap[:min] - center_src_proj
          origin = center_src.clone
          origin.z = z_min
          origin = origin.offset(lateral_vec, delta_lateral)

          x_axis = forward_normal.normalize
          y_axis = lateral_vec.normalize
          z_axis = up_vec
        else
          # Flush with outer (exterior) wall face and extends inward
          delta_lateral = overlap[:max] - center_src_proj
          origin = center_src.clone
          origin.z = z_min
          origin = origin.offset(lateral_vec, delta_lateral)

          x_axis = forward_normal.normalize
          y_axis = lateral_vec.reverse.normalize
          z_axis = up_vec
        end

        is_window_auto = z_min > 500.0.mm # Higher off ground is recognized as window

        glass_h = (Config.get(:glass_height) || 350.0).to_f
        has_transom = glass_h > 0 && (height.to_mm > 2400.0)

        {
          origin: origin,
          x_axis: x_axis,
          y_axis: y_axis,
          z_axis: z_axis,
          width_len: width,
          height_len: height,
          width_mm: width.to_mm,
          height_mm: height.to_mm,
          is_window_auto: is_window_auto,
          has_transom: has_transom,
          glass_height_mm: glass_h,
          has_bottom_fix: false,
          fix_bottom_height_mm: 0.0
        }
      end

      def calculate_face_overlap(f_src, tr_src, f_tgt, tr_tgt, normal)
        up = Geom::Vector3d.new(0, 0, 1)
        lateral = (up * normal).normalize

        src_pts = f_src.vertices.map { |v| tr_src * v.position }
        tgt_pts = f_tgt.vertices.map { |v| tr_tgt * v.position }

        src_proj = src_pts.map { |p| p.to_a.zip(lateral.to_a).map { |a, b| a * b }.sum }
        tgt_proj = tgt_pts.map { |p| p.to_a.zip(lateral.to_a).map { |a, b| a * b }.sum }

        src_min = src_proj.min
        src_max = src_proj.max
        tgt_min = tgt_proj.min
        tgt_max = tgt_proj.max

        overlap_min = [src_min, tgt_min].max
        overlap_max = [src_max, tgt_max].min

        return nil if overlap_max - overlap_min < 20.0.mm

        {
          min: overlap_min,
          max: overlap_max,
          mid_proj: (overlap_min + overlap_max) * 0.5,
          length: overlap_max - overlap_min
        }
      end

      def decide_is_window(op)
        selected_type = ITEM_TYPES[@type_index]
        case selected_type
        when :window_1, :window_2, :window_4, :window_sliding then true
        when :door_1, :door_2, :door_4, :door_sliding, :fix_glass then false
        else
          op[:is_window_auto]
        end
      end

      def resolve_panel_count(op)
        selected_type = ITEM_TYPES[@type_index]
        case selected_type
        when :door_1, :window_1, :fix_glass then 1
        when :door_2, :window_2, :door_sliding, :window_sliding then 2
        when :door_4, :window_4 then 4
        else # :auto
          w = op[:width_mm]
          if op[:is_window_auto]
            w > 1800.0 ? 4 : 2
          else
            if w <= 1150.0
              1
            elsif w <= 2200.0
              2
            else
              4
            end
          end
        end
      end

      def build_item_for_opening(op)
        model = Sketchup.active_model
        w_mm = op[:width_mm]
        h_mm = op[:height_mm]
        is_win = decide_is_window(op)
        panel_count = resolve_panel_count(op)

        selected_type = ITEM_TYPES[@type_index]
        is_sliding = selected_type.to_s.include?('sliding')

        assembly = if is_win
                     # Build WINDOW directly as an independent assembly
                     WindowBuilder.generate(
                       parent: model.active_entities,
                       name: "WINDOW_#{panel_count}P_#{w_mm.round(0)}x#{h_mm.round(0)}",
                       width: w_mm.mm,
                       height: h_mm.mm,
                       panel_count: panel_count,
                       is_sliding: is_sliding,
                       has_fix_top: op[:has_transom],
                       fix_top_height: op[:glass_height_mm].to_f.mm,
                       has_fix_bottom: op[:has_bottom_fix],
                       fix_bottom_height: op[:fix_bottom_height_mm].to_f.mm
                     )
                   else
                     # Build DOOR directly as an independent assembly
                     DoorGenerator.generate(
                       parent: model.active_entities,
                       name: "DOOR_#{panel_count}P_#{w_mm.round(0)}x#{h_mm.round(0)}",
                       width: w_mm.mm,
                       height: h_mm.mm,
                       panel_count: panel_count,
                       is_sliding: is_sliding,
                       has_fix_top: op[:has_transom],
                       fix_module_height: op[:glass_height_mm].to_f.mm
                     )
                   end

        return nil unless assembly && assembly.valid?

        # Align and position into the opening
        tr_align = Geom::Transformation.axes(
          op[:origin],
          op[:x_axis],
          op[:y_axis],
          op[:z_axis]
        )
        assembly.transform!(tr_align)

        # Tag with NAUQ metadata for resizing & report
        Attribute.tag(
          assembly,
          is_win ? 'window' : 'door',
          width: w_mm,
          height: h_mm,
          panel_count: panel_count,
          type: is_win ? 'window' : 'door'
        )

        assembly
      end

      def entities_for_face(face)
        return nil unless face
        parent = face.parent
        return parent if parent.respond_to?(:add_face)
        return parent.entities if parent.respond_to?(:entities)
        nil
      end
    end
  end
end
