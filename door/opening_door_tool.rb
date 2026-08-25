# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Interactive Tool to automatically detect wall openings or manually place 3D Doors & Windows via 2 Diagonal Opposite Corners (Toggle with Alt)
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

      def initialize
        @type_index = 0 # 0 = :auto
        @flipped = false
        @manual_mode = false # Toggle with Alt key

        @input_point = Sketchup::InputPoint.new
        @input_point_1 = nil
        @pt1 = nil
        @pt2 = nil

        @current_opening = nil
        @current_manual_opening = nil
        @preview_bbox = nil
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
        @preview_bbox = nil
        @current_opening = nil
        @current_manual_opening = nil
        @pt1 = nil
        @pt2 = nil
        view.invalidate rescue nil
      end

      def update_status_text
        type_name = current_type_label
        flip_str = @flipped ? ' [Đảo mặt: BẬT]' : ''
        if @manual_mode
          if @pt1.nil?
            Sketchup.status_text = "[NAUQ VẼ CỬA THỦ CÔNG (2 GÓC CHÉO) - #{type_name}#{flip_str}] Click Góc 1 (Chân cửa) | [Alt]: Chuyển sang Tự Động | [TAB]: Đổi kiểu | [Ctrl]: Đảo chiều"
          else
            Sketchup.status_text = "[NAUQ VẼ CỬA THỦ CÔNG (2 GÓC CHÉO) - #{type_name}#{flip_str}] Click Góc 2 (Góc chéo đối diện) | [ESC]: Hủy điểm 1 | [Alt]: Chuyển Tự Động | [TAB]: Đổi kiểu"
          end
        else
          Sketchup.status_text = "[NAUQ THÊM CỬA TỰ ĐỘNG - #{type_name}#{flip_str}] Rê chuột & Click vào hốc tường | [Alt]: Chuyển sang Vẽ Thủ Công (2 Góc Chéo) | [TAB]: Đổi kiểu | [Ctrl]: Đảo chiều"
        end
      end

      def current_type_label
        case ITEM_TYPES[@type_index]
        when :auto then 'Tự động (Auto)'
        when :door_1 then 'Cửa đi 1 cánh'
        when :door_2 then 'Cửa đi 2 cánh'
        when :door_4 then 'Cửa đi 4 cánh'
        when :door_sliding then 'Cửa đi lùa (trượt)'
        when :window_1 then 'Cửa sổ 1 cánh'
        when :window_2 then 'Cửa sổ 2 cánh'
        when :window_4 then 'Cửa sổ 4 cánh'
        when :window_sliding then 'Cửa sổ lùa (trượt)'
        when :fix_glass then 'Vách kính cố định'
        end
      end

      def onMouseMove(_flags, x, y, view)
        if @manual_mode
          if @pt1.nil?
            @input_point.pick(view, x, y)
            @preview_bbox = nil
          else
            @input_point.pick(view, x, y, @input_point_1)
            @pt2 = @input_point.position
            update_manual_preview
          end
        else
          @input_point.pick(view, x, y)
          context = pick_context(@input_point, view, x, y)

          @current_opening = nil
          @preview_bbox = nil

          if context
            opening = detect_opening_from_context(context)
            if opening
              @current_opening = opening
              @preview_bbox = calculate_preview_geometry(opening)
            end
          end
        end

        view.invalidate
      rescue StandardError => e
        @current_opening = nil
        @current_manual_opening = nil
        @preview_bbox = nil
        view.invalidate
      end

      def draw(view)
        # Draw active input point inference
        @input_point.draw(view) if @input_point&.valid?

        # Draw manual mode indicators
        if @manual_mode
          if @pt1
            view.draw_points([@pt1], 10, 1, Sketchup::Color.new(37, 99, 235)) # Blue start corner
            if @pt2
              view.drawing_color = Sketchup::Color.new(37, 99, 235, 200)
              view.line_width = 2
              view.draw(GL_LINES, [@pt1, @pt2])

              w_mm = (@current_manual_opening ? @current_manual_opening[:width_mm] : @pt1.distance(@pt2).to_mm).round(0)
              h_mm = (@current_manual_opening ? @current_manual_opening[:height_mm] : 2200.0).round(0)
              mid_pt = Geom::Point3d.new((@pt1.x + @pt2.x) * 0.5, (@pt1.y + @pt2.y) * 0.5, ([@pt1.z, @pt2.z].max) + 60.mm)
              view.draw_text(mid_pt, "Rộng: #{w_mm} mm x Cao: #{h_mm} mm", color: Sketchup::Color.new(30, 41, 59))
            end
          end
        end

        return unless @preview_bbox && @preview_bbox[:corners]

        corners = @preview_bbox[:corners]
        is_win = @preview_bbox[:is_window]

        # Colors: Blue for Door, Emerald/Teal for Window
        fill_color = if is_win
                       Sketchup::Color.new(16, 185, 129, 85)
                     else
                       Sketchup::Color.new(59, 130, 246, 85)
                     end

        edge_color = if is_win
                       Sketchup::Color.new(5, 150, 105, 255)
                     else
                       Sketchup::Color.new(37, 99, 235, 255)
                     end

        # Draw semi-transparent bounding faces
        faces_indices = [
          [0, 1, 2, 3], # Bottom
          [4, 5, 6, 7], # Top
          [0, 1, 5, 4], # Front
          [1, 2, 6, 5], # Right
          [2, 3, 7, 6], # Back
          [3, 0, 4, 7]  # Left
        ]

        view.drawing_color = fill_color
        faces_indices.each do |quad|
          pts = quad.map { |i| corners[i] }
          view.draw(GL_QUADS, pts)
        end

        # Draw crisp outline edges
        view.drawing_color = edge_color
        view.line_width = 2
        edges_indices = [
          [0, 1], [1, 2], [2, 3], [3, 0],
          [4, 5], [5, 6], [6, 7], [7, 4],
          [0, 4], [1, 5], [2, 6], [3, 7]
        ]
        edges_indices.each do |e|
          view.draw(GL_LINES, [corners[e[0]], corners[e[1]]])
        end

        # Draw center icon / panel division lines
        if @preview_bbox[:division_lines]
          view.drawing_color = Sketchup::Color.new(245, 158, 11, 255)
          view.line_width = 2
          @preview_bbox[:division_lines].each do |line|
            view.draw(GL_LINES, line)
          end
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
          @current_opening = nil
          @preview_bbox = nil
          update_status_text
          view.invalidate
          return true
        elsif key == 9 # VK_TAB: Cycle types
          @type_index = (@type_index + 1) % ITEM_TYPES.size
          update_status_text
          if @manual_mode && @pt1 && @pt2
            update_manual_preview
          elsif @current_opening
            @preview_bbox = calculate_preview_geometry(@current_opening)
          end
          view.invalidate
          return true
        elsif key == 17 # VK_CONTROL: Toggle flip orientation
          @flipped = !@flipped
          update_status_text
          if @manual_mode && @pt1 && @pt2
            update_manual_preview
          elsif @current_opening
            @preview_bbox = calculate_preview_geometry(@current_opening)
          end
          view.invalidate
          return true
        elsif key == 27 # VK_ESCAPE: Cancel pending manual point
          if @manual_mode && @pt1
            @pt1 = nil
            @pt2 = nil
            @input_point_1 = nil
            @current_manual_opening = nil
            @preview_bbox = nil
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
            UI.messagebox('Bề rộng cửa quá nhỏ (tối thiểu 100mm). Vui lòng click chọn lại Góc chéo thứ 2.')
            return
          end

          update_manual_preview
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
                UI.messagebox("Không thể tạo hình học #{op_label}.")
              end
            rescue StandardError => e
              model.abort_operation
              UI.messagebox("Lỗi khi vẽ thủ công #{op_label}: #{e.message}")
            end
          end

          # Reset for next placement
          @pt1 = nil
          @pt2 = nil
          @input_point_1 = nil
          @current_manual_opening = nil
          @preview_bbox = nil
          update_status_text
          view.invalidate
        end
      end

      def handle_auto_click(view, x, y)
        @input_point.pick(view, x, y)
        context = pick_context(@input_point, view, x, y)
        unless context
          UI.messagebox("Vui lòng click vào mặt phẳng cạnh hốc cửa (mặt tường đứng tại vị trí mở cửa).\n\nGợi ý: Bạn có thể bấm phím [Alt] để chuyển sang chế độ Vẽ Thủ Công 2 Góc Chéo.")
          return
        end

        opening = detect_opening_from_context(context)
        unless opening
          UI.messagebox("Không nhận diện được khoảng trống đối diện của hốc cửa.\n\nGợi ý: Bấm [Alt] để vẽ cửa thủ công bằng cách click 2 góc chéo.")
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
            UI.messagebox("Không thể tạo hình học #{op_label}.")
          end
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Lỗi khi thêm #{op_label}: #{e.message}")
        end

        view.invalidate
      end

      def update_manual_preview
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

        op = {
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
        @current_manual_opening = op
        @preview_bbox = calculate_preview_geometry(op)
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
          UI.messagebox("Đã tự động tạo #{count} bộ cửa từ các mặt phẳng được chọn!")
        else
          model.abort_operation
          UI.messagebox('Không tìm thấy hốc cửa hợp lệ trong các mặt phẳng đang chọn.')
        end
      end

      private

      # Traverses input point context to find valid vertical opening face
      def pick_context(ip, view, x, y)
        face = ip.face
        return { face: face, transformation: ip.transformation, instance_path: ip.instance_path } if valid_vertical_face?(face)

        # Raytest backup if hovering inside component or edge
        ray = view.pickray(x, y)
        hit = Sketchup.active_model.raytest(ray)
        if hit
          hit_point, path = hit
          leaf = path.last
          if leaf.is_a?(Sketchup::Face) && valid_vertical_face?(leaf)
            tr = Geom::Transformation.new
            path.each { |ent| tr *= ent.transformation if ent.respond_to?(:transformation) }
            return { face: leaf, transformation: tr, instance_path: path }
          end
        end

        nil
      end

      def valid_vertical_face?(face)
        return false unless face && face.valid?
        normal = face.normal
        normal.z.abs <= 0.2 # Must be vertical wall face
      end

      # Raycasts from the source face along its normal to locate the opposite parallel opening face
      def detect_opening_from_context(context)
        face = context[:face]
        tr = context[:transformation] || Geom::Transformation.new

        source_normal = (tr * face.normal).normalize
        source_normal = Geom::Vector3d.new(source_normal.x, source_normal.y, 0).normalize
        return nil if source_normal.length < 0.001

        model = Sketchup.active_model
        container = context[:instance_path] ? context[:instance_path].first : model.active_entities
        all_faces = find_candidate_faces(container)

        best_target = nil
        min_distance = Float::INFINITY
        best_overlap = nil

        center_pt = tr * face.bounds.center
        ray = [center_pt, source_normal]
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
            if dot < -0.9 # Opposite parallel face
              dist = center_pt.distance(hit_pt)
              if dist >= MIN_OPENING_WIDTH_MM.mm && dist <= MAX_OPENING_WIDTH_MM.mm
                overlap = calculate_face_overlap(face, tr, hit_face, hit_tr, source_normal)
                if overlap && overlap[:length] >= 50.0.mm
                  best_target = { face: hit_face, transformation: hit_tr }
                  min_distance = dist
                  best_overlap = overlap
                end
              end
            end
          end
        end

        # Exhaustive search if raycast misses
        unless best_target
          all_faces.each do |candidate|
            next if candidate[:face] == face

            c_norm = (candidate[:transformation] * candidate[:face].normal).normalize
            c_norm = Geom::Vector3d.new(c_norm.x, c_norm.y, 0).normalize
            next if c_norm.length < 0.001

            dot = source_normal.dot(c_norm)
            next unless dot < -0.9 # Opposite parallel face

            c_center = candidate[:transformation] * candidate[:face].bounds.center
            vec = c_center - center_pt
            dist = vec.dot(source_normal)
            next unless dist >= MIN_OPENING_WIDTH_MM.mm && dist <= MAX_OPENING_WIDTH_MM.mm

            overlap = calculate_face_overlap(face, tr, candidate[:face], candidate[:transformation], source_normal)
            next unless overlap && overlap[:length] >= 50.0.mm

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

      # Construct exact 3D coordinate system for door alignment
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
        lateral_vec = up_vec * forward_normal

        center_src = tr_src * f_src.bounds.center
        center_tgt = tr_tgt * f_tgt.bounds.center
        mid_x = (center_src.x + center_tgt.x) * 0.5
        mid_y = (center_src.y + center_tgt.y) * 0.5

        # Lateral midpoint positioning
        frame_d = FRAME_DEPTH
        half_frame = frame_d * 0.5
        mid_lat = overlap[:midpoint]

        # Origin positioned at corner so that frame centered across wall thickness
        origin = center_src.clone
        origin.z = z_min
        origin = origin.offset(lateral_vec, mid_lat - (overlap[:start]))
        origin = origin.offset(lateral_vec.reverse, half_frame)

        # Coordinate axes:
        # X: along forward_normal (width of opening from Left jamb to Right jamb)
        # Y: along lateral_vec (depth of frame into the wall)
        # Z: along up_vec (height of opening)
        x_axis = forward_normal.normalize
        y_axis = lateral_vec.normalize
        z_axis = up_vec

        y_axis.reverse! if @flipped

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
          has_bottom_fix: is_window_auto && height.to_mm > 1600.0,
          fix_bottom_height_mm: is_window_auto ? 400.0 : 0.0
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
          start: overlap_min - src_min,
          end: overlap_max - src_min,
          midpoint: ((overlap_min + overlap_max) * 0.5) - src_min,
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

      def calculate_preview_geometry(op)
        w = op[:width_len]
        h = op[:height_len]
        frame_d = FRAME_DEPTH

        org = op[:origin]
        x_vec = op[:x_axis]
        y_vec = op[:y_axis]
        z_vec = op[:z_axis]

        corners = []
        [0.0, h].each do |z_val|
          [0.0, frame_d].each do |y_val|
            [0.0, w].each do |x_val|
              pt = org.offset(x_vec, x_val).offset(y_vec, y_val).offset(z_vec, z_val)
              corners << pt
            end
          end
        end

        ordered_corners = [
          corners[0], corners[1], corners[3], corners[2],
          corners[4], corners[5], corners[7], corners[6]
        ]

        panel_count = resolve_panel_count(op)
        division_lines = []
        is_win = decide_is_window(op)

        # Panel vertical split lines
        if panel_count > 1
          (1...panel_count).each do |p_idx|
            split_x = w * (p_idx.to_f / panel_count)
            p_bot = org.offset(x_vec, split_x).offset(y_vec, frame_d * 0.5)
            p_top = p_bot.offset(z_vec, h)
            division_lines << [p_bot, p_top]
          end
        end

        # Window bottom fix preview line
        if is_win && op[:has_bottom_fix] && op[:fix_bottom_height_mm] > 0
          bot_fix_len = op[:fix_bottom_height_mm].mm
          if bot_fix_len < h - 100.mm
            p_f_l = org.offset(z_vec, bot_fix_len).offset(y_vec, frame_d * 0.5)
            p_f_r = p_f_l.offset(x_vec, w)
            division_lines << [p_f_l, p_f_r]
          end
        end

        # Top transom fix preview line
        if op[:has_transom] && op[:glass_height_mm] > 0
          transom_len = op[:glass_height_mm].mm
          if transom_len < h - 200.mm
            p_t_l = org.offset(z_vec, h - transom_len).offset(y_vec, frame_d * 0.5)
            p_t_r = p_t_l.offset(x_vec, w)
            division_lines << [p_t_l, p_t_r]
          end
        end

        {
          corners: ordered_corners,
          division_lines: division_lines,
          is_window: is_win
        }
      end

      def build_item_for_opening(op)
        model = Sketchup.active_model
        w_mm = op[:width_mm]
        h_mm = op[:height_mm]
        is_win = decide_is_window(op)
        panel_count = resolve_panel_count(op)

        assembly = if is_win
                     # Build WINDOW directly as an independent assembly
                     WindowBuilder.generate(
                       parent: model.active_entities,
                       name: "WINDOW_#{panel_count}P_#{w_mm.round(0)}x#{h_mm.round(0)}",
                       width: w_mm.mm,
                       height: h_mm.mm,
                       panel_count: panel_count,
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
