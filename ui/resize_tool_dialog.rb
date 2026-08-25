# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # HtmlDialog & Picker Tool for Resizing individual / multiple doors and windows
    module ResizeToolDialog
      # Tool to pick single door/window or drag selection window to inspect & resize
      class ResizePickerTool
        attr_accessor :selected_entities, :anchor, :show_anchors

        def initialize(dialog)
          @dialog = dialog
          @hover_target = nil
          @selected_entities = []
          @anchor = :center # :left, :center, :right
          @hover_anchor = nil
          @show_anchors = false

          @highlight_color = Sketchup::Color.new(22, 143, 214, 255) # Primary Blue (#168FD6)
          @fill_color = Sketchup::Color.new(22, 143, 214, 60)
          @selected_color = Sketchup::Color.new(243, 38, 46, 255)  # Red (#F3262E) for selected
          @selected_fill = Sketchup::Color.new(243, 38, 46, 70)

          # Drag selection box state
          @dragging = false
          @drag_start = nil
          @drag_current = nil
          @drag_box_color = Sketchup::Color.new(22, 143, 214, 255)
          @drag_fill_color = Sketchup::Color.new(22, 143, 214, 40)
        end

        def activate
          Sketchup.status_text = '[NAUQ CAD TO 3D] Click vào cửa hoặc kéo quét chọn. Click vào điểm GỐC TRÁI / GIỮA / PHẢI trên cửa để chọn gốc neo...'
        end

        def deactivate(view)
          ResizeToolDialog.active_picker_tool = nil if ResizeToolDialog.active_picker_tool == self
          @hover_target = nil
          @hover_anchor = nil
          @dragging = false
          view.invalidate
        end

        def onMouseMove(flags, x, y, view)
          if @drag_start
            @drag_current = Geom::Point3d.new(x, y, 0)
            if (@drag_start.x - x).abs > 3 || (@drag_start.y - y).abs > 3
              @dragging = true
              @hover_target = nil
              @hover_anchor = nil
            end
            view.invalidate
          else
            # Kiểm tra rê chuột trúng điểm neo Anchor không
            hovered_anchor = check_hover_anchor(view, x, y)
            if hovered_anchor != @hover_anchor
              @hover_anchor = hovered_anchor
              view.invalidate
            end

            unless @hover_anchor
              ph = view.pick_helper
              ph.do_pick(x, y)

              target = find_valid_target(ph)
              if target != @hover_target
                @hover_target = target
                view.invalidate
              end
            end
          end
        end

        def onLButtonDown(flags, x, y, view)
          if @hover_anchor
            # Click vào anchor handle
            @drag_start = nil
            return
          end

          @drag_start = Geom::Point3d.new(x, y, 0)
          @drag_current = @drag_start
          @dragging = false
          view.invalidate
        end

        def onLButtonUp(flags, x, y, view)
          if @hover_anchor
            @anchor = @hover_anchor
            @dialog&.execute_script("setAnchor('#{@anchor}');")
            view.invalidate
            return
          end

          was_dragging = @dragging
          start_pt = @drag_start

          @dragging = false
          @drag_start = nil
          @drag_current = nil

          if was_dragging && start_pt && ((start_pt.x - x).abs > 5 || (start_pt.y - y).abs > 5)
            min_x = [start_pt.x, x].min
            max_x = [start_pt.x, x].max
            min_y = [start_pt.y, y].min
            max_y = [start_pt.y, y].max

            @hover_target = nil
            view.invalidate

            select_entities_in_rect(view, min_x, min_y, max_x, max_y)
          else
            # Single click pick
            if @hover_target && @hover_target.valid?
              target = @hover_target
              @selected_entities = [target]
              @hover_target = nil
              view.invalidate
              ResizeToolDialog.on_target_picked(target)
            end
          end
          view.invalidate
        end

        def onSetCursor
          if @hover_anchor
            UI.set_cursor(6) # Hand cursor
          else
            UI.set_cursor(0)
          end
        end

        def draw(view)
          # 1. Draw 2D Drag Selection Box on screen
          if @dragging && @drag_start && @drag_current
            x1, y1 = @drag_start.x, @drag_start.y
            x2, y2 = @drag_current.x, @drag_current.y

            p1 = Geom::Point3d.new(x1, y1, 0)
            p2 = Geom::Point3d.new(x2, y1, 0)
            p3 = Geom::Point3d.new(x2, y2, 0)
            p4 = Geom::Point3d.new(x1, y2, 0)

            view.drawing_color = @drag_fill_color
            view.draw2d(GL_POLYGON, [p1, p2, p3, p4])

            view.drawing_color = @drag_box_color
            view.line_width = 2
            view.line_stipple = '- - '
            view.draw2d(GL_LINE_LOOP, [p1, p2, p3, p4])
            return
          end

          # 2. Draw 3D bounding box for selected entities
          if @selected_entities && !@selected_entities.empty?
            @selected_entities.each do |sel|
              next unless sel && sel.valid?
              draw_entity_bbox(view, sel, @selected_color, @selected_fill, line_width: 3)
            end

            # 3. Draw Anchor Handles (Left, Center, Right) ONLY when width is modified
            draw_anchor_handles(view) if @show_anchors
          end

          # 4. Draw 3D bounding box highlight for hover target
          if @hover_target && @hover_target.valid? && !@selected_entities.include?(@hover_target)
            draw_entity_bbox(view, @hover_target, @highlight_color, @fill_color, line_width: 2)
          end
        end

        private

        def check_hover_anchor(view, x, y)
          return nil unless @show_anchors
          return nil unless @selected_entities && !@selected_entities.empty?
          first = @selected_entities.first
          return nil unless first && first.valid?

          w_mm = ResizeToolDialog.read_dimension(first, 'width') || 900.0
          half_w = Geometry.mm_to_inch(w_mm / 2.0)
          u = first.transformation.xaxis.normalize
          c = first.bounds.center
          mid_z = (first.bounds.min.z + first.bounds.max.z) / 2.0

          p_l = Geom::Point3d.new(c.x - u.x * half_w, c.y - u.y * half_w, mid_z)
          p_c = Geom::Point3d.new(c.x, c.y, mid_z)
          p_r = Geom::Point3d.new(c.x + u.x * half_w, c.y + u.y * half_w, mid_z)

          [ [:left, p_l], [:center, p_c], [:right, p_r] ].each do |anchor_sym, pt3d|
            s_pt = view.screen_coords(pt3d)
            next if s_pt.z < 0 # Behind camera
            if (s_pt.x - x).abs <= 16 && (s_pt.y - y).abs <= 16
              return anchor_sym
            end
          end
          nil
        end

        def draw_anchor_handles(view)
          return unless @selected_entities && !@selected_entities.empty?
          first = @selected_entities.first
          return unless first && first.valid?

          w_mm = ResizeToolDialog.read_dimension(first, 'width') || 900.0
          half_w = Geometry.mm_to_inch(w_mm / 2.0)
          u = first.transformation.xaxis.normalize
          c = first.bounds.center
          min_z = first.bounds.min.z
          max_z = first.bounds.max.z
          mid_z = (min_z + max_z) / 2.0

          pt_l_bot = Geom::Point3d.new(c.x - u.x * half_w, c.y - u.y * half_w, min_z)
          pt_l_top = Geom::Point3d.new(c.x - u.x * half_w, c.y - u.y * half_w, max_z)
          p_l_mid = Geom::Point3d.new(c.x - u.x * half_w, c.y - u.y * half_w, mid_z)

          pt_c_bot = Geom::Point3d.new(c.x, c.y, min_z)
          pt_c_top = Geom::Point3d.new(c.x, c.y, max_z)
          p_c_mid = Geom::Point3d.new(c.x, c.y, mid_z)

          pt_r_bot = Geom::Point3d.new(c.x + u.x * half_w, c.y + u.y * half_w, min_z)
          pt_r_top = Geom::Point3d.new(c.x + u.x * half_w, c.y + u.y * half_w, max_z)
          p_r_mid = Geom::Point3d.new(c.x + u.x * half_w, c.y + u.y * half_w, mid_z)

          # Draw 3 vertical anchor lines
          draw_anchor_line(view, pt_l_bot, pt_l_top, @anchor == :left)
          draw_anchor_line(view, pt_c_bot, pt_c_top, @anchor == :center)
          draw_anchor_line(view, pt_r_bot, pt_r_top, @anchor == :right)

          # Draw 3 clickable anchor handles
          draw_anchor_disc(view, p_l_mid, :left)
          draw_anchor_disc(view, p_c_mid, :center)
          draw_anchor_disc(view, p_r_mid, :right)
        end

        def draw_anchor_line(view, pt_bot, pt_top, is_active)
          if is_active
            view.drawing_color = Sketchup::Color.new(5, 150, 105, 255) # Emerald
            view.line_width = 4
            view.line_stipple = ''
          else
            view.drawing_color = Sketchup::Color.new(100, 116, 139, 160)
            view.line_width = 1
            view.line_stipple = '- - '
          end
          view.draw(GL_LINES, [pt_bot, pt_top])
        end

        def draw_anchor_disc(view, pt3d, anchor_sym)
          s_pt = view.screen_coords(pt3d)
          return if s_pt.z < 0 # Behind camera

          is_active = (@anchor == anchor_sym)
          is_hover = (@hover_anchor == anchor_sym)

          radius = is_active ? 10 : (is_hover ? 9 : 7)

          fill_color = if is_active
            Sketchup::Color.new(5, 150, 105, 255)
          elsif is_hover
            Sketchup::Color.new(245, 158, 11, 255)
          else
            Sketchup::Color.new(241, 245, 249, 230)
          end

          border_color = if is_active
            Sketchup::Color.new(255, 255, 255, 255)
          elsif is_hover
            Sketchup::Color.new(217, 119, 6, 255)
          else
            Sketchup::Color.new(100, 116, 139, 255)
          end

          segments = 16
          pts_poly = []
          segments.times do |i|
            angle = (2.0 * Math::PI / segments) * i
            pts_poly << Geom::Point3d.new(s_pt.x + Math.cos(angle) * radius, s_pt.y + Math.sin(angle) * radius, 0)
          end

          view.drawing_color = fill_color
          view.draw2d(GL_POLYGON, pts_poly)

          view.drawing_color = border_color
          view.line_width = is_active ? 2 : 1
          view.line_stipple = ''
          view.draw2d(GL_LINE_LOOP, pts_poly)
        end

        private

        def draw_entity_bbox(view, ent, stroke_color, fill_color, line_width: 2)
          bbox = ent.bounds
          return if bbox.empty?

          pts = (0..7).map { |i| bbox.corner(i) }

          edges = [
            [0, 1], [1, 3], [3, 2], [2, 0],
            [4, 5], [5, 7], [7, 6], [6, 4],
            [0, 4], [1, 5], [2, 6], [3, 7]
          ]

          view.drawing_color = stroke_color
          view.line_width = line_width
          view.line_stipple = ''

          edges.each do |p1_idx, p2_idx|
            view.draw(GL_LINES, pts[p1_idx], pts[p2_idx])
          end

          view.drawing_color = fill_color
          faces = [
            [0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4],
            [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]
          ]
          faces.each do |f|
            view.draw(GL_POLYGON, f.map { |i| pts[i] })
          end
        end

        def select_entities_in_rect(view, min_x, min_y, max_x, max_y)
          model = Sketchup.active_model
          return unless model

          targets = []
          search_pool = []

          # Search in container groups
          ['NAUQ_DOORS', 'NAUQ_WINDOWS'].each do |cname|
            c = model.active_entities.find { |e| e.is_a?(Sketchup::Group) && e.name == cname }
            if c && c.valid?
              c.entities.each { |child| search_pool << child if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance) }
            end
          end

          # Also check active entities
          model.active_entities.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            search_pool << e if is_door_or_window?(e)
          end

          search_pool.uniq.each do |ent|
            next unless ent && ent.valid? && is_door_or_window?(ent)
            bbox = ent.bounds
            next if bbox.empty?

            center_pt = view.screen_coords(bbox.center)
            if center_pt.z >= 0 && center_pt.x >= min_x && center_pt.x <= max_x && center_pt.y >= min_y && center_pt.y <= max_y
              targets << ent
              next
            end

            corners = (0..7).map { |i| view.screen_coords(bbox.corner(i)) }
            any_corner_in = corners.any? do |s|
              s.z >= 0 && s.x >= min_x && s.x <= max_x && s.y >= min_y && s.y <= max_y
            end
            targets << ent if any_corner_in
          end

          targets.uniq!
          @selected_entities = targets

          if targets.empty?
            ResizeToolDialog.update_status('⚠️ Không tìm thấy cửa nào trong vùng quét.', 'error')
          else
            ResizeToolDialog.on_multiple_picked(targets)
          end
        end

        def find_valid_target(pick_helper)
          path = pick_helper.path_at(0) || []
          candidate = path.reverse.find do |ent|
            next false unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
            is_door_or_window?(ent)
          end
          return candidate if candidate

          target = pick_helper.best_picked
          if target.nil? || (!target.is_a?(Sketchup::Group) && !target.is_a?(Sketchup::ComponentInstance))
            target = path.reverse.find { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          end

          if target && (target.is_a?(Sketchup::Group) || target.is_a?(Sketchup::ComponentInstance))
            name = (target.name || '').upcase
            return nil if name.include?('NAUQ_WALL') || name.include?('NAUQ_SLAB') || name.include?('NAUQ_CAD')
            return target if is_door_or_window?(target)
          end

          nil
        end

        def is_door_or_window?(entity)
          return false unless entity.respond_to?(:get_attribute)
          Attribute.tagged_as?(entity, 'door') || Attribute.tagged_as?(entity, 'window') ||
            entity.attribute_dictionary('TT_Door') || entity.attribute_dictionary('NAUQ_DOOR') || entity.attribute_dictionary('NAUQ_WINDOW') ||
            (entity.name || '').upcase.start_with?('DOOR') || (entity.name || '').upcase.start_with?('WINDOW')
        end
      end

      # =========================================================================
      # Door / Window Realtime Interactive Move Tool
      # Di chuyển cửa realtime dọc theo phương của bức tường, hỗ trợ gõ VCB & ESC
      # =========================================================================
      class DoorMoveTool
        def initialize(dialog, targets)
          @dialog = dialog
          @targets = (targets || []).select { |t| t && t.valid? }
          @model = Sketchup.active_model
          @ip_current = Sketchup::InputPoint.new
          @delta_dist = 0.0 # internal inches
          @orig_transforms = {}
          @orig_centers = {}
          @targets.each do |t|
            @orig_transforms[t.entityID] = t.transformation
            @orig_centers[t.entityID] = t.bounds.center
          end

          first = @targets.first
          @u_dir = first ? first.transformation.xaxis.normalize : Geom::Vector3d.new(1, 0, 0)
          @first_center = first ? first.bounds.center : Geom::Point3d.new(0, 0, 0)
          @first_origin = first ? first.transformation.origin : Geom::Point3d.new(0, 0, 0)
          @line_color = Sketchup::Color.new(245, 158, 11, 255) # Orange #F59E0B
        end

        def activate
          Sketchup.status_text = '[NAUQ] Rê chuột để di chuyển cửa REALTIME dọc tường | Gõ số mm + Enter để dời chính xác | Click để chốt | ESC để hủy'
          Sketchup.vcb_label = 'Khoảng cách dịch (mm)'
          Sketchup.vcb_value = '0'
          @model.active_view.invalidate
        end

        def deactivate(view)
          view.invalidate
        end

        def enableVCB?
          true
        end

        def onUserText(text, _view)
          val_mm = text.to_f
          return if val_mm.abs < 0.001

          delta_inch = Geometry.mm_to_inch(val_mm)
          apply_delta_preview(delta_inch)
          commit_move(delta_inch)
        end

        def onMouseMove(_flags, x, y, view)
          @ip_current.pick(view, x, y)
          return unless @ip_current.valid?

          pos = @ip_current.position
          # Project vector onto wall direction @u_dir
          vec = pos - @first_origin
          @delta_dist = vec.dot(@u_dir)

          # Live realtime translation
          apply_delta_preview(@delta_dist)

          delta_mm = Geometry.inch_to_mm(@delta_dist).round(0)
          Sketchup.vcb_value = "#{delta_mm}"
          Sketchup.status_text = "[NAUQ] Dời: #{delta_mm > 0 ? '+' : ''}#{delta_mm} mm | Click để đặt | Gõ số mm + Enter | ESC hủy"
          view.invalidate
        end

        def onLButtonDown(_flags, _x, _y, _view)
          commit_move(@delta_dist)
        end

        def onKeyDown(key, _repeat, _flags, _view)
          if key == 27 # ESC
            cancel_move
          end
        end

        def draw(view)
          @ip_current.draw(view) if @ip_current.valid?

          # Draw guide line along wall
          if @targets.first && @targets.first.valid?
            p1 = @first_center - (@u_dir * 120.0) # ~3m guide
            p2 = @first_center + (@u_dir * 120.0)

            view.drawing_color = @line_color
            view.line_width = 2
            view.line_stipple = '- - '
            view.draw(GL_LINES, [p1, p2])

            # Draw realtime distance badge
            delta_mm = Geometry.inch_to_mm(@delta_dist).round(0)
            curr_center = @first_center + (@u_dir * @delta_dist)
            screen_pt = view.screen_coords(curr_center)
            view.draw_text(screen_pt, "  ↔ #{delta_mm > 0 ? '+' : ''}#{delta_mm} mm", color: @line_color)
          end
        end

        private

        def apply_delta_preview(delta)
          t_shift = Geom::Transformation.translation(Geom::Vector3d.new(delta, 0, 0))
          @targets.each do |target|
            next unless target && target.valid?
            orig_t = @orig_transforms[target.entityID]
            next unless orig_t
            target.transformation = orig_t * t_shift
          end
        end

        def commit_move(delta)
          delta_mm = Geometry.inch_to_mm(delta)
          if delta.abs < 0.001
            return cancel_move
          end

          @model.start_operation('NAUQ Di chuyển Cửa Realtime', true)
          begin
            walls_group = DWGReader.find_or_create_walls_group(@model)
            t_shift = Geom::Transformation.translation(Geom::Vector3d.new(delta, 0, 0))

            @targets.each do |target|
              next unless target && target.valid?
              orig_t = @orig_transforms[target.entityID]
              next unless orig_t

              # Finalize transformation
              target.transformation = orig_t * t_shift

              # Move wall opening geometry in all walls groups
              old_center = @orig_centers[target.entityID] || orig_t.origin
              w_mm = ResizeToolDialog.read_dimension(target, 'width') || 900.0
              h_mm = ResizeToolDialog.read_dimension(target, 'height') || 2200.0
              type = ResizeToolDialog.is_entity_window?(target) ? :window : :door
              z_off = ResizeToolDialog.read_z_offset(target, type)

              ResizeToolDialog.move_wall_opening_for_all_walls(
                @model,
                old_center,
                @u_dir,
                delta,
                w_mm,
                h_mm,
                z_off
              )
            end

            @model.commit_operation
            msg = "Đã di chuyển #{delta_mm.round(0)} mm thành công!"
            Logger.info(msg)
            ResizeToolDialog.update_status(msg, 'success')
          rescue => e
            @model.abort_operation
            Logger.error("Lỗi di chuyển cửa: #{e.message}")
            ResizeToolDialog.update_status("Lỗi: #{e.message}", 'error')
          end

          # Return to normal picker tool
          ResizeToolDialog.start_picker_tool
        end

        def cancel_move
          @targets.each do |target|
            next unless target && target.valid?
            orig_t = @orig_transforms[target.entityID]
            target.transformation = orig_t if orig_t
          end
          @model.active_view.invalidate
          ResizeToolDialog.start_picker_tool
          ResizeToolDialog.update_status('Đã hủy di chuyển.', 'info')
        end
      end

      class << self
        attr_accessor :active_picker_tool

        def show
          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            start_picker_tool
            return
          end

          @dialog = UI::HtmlDialog.new(
            dialog_title: 'Resize Door / Window (Sửa kích thước cửa)',
            preferences_key: 'NAUQ_CAD_TO_3D_Resize_Tool_Dialog',
            scrollable: true,
            resizable: true,
            width: 820,
            height: 720,
            min_width: 780,
            min_height: 660,
            left: 220,
            top: 100,
            style: UI::HtmlDialog::STYLE_DIALOG
          )

          @dialog.set_on_closed do
            stop_picker_tool
          end

          @dialog.set_html(html_content)
          attach_callbacks(@dialog)
          @dialog.show
          start_picker_tool
        end

        def close
          stop_picker_tool
          @dialog&.close
        end

        def start_picker_tool
          model = Sketchup.active_model
          return unless model

          tool = ResizePickerTool.new(@dialog)
          @active_picker_tool = tool
          model.select_tool(tool)
        end

        def start_move_tool
          model = Sketchup.active_model
          return unless model

          targets = @active_picker_tool&.selected_entities || []
          targets.select! { |t| t && t.valid? }

          if targets.empty?
            update_status('Vui lòng chọn ít nhất 1 cửa để di chuyển.', 'error')
            return
          end

          tool = DoorMoveTool.new(@dialog, targets)
          model.select_tool(tool)
          update_status('↔️ Đang ở chế độ Di chuyển: Rê chuột dọc theo tường HOẶC gõ khoảng cách (mm) + Enter...', 'waiting')
        end

        def stop_picker_tool
          model = Sketchup.active_model
          if @active_picker_tool
            @active_picker_tool = nil
            model.select_tool(nil) if model
          elsif model && model.tools.active_tool_name == 'NAUQ::CadTo3D::ResizeToolDialog::ResizePickerTool'
            model.select_tool(nil)
          end
        end

        def update_status(msg, status_type = 'info')
          return unless @dialog && @dialog.visible?
          msg_escaped = msg.to_s.gsub('\\', '\\\\').gsub("'", "\\'").gsub("\n", ' ')
          @dialog.execute_script("showStatus('#{msg_escaped}', '#{status_type}');")
        end

        # When a single target is picked by tool
        def on_target_picked(target)
          return unless @dialog && @dialog.visible? && target && target.valid?

          type = is_entity_window?(target) ? 'window' : 'door'
          width_mm = read_dimension(target, 'width') || 900.0
          height_mm = read_dimension(target, 'height') || (type == 'door' ? 2200.0 : 1200.0)
          panel_count = read_panel_count(target, type.to_sym)
          has_fix_top = read_has_fix(target, :top)
          has_fix_bottom = read_has_fix(target, :bottom)
          has_fix_left = read_has_fix(target, :left)
          has_fix_right = read_has_fix(target, :right)

          data = {
            count: 1,
            type: type,
            width: width_mm.round(1),
            height: height_mm.round(1),
            z_offset: read_z_offset(target, type).round(0),
            panel_count: panel_count,
            has_fix_top: has_fix_top,
            fix_top_height: read_dimension(target, 'fix_top_height') || 350.0,
            has_fix_bottom: has_fix_bottom,
            fix_bottom_height: read_dimension(target, 'fix_bottom_height') || 400.0,
            has_fix_left: has_fix_left,
            fix_left_width: read_dimension(target, 'fix_left_width') || 300.0,
            has_fix_right: has_fix_right,
            fix_right_width: read_dimension(target, 'fix_right_width') || 300.0,
            name: target.name || "Cửa #{type == 'door' ? 'đi' : 'sổ'}"
          }

          @dialog.execute_script("setPickedData(#{data.to_json});")
          update_status("Đã chọn: #{data[:name]} (#{width_mm.round(0)} x #{height_mm.round(0)} mm)", 'info')
        end

        # When multiple targets are swept by drag box
        def on_multiple_picked(targets)
          return unless @dialog && @dialog.visible? && targets && !targets.empty?

          first = targets.first
          type = is_entity_window?(first) ? 'window' : 'door'
          width_mm = read_dimension(first, 'width') || 900.0
          height_mm = read_dimension(first, 'height') || (type == 'door' ? 2200.0 : 1200.0)
          panel_count = read_panel_count(first, type.to_sym)
          has_fix_top = read_has_fix(first, :top)
          has_fix_bottom = read_has_fix(first, :bottom)
          has_fix_left = read_has_fix(first, :left)
          has_fix_right = read_has_fix(first, :right)

          data = {
            count: targets.length,
            type: type,
            width: width_mm.round(1),
            height: height_mm.round(1),
            z_offset: read_z_offset(first, type).round(0),
            panel_count: panel_count,
            has_fix_top: has_fix_top,
            fix_top_height: read_dimension(first, 'fix_top_height') || 350.0,
            has_fix_bottom: has_fix_bottom,
            fix_bottom_height: read_dimension(first, 'fix_bottom_height') || 400.0,
            has_fix_left: has_fix_left,
            fix_left_width: read_dimension(first, 'fix_left_width') || 300.0,
            has_fix_right: has_fix_right,
            fix_right_width: read_dimension(first, 'fix_right_width') || 300.0,
            name: "Đã chọn #{targets.length} cửa"
          }

          @dialog.execute_script("setPickedData(#{data.to_json});")
          update_status("Đã chọn #{targets.length} cửa trong vùng quét.", 'info')
        end

        # Execute resize on selected targets
        def execute_resize(data_hash)
          model = Sketchup.active_model
          return unless model

          targets = @active_picker_tool&.selected_entities || []
          targets.select! { |t| t && t.valid? }

          if targets.empty?
            update_status('Chưa chọn cửa nào.', 'error')
            return
          end

          new_width = data_hash['width'].to_f
          new_height = data_hash['height'].to_f
          new_z_offset = data_hash['z_offset'].to_f
          type = data_hash['type'].to_s == 'window' ? :window : :door
          panel_count = [data_hash['panel_count'].to_i, 1].max
          anchor = (data_hash['anchor'] || @active_picker_tool&.anchor || 'center').to_s
          new_z_offset = 0.0 if type == :door

          has_fix_top = data_hash['has_fix_top'] == true || data_hash['has_fix_top'] == 'true'
          fix_top_h = data_hash['fix_top_height'].to_f
          fix_top_h = 350.0 if fix_top_h <= 0 && has_fix_top

          has_fix_bottom = data_hash['has_fix_bottom'] == true || data_hash['has_fix_bottom'] == 'true'
          fix_bottom_h = data_hash['fix_bottom_height'].to_f
          fix_bottom_h = 400.0 if fix_bottom_h <= 0 && has_fix_bottom

          has_fix_left = data_hash['has_fix_left'] == true || data_hash['has_fix_left'] == 'true'
          fix_left_w = data_hash['fix_left_width'].to_f
          fix_left_w = 300.0 if fix_left_w <= 0 && has_fix_left

          has_fix_right = data_hash['has_fix_right'] == true || data_hash['has_fix_right'] == 'true'
          fix_right_w = data_hash['fix_right_width'].to_f
          fix_right_w = 300.0 if fix_right_w <= 0 && has_fix_right

          fix_opts = {
            has_fix_top: has_fix_top,
            fix_top_height: fix_top_h.mm,
            has_fix_bottom: has_fix_bottom,
            fix_bottom_height: fix_bottom_h.mm,
            has_fix_left: has_fix_left,
            fix_left_width: fix_left_w.mm,
            has_fix_right: has_fix_right,
            fix_right_width: fix_right_w.mm
          }

          if new_width <= 100 || new_height <= 100
            update_status('Kích thước không hợp lệ (> 100mm)', 'error')
            return
          end

          model.start_operation('NAUQ Resize Doors/Windows', true)
          begin
            success_count = 0
            new_targets = []

            targets.each do |target|
              next unless target && target.valid?

              parent_entities = target.parent ? target.parent.entities : model.active_entities
              old_transform = target.transformation
              old_center = target.bounds.center
              old_h = read_dimension(target, 'height') || new_height
              old_w = read_dimension(target, 'width') || new_width
              old_z_offset = read_z_offset(target, type)

              delta_w = (new_width - old_w).mm
              t_anchor_shift = case anchor
              when 'left' then Geom::Transformation.new
              when 'right' then Geom::Transformation.translation(Geom::Vector3d.new(-delta_w, 0, 0))
              else Geom::Transformation.translation(Geom::Vector3d.new(-delta_w / 2.0, 0, 0))
              end

              if type == :door
                new_group = DoorGenerator.generate(
                  fix_opts.merge(parent: parent_entities, name: "DOOR_RESIZED_#{panel_count}P", width: new_width.mm, height: new_height.mm, panel_count: panel_count)
                )
                new_group.transform!(old_transform * t_anchor_shift)
                Attribute.tag(new_group, 'door', width: new_width, height: new_height, panel_count: panel_count, **fix_opts)
                new_targets << new_group
              else
                win_assembly = WindowBuilder.generate(
                  fix_opts.merge(parent: parent_entities, name: "WINDOW_RESIZED_#{panel_count}P", width: new_width.mm, height: new_height.mm, panel_count: panel_count)
                )
                win_assembly.transform!(old_transform * t_anchor_shift)
                if (new_z_offset - old_z_offset).abs > 1.0
                  win_assembly.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, (new_z_offset - old_z_offset).mm)))
                end
                Attribute.tag(win_assembly, 'window', width: new_width, height: new_height, leaf_count: panel_count, z_offset: new_z_offset, **fix_opts)
                new_targets << win_assembly
              end

              if (old_h - new_height).abs > 1.0 || (old_w - new_width).abs > 1.0 || (type == :window && (old_z_offset - new_z_offset).abs > 1.0)
                walls_group = DWGReader.find_or_create_walls_group(model)
                adjust_wall_for_resize(walls_group, old_center, old_transform.xaxis, old_h, new_height, old_w, new_width, type, old_z_offset, new_z_offset, anchor)
              end

              target.erase! if target.valid?
              success_count += 1
            end

            model.commit_operation
            msg = "Đã cập nhật #{success_count} cửa thành công!"
            Logger.info(msg)
            update_status(msg, 'success')

            # Keep selection on the newly generated entities
            if @active_picker_tool
              @active_picker_tool.selected_entities = new_targets.select { |e| e && e.valid? }
            end
            model.active_view.invalidate
          rescue StandardError => e
            model.abort_operation
            Logger.error("Lỗi khi Resize cửa: #{e.message}")
            update_status("Lỗi: #{e.message}", 'error')
          end
        end

        # Chuẩn hóa kích thước và vị trí của các cửa được chọn khớp 100% với lỗ mở tường xung quanh
        def sync_selected_to_opening
          model = Sketchup.active_model
          return unless model

          targets = @active_picker_tool&.selected_entities || []
          targets.select! { |t| t && t.valid? }

          if targets.empty?
            update_status('Chưa chọn cửa nào để chuẩn hóa theo opening.', 'error')
            return
          end

          model.start_operation('NAUQ Chuẩn hóa Cửa theo Lỗ mở Tường', true)
          begin
            synced_count = 0
            new_targets = []
            last_data = nil

            targets.each do |target|
              next unless target && target.valid?

              detected = detect_opening_from_wall(model, target)
              next unless detected

              type = is_entity_window?(target) ? :window : :door
              parent_entities = target.parent ? target.parent.entities : model.active_entities

              panel_count = read_panel_count(target, type)
              has_fix_t = read_has_fix(target, :top)
              has_fix_b = read_has_fix(target, :bottom)
              has_fix_l = read_has_fix(target, :left)
              has_fix_r = read_has_fix(target, :right)

              # Low sill auto bottom fix rule
              if type == :window && detected[:z_offset] < 200.0
                has_fix_b = true
              end

              fix_opts = {
                has_fix_top: has_fix_t,
                fix_top_height: (read_dimension(target, 'fix_top_height') || 350.0).mm,
                has_fix_bottom: has_fix_b,
                fix_bottom_height: (read_dimension(target, 'fix_bottom_height') || 400.0).mm,
                has_fix_left: has_fix_l,
                fix_left_width: (read_dimension(target, 'fix_left_width') || 300.0).mm,
                has_fix_right: has_fix_r,
                fix_right_width: (read_dimension(target, 'fix_right_width') || 300.0).mm
              }

              new_w = detected[:width].mm
              new_h = detected[:height].mm

              if type == :door
                new_group = DoorGenerator.generate(
                  fix_opts.merge(
                    parent: parent_entities,
                    name: "DOOR_SYNC_#{panel_count}P",
                    width: new_w,
                    height: new_h,
                    panel_count: panel_count
                  )
                )
                rad = Math.atan2(detected[:dir].y, detected[:dir].x)
                t_shift = Geom::Transformation.translation(Geom::Vector3d.new(-new_w / 2.0, 0, 0))
                t_rot = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), rad)
                t_pos = Geom::Transformation.translation(detected[:center])
                new_group.transform!(t_pos * t_rot * t_shift)

                Attribute.tag(new_group, 'door', width: detected[:width], height: detected[:height], panel_count: panel_count, **fix_opts)
                new_targets << new_group
              else
                win_assembly = WindowBuilder.generate(
                  fix_opts.merge(
                    parent: parent_entities,
                    name: "WINDOW_SYNC_#{panel_count}P",
                    width: new_w,
                    height: new_h,
                    panel_count: panel_count
                  )
                )
                rad = Math.atan2(detected[:dir].y, detected[:dir].x)
                t_shift = Geom::Transformation.translation(Geom::Vector3d.new(-new_w / 2.0, 0, 0))
                t_rot = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), rad)
                t_pos = Geom::Transformation.translation(detected[:center])
                win_assembly.transform!(t_pos * t_rot * t_shift)

                Attribute.tag(win_assembly, 'window', width: detected[:width], height: detected[:height], leaf_count: panel_count, z_offset: detected[:z_offset], **fix_opts)
                new_targets << win_assembly
              end

              last_data = {
                type: type.to_s,
                width: detected[:width].round(1),
                height: detected[:height].round(1),
                z_offset: detected[:z_offset].round(0),
                panel_count: panel_count,
                has_fix_top: has_fix_t,
                fix_top_height: read_dimension(target, 'fix_top_height') || 350.0,
                has_fix_bottom: has_fix_b,
                fix_bottom_height: read_dimension(target, 'fix_bottom_height') || 400.0,
                has_fix_left: has_fix_l,
                fix_left_width: read_dimension(target, 'fix_left_width') || 300.0,
                has_fix_right: has_fix_r,
                fix_right_width: read_dimension(target, 'fix_right_width') || 300.0,
                name: (type == :door ? 'Cửa đi' : 'Cửa sổ') + " (Đã khớp #{detected[:width].round(0)}x#{detected[:height].round(0)})"
              }

              target.erase! if target.valid?
              synced_count += 1
            end

            if synced_count > 0
              model.commit_operation
              msg = "Đã chuẩn hóa #{synced_count} cửa khớp 100% với lỗ mở tường!"
              Logger.info(msg)
              update_status(msg, 'success')

              if last_data
                @dialog.execute_script("setPickedData(#{last_data.to_json});")
              end

              if @active_picker_tool
                @active_picker_tool.selected_entities = new_targets.select { |e| e && e.valid? }
              end
              model.active_view.invalidate
            else
              model.abort_operation
              update_status('Không phát hiện được biên dạng lỗ mở tường xung quanh cửa.', 'error')
            end
          rescue StandardError => e
            model.abort_operation
            Logger.error("Lỗi khi chuẩn hóa theo opening: #{e.message}")
            update_status("Lỗi: #{e.message}", 'error')
          end
        end

        # Tự động dò biên dạng lỗ mở tường xung quanh 1 bộ cửa (Door / Window)
        # @param model [Sketchup::Model]
        # @param target [Sketchup::Group, Sketchup::ComponentInstance]
        # @return [Hash, nil] {:width, :height, :z_offset, :center, :dir}
        def detect_opening_from_wall(model, target)
          return nil unless target && target.valid?

          type = is_entity_window?(target) ? :window : :door
          tr = target.transformation
          u_dir = tr.xaxis.normalize
          center = target.bounds.center

          was_visible = target.visible?
          target.visible = false

          begin
            z_min = target.bounds.min.z
            z_max = target.bounds.max.z
            z_samples = [
              z_min + (z_max - z_min) * 0.25,
              z_min + (z_max - z_min) * 0.5,
              z_min + (z_max - z_min) * 0.75
            ]

            left_hits = []
            right_hits = []

            z_samples.each do |zs|
              origin_s = Geom::Point3d.new(center.x, center.y, zs)

              # Ray left
              ray_l = [origin_s, Geom::Vector3d.new(-u_dir.x, -u_dir.y, -u_dir.z)]
              res_l = model.raytest(ray_l)
              if res_l
                left_hits << res_l[0]
              end

              # Ray right
              ray_r = [origin_s, Geom::Vector3d.new(u_dir.x, u_dir.y, u_dir.z)]
              res_r = model.raytest(ray_r)
              if res_r
                right_hits << res_r[0]
              end
            end

            return nil if left_hits.empty? || right_hits.empty?

            hit_left = left_hits.min_by { |p| (p - center).length }
            hit_right = right_hits.min_by { |p| (p - center).length }

            span_vec = hit_right - hit_left
            opening_w_inch = span_vec.dot(u_dir).abs
            return nil if opening_w_inch < 4.0 # Dưới 100mm

            mid_xy = Geom::Point3d.new(
              (hit_left.x + hit_right.x) / 2.0,
              (hit_left.y + hit_right.y) / 2.0,
              center.z
            )

            # Search vertical (-Z and +Z) from mid_xy to find bottom sill & top lintel
            ray_b = [mid_xy, Geom::Vector3d.new(0, 0, -1)]
            res_b = model.raytest(ray_b)

            ray_t = [mid_xy, Geom::Vector3d.new(0, 0, 1)]
            res_t = model.raytest(ray_t)

            z_bot = res_b ? res_b[0].z : target.bounds.min.z
            z_top = res_t ? res_t[0].z : target.bounds.max.z

            opening_h_inch = z_top - z_bot
            return nil if opening_h_inch < 4.0

            floor_z = 0.0
            walls_g = DWGReader.find_or_create_walls_group(model)
            if walls_g && walls_g.valid?
              floor_z = walls_g.bounds.min.z
            end

            z_offset_mm = [(z_bot - floor_z).to_mm.round(0), 0.0].max
            z_offset_mm = 0.0 if type == :door

            {
              width: opening_w_inch.to_mm.round(0),
              height: opening_h_inch.to_mm.round(0),
              z_offset: z_offset_mm,
              center: Geom::Point3d.new(mid_xy.x, mid_xy.y, z_bot),
              dir: u_dir
            }
          ensure
            target.visible = was_visible if target && target.valid?
          end
        end

        # Di chuyển ranh giới opening và đỉnh WallFill cũ → mới (không cần dựng lại tường)
        # @param walls_group [Sketchup::Group] NAUQ_WALLS
        # @param xy_origin [Geom::Point3d] tâm XY opening
        # @param wall_x_axis [Geom::Vector3d] vector chỉ phương dọc theo tường
        # @param old_height_mm [Float] chiều cao cửa cũ
        # @param new_height_mm [Float] chiều cao cửa mới
        # @param old_width_mm [Float] chiều rộng cửa cũ
        # @param new_width_mm [Float] chiều rộng cửa mới
        # @param type [Symbol] :door hoặc :window
        # @param old_z_offset_mm [Float] cao độ bậu cũ (window)
        # @param new_z_offset_mm [Float] cao độ bậu mới (window)
        # @param anchor [String, Symbol] 'left', 'center', 'right'
        def adjust_wall_for_resize(walls_group, xy_origin, wall_x_axis, old_height_mm, new_height_mm, old_width_mm, new_width_mm, type, old_z_offset_mm = 0.0, new_z_offset_mm = 0.0, anchor = 'center')
          return unless walls_group && walls_group.valid?

          base_z = walls_group.bounds.min.z
          max_w_mm = [old_width_mm, new_width_mm].max

          # 1. ĐIỀU CHỈNH CHIỀU NGANG OPENING (Má tường trái & phải theo Anchor)
          delta_w_mm = new_width_mm - old_width_mm
          if delta_w_mm.abs > 1.0 && wall_x_axis && wall_x_axis.valid?
            u = wall_x_axis.normalize
            half_old_w = Geometry.mm_to_inch(old_width_mm / 2.0)
            delta_w_inch = Geometry.mm_to_inch(delta_w_mm)
            tol = Geometry.mm_to_inch(45.0)

            case anchor.to_s
            when 'left'
              # Mép trái cố định: má trái dời 0, má phải dời +delta_w
              move_wall_jamb_boundary(walls_group, xy_origin, u, +half_old_w, delta_w_inch, tol, max_w_mm)
            when 'right'
              # Mép phải cố định: má trái dời -delta_w, má phải dời 0
              move_wall_jamb_boundary(walls_group, xy_origin, u, -half_old_w, -delta_w_inch, tol, max_w_mm)
            else # 'center'
              # Tâm giữa cố định: má trái dời -delta_w/2, má phải dời +delta_w/2
              delta_half_w = delta_w_inch / 2.0
              move_wall_jamb_boundary(walls_group, xy_origin, u, -half_old_w, -delta_half_w, tol, max_w_mm)
              move_wall_jamb_boundary(walls_group, xy_origin, u, +half_old_w, +delta_half_w, tol, max_w_mm)
            end
          end

          # 2. ĐIỀU CHỈNH CHIỀU CAO & CAO ĐỘ BẬU (WallFill trên / dưới)
          if type == :door
            old_top_z = base_z + Geometry.mm_to_inch(old_height_mm)
            new_top_z = base_z + Geometry.mm_to_inch(new_height_mm)
            delta = new_top_z - old_top_z

            if delta.abs > Geometry.mm_to_inch(1.0)
              count = move_wallfill_boundary(walls_group, xy_origin, old_top_z, delta, max_w_mm)
              Logger.info("Door WallFill: di chuyển #{count} đỉnh tại z=#{old_height_mm.round(0)}mm → z=#{new_height_mm.round(0)}mm")
            end

          elsif type == :window
            old_bottom_z = base_z + Geometry.mm_to_inch(old_z_offset_mm)
            new_bottom_z = base_z + Geometry.mm_to_inch(new_z_offset_mm)
            delta_bottom = new_bottom_z - old_bottom_z

            if delta_bottom.abs > Geometry.mm_to_inch(1.0)
              count = move_wallfill_boundary(walls_group, xy_origin, old_bottom_z, delta_bottom, max_w_mm)
              Logger.info("Window WallFill dưới: di chuyển #{count} đỉnh tại z=#{old_z_offset_mm.round(0)}mm → z=#{new_z_offset_mm.round(0)}mm")
            end

            old_top_z = base_z + Geometry.mm_to_inch(old_z_offset_mm + old_height_mm)
            new_top_z = base_z + Geometry.mm_to_inch(new_z_offset_mm + new_height_mm)
            delta_top = new_top_z - old_top_z

            if delta_top.abs > Geometry.mm_to_inch(1.0)
              count = move_wallfill_boundary(walls_group, xy_origin, old_top_z, delta_top, max_w_mm)
              Logger.info("Window WallFill trên: di chuyển #{count} đỉnh tại z=#{(old_z_offset_mm + old_height_mm).round(0)}mm → z=#{(new_z_offset_mm + new_height_mm).round(0)}mm")
            end
          end
        end

        # Tìm và di chuyển các đỉnh (vertex) của má tường / đầu WallFill tại vị trí ranh giới x_offset dọc theo tường
        # @param walls_group [Sketchup::Group] NAUQ_WALLS
        # @param xy_center [Geom::Point3d] tâm opening
        # @param u_dir [Geom::Vector3d] unit vector dọc theo tường
        # @param target_x_dist [Float] khoảng cách từ tâm theo u_dir (inch)
        # @param delta_move [Float] độ dời theo u_dir (inch)
        # @param tol [Float] sai số khoảng cách (inch)
        # @param max_w_mm [Float] chiều rộng lớn nhất (mm)
        def move_wall_jamb_boundary(walls_group, xy_center, u_dir, target_x_dist, delta_move, tol, max_w_mm)
          return 0 if delta_move.abs < 0.001

          search_radius = Geometry.mm_to_inch(max_w_mm + 400.0)
          max_perp_dist = Geometry.mm_to_inch(400.0)

          verts_to_move = []
          seen_ids = {}

          walls_group.entities.grep(Sketchup::Edge).each do |edge|
            next unless edge.valid?
            [edge.start, edge.end].each do |v|
              next if seen_ids[v.object_id]
              pos = v.position

              dx = pos.x - xy_center.x
              dy = pos.y - xy_center.y
              xy_dist = Math.sqrt(dx * dx + dy * dy)
              next if xy_dist > search_radius

              proj_x = (dx * u_dir.x + dy * u_dir.y)
              next unless (proj_x - target_x_dist).abs < tol

              perp_x = dx - proj_x * u_dir.x
              perp_y = dy - proj_x * u_dir.y
              perp_dist = Math.sqrt(perp_x * perp_x + perp_y * perp_y)
              next if perp_dist > max_perp_dist

              verts_to_move << v
              seen_ids[v.object_id] = true
            end
          end

          return 0 if verts_to_move.empty?

          move_vec = Geom::Vector3d.new(u_dir.x * delta_move, u_dir.y * delta_move, 0)
          vectors = Array.new(verts_to_move.size, move_vec)
          walls_group.entities.transform_by_vectors(verts_to_move, vectors)

          Logger.info("Wall Opening Width: di chuyển #{verts_to_move.size} đỉnh má tường (x_dist=#{target_x_dist.to_mm.round(0)}mm) theo delta=#{delta_move.to_mm.round(0)}mm")
          verts_to_move.size
        end

        # Tìm và di chuyển các đỉnh (vertex) trong NAUQ_WALLS tại z = target_z
        # gần vị trí XY của opening, dịch chuyển theo delta_z
        # @return [Integer] số đỉnh đã di chuyển
        def move_wallfill_boundary(walls_group, xy_pos, target_z, delta_z, width_mm)
          search_radius = Geometry.mm_to_inch(width_mm + 300.0)
          z_tolerance = Geometry.mm_to_inch(25.0)

          verts_to_move = []
          seen_ids = {}

          walls_group.entities.grep(Sketchup::Edge).each do |edge|
            next unless edge.valid?
            [edge.start, edge.end].each do |v|
              next if seen_ids[v.object_id]
              pos = v.position
              next unless (pos.z - target_z).abs < z_tolerance

              dx = pos.x - xy_pos.x
              dy = pos.y - xy_pos.y
              xy_dist = Math.sqrt(dx * dx + dy * dy)
              next if xy_dist > search_radius

              verts_to_move << v
              seen_ids[v.object_id] = true
            end
          end

          return 0 if verts_to_move.empty?

          move_vec = Geom::Vector3d.new(0, 0, delta_z)
          vectors = Array.new(verts_to_move.size, move_vec)
          walls_group.entities.transform_by_vectors(verts_to_move, vectors)

          verts_to_move.size
        end

        # Tìm và di chuyển lỗ mở trên tất cả các group tường của mô hình
        def move_wall_opening_for_all_walls(model, old_center, u_dir, delta_inch, width_mm, height_mm, z_offset_mm)
          total_moved = 0
          all_groups = []

          wg = DWGReader.find_or_create_walls_group(model)
          if wg && wg.valid?
            all_groups << wg
            wg.entities.grep(Sketchup::Group).each { |sub| all_groups << sub if sub.valid? }
          end

          model.entities.grep(Sketchup::Group).each do |g|
            next unless g.valid?
            name = (g.name || '').upcase
            if name.include?('NAUQ_WALL') || name.include?('WALL') || Attribute.tagged_as?(g, 'wall')
              all_groups << g unless all_groups.include?(g)
            end
          end

          all_groups.each do |g|
            total_moved += move_wall_opening_along_wall(g, old_center, u_dir, delta_inch, width_mm, height_mm, z_offset_mm)
          end

          total_moved
        end

        # Di chuyển toàn bộ hình học của lỗ mở tường và WallFill dọc theo tường
        # @param walls_group [Sketchup::Group]
        # @param old_center [Geom::Point3d]
        # @param u_dir [Geom::Vector3d]
        # @param delta_inch [Float]
        # @param width_mm [Float]
        # @param height_mm [Float]
        # @param z_offset_mm [Float]
        # @return [Integer] số đỉnh đã di chuyển
        def move_wall_opening_along_wall(walls_group, old_center, u_dir, delta_inch, width_mm, height_mm, z_offset_mm)
          return 0 unless walls_group && walls_group.valid? && delta_inch.abs > 0.001

          # Convert to local coordinates of walls_group if needed
          wg_tr = walls_group.transformation
          if wg_tr.identity?
            local_center = old_center
            local_u = u_dir
          else
            inv_tr = wg_tr.inverse
            local_center = inv_tr * old_center
            local_u = (inv_tr * u_dir) - (inv_tr * Geom::Point3d.new(0, 0, 0))
            local_u.normalize!
          end

          half_w_inch = Geometry.mm_to_inch(width_mm / 2.0)
          tol_x = Geometry.mm_to_inch(80.0) # 80mm tolerance
          max_perp_dist = Geometry.mm_to_inch(450.0)
          search_radius = half_w_inch + Geometry.mm_to_inch(300.0)

          verts_to_move = []
          seen_ids = {}

          walls_group.entities.grep(Sketchup::Edge).each do |edge|
            next unless edge.valid?
            [edge.start, edge.end].each do |v|
              next if seen_ids[v.object_id]
              pos = v.position

              dx = pos.x - local_center.x
              dy = pos.y - local_center.y
              xy_dist = Math.sqrt(dx * dx + dy * dy)
              next if xy_dist > search_radius

              proj_x = (dx * local_u.x + dy * local_u.y)
              next if proj_x.abs > (half_w_inch + tol_x)

              perp_x = dx - proj_x * local_u.x
              perp_y = dy - proj_x * local_u.y
              perp_dist = Math.sqrt(perp_x * perp_x + perp_y * perp_y)
              next if perp_dist > max_perp_dist

              verts_to_move << v
              seen_ids[v.object_id] = true
            end
          end

          return 0 if verts_to_move.empty?

          move_vec = Geom::Vector3d.new(local_u.x * delta_inch, local_u.y * delta_inch, 0)
          vectors = Array.new(verts_to_move.size, move_vec)
          walls_group.entities.transform_by_vectors(verts_to_move, vectors)

          Logger.info("Move Wall Opening: Đã dịch chuyển #{verts_to_move.size} đỉnh trong #{walls_group.name || 'WALLS'} theo delta=#{delta_inch.to_mm.round(0)}mm")
          verts_to_move.size
        end

        def is_entity_window?(entity)
          return true if Attribute.tagged_as?(entity, 'window')
          return true if entity.attribute_dictionary('NAUQ_WINDOW')
          return true if entity.get_attribute('NAUQ_CAD_TO_3D', 'type') == 'window'
          name = (entity.name || '').upcase
          return true if name.start_with?('WINDOW') || name.include?('CUA SO') || name.include?('TT_WIN')
          false
        end

        def read_has_fix(entity, direction)
          key = "has_fix_#{direction}"
          val = Attribute.get(entity, key) || entity.get_attribute('NAUQ_DOOR', key) || entity.get_attribute('NAUQ_WINDOW', key)
          return true if val == true || val.to_s == 'true' || val.to_i == 1
          if direction == :top || direction == 'top'
            return true if read_has_fix_top(entity)
          elsif (direction == :bottom || direction == 'bottom') && is_entity_window?(entity)
            z_off = read_z_offset(entity, 'window')
            return true if z_off < 200.0
          end
          false
        end

        def read_has_fix_top(entity)
          val = Attribute.get(entity, 'has_fix_top') || entity.get_attribute('NAUQ_DOOR', 'has_fix_top') || entity.get_attribute('NAUQ_WINDOW', 'has_fix_top')
          return true if val == true || val.to_s == 'true' || val.to_i == 1
          name = (entity.name || '').upcase
          return true if name.include?('FIX')
          false
        end

        def read_dimension(entity, key)
          val = Attribute.get(entity, "#{key}_mm") || Attribute.get(entity, key) ||
                entity.get_attribute('TT_Door', "#{key}_mm") ||
                entity.get_attribute('NAUQ_DOOR', key) || entity.get_attribute('NAUQ_WINDOW', key)

          if val
            val_f = val.to_f
            if key == 'height' && val_f > 0 && val_f < 150.0
              val_f = val_f.inch.to_mm
            elsif key == 'width' && val_f > 0 && val_f < 100.0
              val_f = val_f.inch.to_mm
            end
            return val_f if val_f > 100.0
          end

          if entity.respond_to?(:bounds) && !entity.bounds.empty?
            return entity.bounds.height.to_mm if key == 'height' && entity.bounds.height.to_mm > 100.0
            return [entity.bounds.width.to_mm, entity.bounds.depth.to_mm].max if key == 'width'
          end
          nil
        end

        def read_panel_count(entity, type)
          val = Attribute.get(entity, 'panel_count') || Attribute.get(entity, 'leaf_count') ||
                entity.get_attribute('NAUQ_DOOR', 'leaf_count') || entity.get_attribute('NAUQ_DOOR', 'panel_count') ||
                entity.get_attribute('NAUQ_WINDOW', 'leaf_count') || entity.get_attribute('NAUQ_WINDOW', 'panel_count')
          return val.to_i if val && val.to_i > 0

          name = (entity.name || '').upcase
          if name =~ /_(\d+)P/ || name =~ /(\d+) cánh/i || name =~ /(\d+)CANH/i
            return $1.to_i if $1.to_i > 0
          end

          w = read_dimension(entity, 'width') || 900.0
          max_w = type == :door ? (Config.get(:door_max_width) || 900.0) : (Config.get(:window_max_width) || 900.0)
          [(w / max_w).ceil, 1].max
        end

        def read_z_offset(entity, type)
          return 0.0 if type == :door || type.to_s == 'door'
          val = Attribute.get(entity, 'z_offset_mm') || Attribute.get(entity, 'z_offset') ||
                entity.get_attribute('NAUQ_WINDOW', 'z_offset')
          return val.to_f if val && val.to_f > 0.0

          if entity.respond_to?(:bounds) && !entity.bounds.empty?
            z = entity.bounds.min.z.to_mm
            return z.round(1) if z > 50.0
          end
          Config.get(:window_offset) || 900.0
        end

        private

        def attach_callbacks(dialog)
          dialog.add_action_callback('do_resize') do |_ctx, data_hash|
            next unless data_hash.is_a?(Hash)
            execute_resize(data_hash)
          end

          dialog.add_action_callback('sync_with_opening') do |_ctx|
            sync_selected_to_opening
          end

          dialog.add_action_callback('start_move_tool') do |_ctx|
            start_move_tool
          end

          dialog.add_action_callback('set_anchor') do |_ctx, anchor_str|
            if @active_picker_tool
              @active_picker_tool.anchor = anchor_str.to_sym rescue :center
              Sketchup.active_model&.active_view&.invalidate
            end
          end

          dialog.add_action_callback('set_show_anchors') do |_ctx, flag|
            if @active_picker_tool
              @active_picker_tool.show_anchors = (flag == true || flag == 'true')
              Sketchup.active_model&.active_view&.invalidate
            end
          end

          dialog.add_action_callback('activate_picker') do |_ctx|
            start_picker_tool
            update_status('Đang ở chế độ chọn: Click vào 1 cửa HOẶC kéo quét vùng chọn trên màn hình...', 'waiting')
          end

          dialog.add_action_callback('close_dialog') do |_ctx|
            close
          end
        end

        def html_content
          <<~HTML
            <!DOCTYPE html>
            <html lang="vi">
            <head>
              <meta charset="UTF-8">
              <title>Resize Door / Window</title>
              <style>
                :root {
                  color-scheme: light;
                  --bg-color: #f8fafc;
                  --card-bg: #ffffff;
                  --border-color: #cbd5e1;
                  --text-main: #0f172a;
                  --text-muted: #64748b;
                  --primary-color: #059669;
                  --primary-hover: #047857;
                  --accent-color: #f3262e;
                  --btn-secondary: #e2e8f0;
                  --btn-secondary-hover: #cbd5e1;
                }

                * { box-sizing: border-box; margin: 0; padding: 0; }

                html, body {
                  color-scheme: light;
                  background-color: var(--bg-color);
                  color: var(--text-main);
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
                  padding: 14px;
                  margin: 0;
                  padding: 10px 14px;
                  display: flex;
                  flex-direction: column;
                  height: 100vh;
                  box-sizing: border-box;
                  overflow: hidden;
                }

                /* Custom Light mode scrollbar */
                ::-webkit-scrollbar {
                  width: 7px;
                  height: 7px;
                }
                ::-webkit-scrollbar-button {
                  display: none;
                  width: 0;
                  height: 0;
                }
                ::-webkit-scrollbar-track {
                  background: #f1f5f9;
                }
                ::-webkit-scrollbar-thumb {
                  background: #cbd5e1;
                  border-radius: 4px;
                }
                ::-webkit-scrollbar-thumb:hover {
                  background: #94a3b8;
                }

                .header {
                  margin-bottom: 6px;
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                  flex-shrink: 0;
                }

                .header-title {
                  font-size: 14px;
                  font-weight: 700;
                  color: var(--text-main);
                }

                .header-subtitle {
                  font-size: 11px;
                  color: var(--text-muted);
                  margin-top: 1px;
                }

                .status-box {
                  background: #f1f5f9;
                  border: 1px solid var(--border-color);
                  border-radius: 6px;
                  padding: 4px 10px;
                  font-size: 11px;
                  color: var(--text-main);
                  margin-bottom: 8px;
                  display: flex;
                  align-items: center;
                  gap: 6px;
                  min-height: 28px;
                  flex-shrink: 0;
                }

                .status-box.waiting {
                  background: #eff6ff;
                  border-color: #bfdbfe;
                  color: #1d4ed8;
                }

                .status-box.success {
                  background: #ecfdf5;
                  border-color: #a7f3d0;
                  color: #047857;
                }

                .status-box.error {
                  background: #fef2f2;
                  border-color: #fecaca;
                  color: #b91c1c;
                }

                .main-layout {
                  display: grid;
                  grid-template-columns: 350px 1fr;
                  gap: 12px;
                  flex: 1;
                  min-height: 0;
                }

                .left-column {
                  display: flex;
                  flex-direction: column;
                  gap: 6px;
                  overflow-y: auto;
                  padding-right: 4px;
                  height: 100%;
                  box-sizing: border-box;
                }

                /* Type tabs matching BuildDialog & ReplaceDialog */
                .type-tabs {
                  display: flex;
                  gap: 6px;
                  margin-bottom: 2px;
                  flex-shrink: 0;
                }

                .tab-btn {
                  flex: 1;
                  padding: 6px 10px;
                  border: 1px solid var(--border-color);
                  background: var(--card-bg);
                  border-radius: 6px;
                  font-size: 11px;
                  font-weight: 700;
                  color: var(--text-muted);
                  cursor: pointer;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  gap: 6px;
                  transition: all 0.2s;
                }

                .tab-btn.active {
                  border-color: var(--primary-color);
                  background: #ecfdf5;
                  color: var(--primary-color);
                }

                .section {
                  background: var(--card-bg);
                  border: 1px solid var(--border-color);
                  border-radius: 8px;
                  padding: 8px 10px;
                  margin-bottom: 0;
                  flex-shrink: 0;
                }

                .section.form-section {
                  display: flex;
                  flex-direction: column;
                  gap: 6px;
                }

                .section-title {
                  font-size: 11px;
                  font-weight: 700;
                  color: var(--text-main);
                  text-transform: uppercase;
                  letter-spacing: 0.4px;
                  margin-bottom: 6px;
                  padding-bottom: 4px;
                  border-bottom: 1px solid #f1f5f9;
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                }

                .target-tag {
                  font-size: 10px;
                  font-weight: 700;
                  color: var(--primary-color);
                  background: #ecfdf5;
                  padding: 2px 6px;
                  border-radius: 4px;
                  border: 1px solid #a7f3d0;
                }

                .form-grid {
                  display: grid;
                  grid-template-columns: 1fr 1fr;
                  gap: 6px 10px;
                }

                .form-group {
                  display: flex;
                  flex-direction: column;
                  gap: 3px;
                }

                .form-group.full {
                  grid-column: span 2;
                }

                label {
                  font-size: 11px;
                  font-weight: 600;
                  color: var(--text-muted);
                }

                input[type="number"] {
                  width: 100%;
                  box-sizing: border-box;
                  background: #ffffff;
                  border: 1px solid var(--border-color);
                  color: var(--text-main);
                  border-radius: 5px;
                  padding: 4px 6px;
                  font-size: 12px;
                  font-weight: 600;
                  outline: none;
                  transition: border-color 0.15s, box-shadow 0.15s;
                }

                input[type="number"]:focus {
                  border-color: var(--primary-color);
                  box-shadow: 0 0 0 2px rgba(5, 150, 105, 0.18);
                }

                input[type="number"]:disabled {
                  background: #f1f5f9;
                  color: #94a3b8;
                  cursor: not-allowed;
                  border-color: #e2e8f0;
                }

                .checkbox-row {
                  display: flex;
                  align-items: center;
                  gap: 6px;
                  margin-top: 2px;
                  padding: 3px 6px;
                  background: #f8fafc;
                  border: 1px solid #e2e8f0;
                  border-radius: 5px;
                }

                input[type="checkbox"] {
                  width: 14px;
                  height: 14px;
                  cursor: pointer;
                  accent-color: var(--primary-color);
                }

                .anchor-tabs {
                  display: flex;
                  gap: 4px;
                  margin-top: 2px;
                }

                .anchor-btn {
                  flex: 1;
                  padding: 3px 6px;
                  border: 1px solid var(--border-color);
                  background: #f8fafc;
                  border-radius: 4px;
                  font-size: 10px;
                  font-weight: 600;
                  color: var(--text-muted);
                  cursor: pointer;
                  text-align: center;
                  transition: all 0.15s;
                }

                .anchor-btn.active {
                  border-color: var(--primary-color);
                  background: #ecfdf5;
                  color: var(--primary-color);
                  font-weight: 700;
                }

                /* Lu Ban Ruler Card Styles */
                .luban-card {
                  background: #f8fafc;
                  border: 1px solid var(--border-color);
                  border-radius: 6px;
                  padding: 6px 8px;
                  margin-top: 4px;
                  display: flex;
                  flex-direction: column;
                  gap: 4px;
                  transition: all 0.2s ease;
                }

                .luban-card.is-good {
                  background: #f0fdf4;
                  border-color: #86efac;
                }

                .luban-card.is-bad {
                  background: #fef2f2;
                  border-color: #fca5a5;
                }

                .luban-header {
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                  gap: 6px;
                }

                .luban-title-wrap {
                  display: flex;
                  align-items: center;
                  gap: 5px;
                  font-size: 11px;
                  font-weight: 700;
                  color: var(--text-main);
                }

                .luban-badge {
                  font-size: 10px;
                  font-weight: 700;
                  padding: 1px 6px;
                  border-radius: 4px;
                  letter-spacing: 0.2px;
                  white-space: nowrap;
                }

                .luban-badge.good {
                  background: #16a34a;
                  color: #ffffff;
                }

                .luban-badge.bad {
                  background: #dc2626;
                  color: #ffffff;
                }

                .luban-badge.neutral {
                  background: #94a3b8;
                  color: #ffffff;
                }

                .luban-detail {
                  font-size: 10px;
                  color: var(--text-muted);
                  line-height: 1.3;
                }

                .luban-card.is-good .luban-detail {
                  color: #15803d;
                  font-weight: 600;
                }

                .luban-card.is-bad .luban-detail {
                  color: #b91c1c;
                  font-weight: 600;
                }

                .luban-suggest-row {
                  display: flex;
                  align-items: center;
                  flex-wrap: wrap;
                  gap: 4px;
                  margin-top: 1px;
                  padding-top: 3px;
                  border-top: 1px dashed rgba(0, 0, 0, 0.08);
                }

                .luban-suggest-label {
                  font-size: 10px;
                  font-weight: 600;
                  color: var(--text-muted);
                }

                .luban-pills {
                  display: flex;
                  gap: 4px;
                  flex-wrap: wrap;
                }

                .luban-pill {
                  font-size: 10px;
                  font-weight: 700;
                  padding: 1px 6px;
                  border-radius: 10px;
                  background: #ffffff;
                  border: 1px solid #86efac;
                  color: #16a34a;
                  cursor: pointer;
                  display: inline-flex;
                  align-items: center;
                  gap: 2px;
                  transition: all 0.15s ease;
                  box-shadow: 0 1px 2px rgba(0,0,0,0.04);
                }

                .luban-pill:hover {
                  background: #16a34a;
                  color: #ffffff;
                  border-color: #16a34a;
                  transform: translateY(-1px);
                }

                /* Fix Grid Styles */
                .fix-section-title {
                  font-size: 10px;
                  font-weight: 700;
                  color: var(--text-muted);
                  text-transform: uppercase;
                  letter-spacing: 0.4px;
                  margin-top: 3px;
                  margin-bottom: 2px;
                }

                .fix-grid {
                  display: grid;
                  grid-template-columns: 1fr 1fr;
                  gap: 5px;
                }

                .fix-item {
                  display: flex;
                  align-items: center;
                  justify-content: space-between;
                  gap: 4px;
                  background: #f8fafc;
                  border: 1px solid #e2e8f0;
                  border-radius: 4px;
                  padding: 2px 5px;
                }

                .fix-checkbox-label {
                  display: flex;
                  align-items: center;
                  gap: 4px;
                  font-size: 11px;
                  font-weight: 600;
                  color: var(--text-main);
                  cursor: pointer;
                  user-select: none;
                }

                .fix-item input[type="number"] {
                  width: 52px;
                  padding: 2px 4px;
                  font-size: 11px;
                  text-align: right;
                }

                /* Preview Box Styles */
                .preview-container {
                  background: var(--card-bg);
                  border: 1px solid var(--border-color);
                  border-radius: 8px;
                  padding: 8px 10px;
                  display: flex;
                  flex-direction: column;
                  align-items: center;
                  height: 100%;
                  box-sizing: border-box;
                  min-height: 0;
                }

                .preview-header {
                  width: 100%;
                  font-size: 11px;
                  font-weight: 700;
                  color: var(--text-main);
                  text-transform: uppercase;
                  letter-spacing: 0.4px;
                  margin-bottom: 6px;
                  padding-bottom: 4px;
                  border-bottom: 1px solid #f1f5f9;
                  display: flex;
                  justify-content: space-between;
                  flex-shrink: 0;
                }

                .preview-svg-wrap {
                  flex: 1;
                  width: 100%;
                  min-height: 0;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  background: #f8fafc;
                  border: 1px dashed #cbd5e1;
                  border-radius: 6px;
                  overflow: hidden;
                  padding: 6px;
                  box-sizing: border-box;
                }

                .preview-footer {
                  margin-top: 6px;
                  font-size: 10px;
                  font-weight: 600;
                  color: var(--text-muted);
                  flex-shrink: 0;
                }

                .actions {
                  display: flex;
                  justify-content: flex-end;
                  align-items: center;
                  gap: 8px;
                  margin-top: 8px;
                  padding-top: 8px;
                  border-top: 1px solid var(--border-color);
                  flex-shrink: 0;
                }

                button {
                  padding: 8px 18px;
                  border-radius: 6px;
                  border: 1px solid transparent;
                  font-size: 12px;
                  font-weight: 700;
                  cursor: pointer;
                  transition: all 0.15s;
                }

                .btn-primary {
                  background: linear-gradient(135deg, #10b981 0%, #047857 100%);
                  color: #ffffff;
                  border: 1px solid rgba(255, 255, 255, 0.2);
                  box-shadow: 0 2px 6px rgba(16, 185, 129, 0.3);
                }

                .btn-primary:hover {
                  background: linear-gradient(135deg, #059669 0%, #065f46 100%);
                  box-shadow: 0 4px 10px rgba(16, 185, 129, 0.4);
                  transform: translateY(-1px);
                }

                .btn-sync {
                  background: linear-gradient(135deg, #10b981 0%, #059669 100%);
                  color: #ffffff;
                  border: 1px solid rgba(255, 255, 255, 0.2);
                  box-shadow: 0 2px 6px rgba(16, 185, 129, 0.25);
                  display: inline-flex;
                  align-items: center;
                  gap: 6px;
                }

                .btn-sync:hover {
                  background: linear-gradient(135deg, #059669 0%, #047857 100%);
                  box-shadow: 0 4px 10px rgba(16, 185, 129, 0.35);
                  transform: translateY(-1px);
                }

                .btn-move {
                  background: linear-gradient(135deg, #10b981 0%, #059669 100%);
                  color: #ffffff;
                  border: 1px solid rgba(255, 255, 255, 0.2);
                  box-shadow: 0 2px 6px rgba(16, 185, 129, 0.25);
                  display: inline-flex;
                  align-items: center;
                  gap: 5px;
                }

                .btn-move:hover {
                  background: linear-gradient(135deg, #d97706 0%, #b45309 100%);
                  box-shadow: 0 4px 10px rgba(245, 158, 11, 0.35);
                  transform: translateY(-1px);
                }

                .btn-secondary {
                  background-color: var(--btn-secondary);
                  color: var(--text-main);
                  border-color: var(--border-color);
                }

                .btn-secondary:hover {
                  background-color: var(--btn-secondary-hover);
                }
              </style>
            </head>
            <body>
              <div class="header">
                <div>
                  <h2>RESIZE TỪNG CỬA (NHANH)</h2>
                  <p>Click hoặc quét chọn cửa trên mô hình để lấy thông số và điều chỉnh</p>
                </div>
              </div>

              <div class="status-box waiting" id="status_box">
                Click vào 1 cửa hoặc quét chọn nhiều cửa trên màn hình...
              </div>

              <div class="main-layout">
                <!-- Left column: form params -->
                <div class="left-column">
                  <!-- Type Selector Tabs -->
                  <div class="type-tabs">
                    <div class="tab-btn active" id="btn_door" onclick="selectType('door')">Cửa đi (Door)</div>
                    <div class="tab-btn" id="btn_window" onclick="selectType('window')">Cửa sổ (Window)</div>
                  </div>

                  <div class="section form-section">
                    <div class="section-title">
                      <span>Thông số kích thước</span>
                      <span id="target_label" class="target-tag">Chưa chọn cửa</span>
                    </div>

                    <div class="form-grid">
                      <div class="form-group">
                        <label>Chiều rộng cửa (W mm)</label>
                        <input type="number" id="width" step="10" placeholder="VD: 900" oninput="onInputChanged()" onchange="onInputChanged()" required>
                      </div>
                      <div class="form-group">
                        <label>Cote trên cửa (Lanh-tô mm)</label>
                        <input type="number" id="top_cote" step="10" placeholder="VD: 2200" oninput="onHeightParamsChanged()" onchange="onHeightParamsChanged()" required>
                      </div>
                      <div class="form-group">
                        <label>Cote bậu cửa sổ (Offset mm)</label>
                        <input type="number" id="z_offset" step="10" value="0" oninput="onHeightParamsChanged()" onchange="onHeightParamsChanged()" disabled>
                      </div>
                      <div class="form-group">
                        <label>Chiều cao cửa (Tự tính mm)</label>
                        <input type="number" id="height_display" disabled style="background: #f1f5f9; color: var(--primary-color); font-weight: 700;">
                      </div>
                      <div class="form-group full">
                        <label>Số cánh cửa</label>
                        <input type="number" id="panel_count" min="1" max="10" value="1" oninput="onInputChanged()" onchange="onInputChanged()" required>
                      </div>
                      <div class="form-group full">
                        <div class="fix-section-title">Cấu hình ô Fix kính (4 hướng)</div>
                        <div class="fix-grid">
                          <!-- Top Fix -->
                          <div class="fix-item">
                            <label class="fix-checkbox-label">
                              <input type="checkbox" id="has_fix_top" onchange="toggleFixInput('top'); onInputChanged();">
                              <span>Fix Trên</span>
                            </label>
                            <input type="number" id="fix_top_height" placeholder="Cao" value="350" step="10" disabled oninput="onInputChanged()" onchange="onInputChanged()">
                          </div>
                          <!-- Bottom Fix -->
                          <div class="fix-item">
                            <label class="fix-checkbox-label">
                              <input type="checkbox" id="has_fix_bottom" onchange="toggleFixInput('bottom'); onInputChanged();">
                              <span>Fix Dưới</span>
                            </label>
                            <input type="number" id="fix_bottom_height" placeholder="Cao" value="400" step="10" disabled oninput="onInputChanged()" onchange="onInputChanged()">
                          </div>
                          <!-- Left Fix -->
                          <div class="fix-item">
                            <label class="fix-checkbox-label">
                              <input type="checkbox" id="has_fix_left" onchange="toggleFixInput('left'); onInputChanged();">
                              <span>Fix Trái</span>
                            </label>
                            <input type="number" id="fix_left_width" placeholder="Rộng" value="300" step="10" disabled oninput="onInputChanged()" onchange="onInputChanged()">
                          </div>
                          <!-- Right Fix -->
                          <div class="fix-item">
                            <label class="fix-checkbox-label">
                              <input type="checkbox" id="has_fix_right" onchange="toggleFixInput('right'); onInputChanged();">
                              <span>Fix Phải</span>
                            </label>
                            <input type="number" id="fix_right_width" placeholder="Rộng" value="300" step="10" disabled oninput="onInputChanged()" onchange="onInputChanged()">
                          </div>
                        </div>
                      </div>
                      <div class="form-group full">
                        <label>Gốc neo khi Resize chiều rộng (Width)</label>
                        <div class="anchor-tabs">
                          <div class="anchor-btn" id="anchor_left" onclick="selectAnchor('left')">Mép Trái</div>
                          <div class="anchor-btn active" id="anchor_center" onclick="selectAnchor('center')">Tâm Giữa</div>
                          <div class="anchor-btn" id="anchor_right" onclick="selectAnchor('right')">Mép Phải</div>
                        </div>
                      </div>
                    </div>

                    <!-- Lu Ban 52.2cm Feng Shui Assessment Card -->
                    <div class="luban-card" id="luban_card">
                      <div class="luban-header">
                        <div class="luban-title-wrap">
                          <span>Thước Lỗ Ban 52.2cm (Thông Thủy)</span>
                        </div>
                        <span class="luban-badge neutral" id="luban_badge">--</span>
                      </div>
                      <div class="luban-detail" id="luban_detail">Nhập chiều rộng (W mm) để tra cứu cung Lỗ Ban.</div>
                      <div class="luban-suggest-row">
                        <span class="luban-suggest-label">Mốc đẹp gần nhất:</span>
                        <div class="luban-pills" id="luban_pills"></div>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Right column: live 2D Preview -->
                <div class="preview-container">
                  <div class="preview-header">
                    <span>Mô phỏng 2D</span>
                    <span id="preview_tag" style="color: var(--primary-color); font-weight:700;">DOOR</span>
                  </div>
                  <div class="preview-svg-wrap" id="svg_container">
                    <!-- Dynamic SVG rendered here -->
                  </div>
                  <div class="preview-footer">Khung nhôm kính Profile</div>
                </div>
              </div>

              <div class="actions">
                <button type="button" class="btn-secondary" onclick="closeForm()">Đóng</button>
                <button type="button" class="btn-move" onclick="startMoveTool()" title="Di chuyển cửa realtime dọc theo phương tường (kéo chuột hoặc gõ số mm + Enter)">Di chuyển</button>
                <button type="button" class="btn-sync" onclick="doSyncOpening()" title="Tự động đo kích thước lỗ mở tường xung quanh và chuẩn hóa cửa khớp 100%">Chuẩn hóa</button>
                <button type="button" class="btn-primary" onclick="doResize()">Resize ngay</button>
              </div>

              <script>
                var currentType = 'door';
                var currentAnchor = 'center';
                var initialWidth = 0;

                /* ==========================================================
                   THƯỚC LỖ BAN 52.2CM (THÔNG THỦY / CỬA ĐI & CỬA SỔ)
                   Chu kỳ 522mm chia làm 8 cung lớn (65.25mm/cung)
                   Mỗi cung lớn chia làm 5 cung nhỏ (13.05mm/cung nhỏ)
                   ========================================================== */
                const LUBAN_522_CIRC = 522.0;
                const LUBAN_8_CUNG = [
                  {
                    name: 'Quý Nhân',
                    isGood: true,
                    desc: 'Cung Quý Nhân (Cát): Gia cảnh hưng vượng, bạn bè trung tín, sự nghiệp phát đạt, con cái thông minh.',
                    subcung: ['Quyền lộc', 'Trung tín', 'Tác quan', 'Phát đạt', 'Thông minh']
                  },
                  {
                    name: 'Hiểm Họa',
                    isGood: false,
                    desc: 'Cung Hiểm Họa (Hung): Dễ tán tài hao của, gia đạo bất hòa, gặp nhiều rủi ro trắc trở.',
                    subcung: ['Tán tài', 'Tử biệt', 'Thoái đinh', 'Thất hiếu', 'Tai họa']
                  },
                  {
                    name: 'Thiên Tai',
                    isGood: false,
                    desc: 'Cung Thiên Tai (Hung): Đề phòng bệnh tật, đau ốm, mất mát tiền của, gia đạo bất an.',
                    subcung: ['Hoàn cảnh', 'Ôn dịch', 'Lao sái', 'Quả phụ', 'Đạo tặc']
                  },
                  {
                    name: 'Thiên Tài',
                    isGood: true,
                    desc: 'Cung Thiên Tài (Cát): Đắc tài đắc lộc, thi cử đỗ đạt, gia đạo an vui, may mắn bất ngờ.',
                    subcung: ['Thi thơ', 'Văn học', 'Thanh quý', 'Tác lộc', 'Thiên lộc']
                  },
                  {
                    name: 'Phúc Lộc',
                    isGood: true,
                    desc: 'Cung Phúc Lộc (Cát): Tài lộc dồi dào, phúc thọ vẹn toàn, tấn tài tấn bảo, vạn sự hanh thông.',
                    subcung: ['Trí tôn', 'Tử tôn', 'Bác học', 'Phúc lộc', 'Tấn tài']
                  },
                  {
                    name: 'Cô Độc',
                    isGood: false,
                    desc: 'Cung Cô Độc (Hung): Hao tài tốn của, gia đạo ly tán, công danh sự nghiệp lận đận.',
                    subcung: ['Bạc mệnh', 'Đoản thọ', 'Hao tài', 'Ly tán', 'Vô tự']
                  },
                  {
                    name: 'Thiên Tặc',
                    isGood: false,
                    desc: 'Cung Thiên Tặc (Hung): Đề phòng kiện tụng tranh chấp, trộm cắp, thị phi bất ngờ.',
                    subcung: ['Phòng bệnh', 'Chiêu ôn', 'Hình ngục', 'Quan tụng', 'Thất tài']
                  },
                  {
                    name: 'Tể Tướng',
                    isGood: true,
                    desc: 'Cung Tể Tướng (Cát): Đại tài đại lợi, quý nhân phù trợ, gia tăng của cải điền sản, con cái hiếu thảo.',
                    subcung: ['Đại tài', 'Thi thơ', 'Hoạch tài', 'Hiếu tử', 'Quý nhân']
                  }
                ];

                function getFrameSize() {
                  return 50.0; // 50mm frame width on each side (total 100mm)
                }

                function evaluateLuBan522(w_clear_mm) {
                  if (!w_clear_mm || w_clear_mm <= 0) return null;
                  const mod = ((w_clear_mm % LUBAN_522_CIRC) + LUBAN_522_CIRC) % LUBAN_522_CIRC;
                  const cungLen = LUBAN_522_CIRC / 8.0; // 65.25mm
                  const subLen = cungLen / 5.0; // 13.05mm

                  const cungIdx = Math.min(Math.floor(mod / cungLen), 7);
                  const subIdx = Math.min(Math.floor((mod % cungLen) / subLen), 4);

                  const cung = LUBAN_8_CUNG[cungIdx];
                  const subName = cung.subcung[subIdx];

                  return {
                    clearWidth: w_clear_mm,
                    cungName: cung.name,
                    subName: subName,
                    isGood: cung.isGood,
                    desc: cung.desc
                  };
                }

                function getNearestGoodClearWidths(w_clear_mm) {
                  if (!w_clear_mm || w_clear_mm <= 0) return [];
                  const frame2 = getFrameSize() * 2; // 100mm
                  const candidates = [];

                  // Tìm các mốc thông thủy đẹp nhỏ hơn (bước 10mm)
                  for (let cw = Math.floor(w_clear_mm / 10) * 10 - 10; cw >= Math.max(200, w_clear_mm - 400); cw -= 10) {
                    const res = evaluateLuBan522(cw);
                    if (res && res.isGood) {
                      candidates.push({ clearWidth: cw, overallWidth: cw + frame2, cungName: res.cungName, subName: res.subName, diff: cw - w_clear_mm });
                      if (candidates.length >= 2) break;
                    }
                  }

                  // Tìm các mốc thông thủy đẹp lớn hơn (bước 10mm)
                  const upCandidates = [];
                  for (let cw = Math.ceil(w_clear_mm / 10) * 10 + 10; cw <= w_clear_mm + 400; cw += 10) {
                    const res = evaluateLuBan522(cw);
                    if (res && res.isGood) {
                      upCandidates.push({ clearWidth: cw, overallWidth: cw + frame2, cungName: res.cungName, subName: res.subName, diff: cw - w_clear_mm });
                      if (upCandidates.length >= 2) break;
                    }
                  }

                  const combined = candidates.concat(upCandidates);
                  const unique = [];
                  const map = {};
                  for (const c of combined) {
                    if (!map[c.clearWidth]) {
                      map[c.clearWidth] = true;
                      unique.push(c);
                    }
                  }
                  unique.sort((a, b) => Math.abs(a.diff) - Math.abs(b.diff));
                  return unique.slice(0, 3);
                }

                function updateLuBanInfo() {
                  const wOverall = Number(document.getElementById('width').value) || 0;
                  const frame2 = getFrameSize() * 2; // 100mm
                  const wClear = Math.max(wOverall - frame2, 0); // Kích thước thông thủy = tổng các cánh

                  const card = document.getElementById('luban_card');
                  const badge = document.getElementById('luban_badge');
                  const detail = document.getElementById('luban_detail');
                  const pillsWrap = document.getElementById('luban_pills');

                  if (!wOverall || wOverall <= frame2) {
                    card.className = 'luban-card';
                    badge.className = 'luban-badge neutral';
                    badge.innerText = '--';
                    detail.innerText = 'Nhập chiều rộng (W mm) để tra cứu cung Thước Lỗ Ban 52.2cm theo thông thủy (lọt lòng cánh).';
                    pillsWrap.innerHTML = '<span style="font-size:10px; color:#94a3b8;">Chưa có dữ liệu</span>';
                    return;
                  }

                  const res = evaluateLuBan522(wClear);
                  if (!res) return;

                  const clearInfoText = 'Thông thủy (Tổng cánh): <b>' + wClear + ' mm</b> (Phủ bì: ' + wOverall + ' mm). ';

                  if (res.isGood) {
                    card.className = 'luban-card is-good';
                    badge.className = 'luban-badge good';
                    badge.innerText = 'CUNG TỐT (' + res.cungName + ' - ' + res.subName + ')';
                    detail.innerHTML = clearInfoText + res.desc;
                  } else {
                    card.className = 'luban-card is-bad';
                    badge.className = 'luban-badge bad';
                    badge.innerText = 'CUNG XẤU (' + res.cungName + ' - ' + res.subName + ')';
                    detail.innerHTML = clearInfoText + res.desc;
                  }

                  // Render suggestion pills
                  const nearest = getNearestGoodClearWidths(wClear);
                  if (nearest.length > 0) {
                    let pillsHtml = '';
                    nearest.forEach(function(item) {
                      const sign = item.diff > 0 ? '+' : '';
                      pillsHtml += '<button type="button" class="luban-pill" title="Bấm để áp dụng Phủ bì ' + item.overallWidth + 'mm (Lọt lòng ' + item.clearWidth + 'mm)" onclick="applyLubanWidth(' + item.overallWidth + ')">' +
                                   'Phủ bì ' + item.overallWidth + ' mm (Thông thủy ' + item.clearWidth + ' - ' + item.cungName + ' ' + sign + item.diff + 'mm)</button>';
                    });
                    pillsWrap.innerHTML = pillsHtml;
                  } else {
                    pillsWrap.innerHTML = '<span style="font-size:10px; color:#94a3b8;">Không có mốc gần</span>';
                  }
                }

                function applyLubanWidth(newOverallW) {
                  document.getElementById('width').value = newOverallW;
                  onInputChanged();
                }

                document.addEventListener('DOMContentLoaded', () => {
                  renderPreview();
                  updateLuBanInfo();
                });

                function selectAnchor(a) {
                  currentAnchor = a;
                  document.getElementById('anchor_left').classList.toggle('active', a === 'left');
                  document.getElementById('anchor_center').classList.toggle('active', a === 'center');
                  document.getElementById('anchor_right').classList.toggle('active', a === 'right');
                  if (window.sketchup && sketchup.set_anchor) {
                    sketchup.set_anchor(a);
                  }
                }

                function setAnchor(a) {
                  currentAnchor = a;
                  document.getElementById('anchor_left').classList.toggle('active', a === 'left');
                  document.getElementById('anchor_center').classList.toggle('active', a === 'center');
                  document.getElementById('anchor_right').classList.toggle('active', a === 'right');
                }

                function showStatus(msg, type) {
                  const box = document.getElementById('status_box');
                  box.className = 'status-box ' + (type || 'info');
                  box.innerText = msg;
                }

                function updateCalculatedHeight() {
                  const topCote = Number(document.getElementById('top_cote').value) || 2200;
                  const isDoor = (currentType === 'door');
                  const offsetEl = document.getElementById('z_offset');
                  const offset = isDoor ? 0 : (Number(offsetEl.value) || 0);
                  const h = isDoor ? topCote : Math.max(topCote - offset, 100);
                  document.getElementById('height_display').value = h;
                  return h;
                }

                function onHeightParamsChanged() {
                  updateCalculatedHeight();
                  onInputChanged();
                }

                function selectType(t) {
                  currentType = t;
                  document.getElementById('btn_door').classList.toggle('active', t === 'door');
                  document.getElementById('btn_window').classList.toggle('active', t === 'window');

                  var offsetEl = document.getElementById('z_offset');
                  if (t === 'door') {
                    offsetEl.value = 0;
                    offsetEl.disabled = true;
                  } else {
                    offsetEl.disabled = false;
                    if (!offsetEl.value || Number(offsetEl.value) <= 0) {
                      offsetEl.value = 900;
                    }
                  }
                  updateCalculatedHeight();
                  renderPreview();
                  updateLuBanInfo();
                }

                function toggleFixInput(dir) {
                  var chk = document.getElementById('has_fix_' + dir);
                  var fieldId = (dir === 'top' || dir === 'bottom') ? ('fix_' + dir + '_height') : ('fix_' + dir + '_width');
                  var inputEl = document.getElementById(fieldId);
                  if (inputEl) {
                    inputEl.disabled = !chk.checked;
                  }
                }

                function setPickedData(data) {
                  initialWidth = Number(data.width) || 0;
                  if (window.sketchup && sketchup.set_show_anchors) {
                    sketchup.set_show_anchors(false);
                  }

                  selectType(data.type || 'door');
                  document.getElementById('width').value = data.width || '';

                  const isWindow = (data.type === 'window');
                  const rawH = Number(data.height) || (isWindow ? 1300 : 2200);
                  const rawOffset = isWindow ? (Number(data.z_offset) || 900) : 0;

                  var offsetEl = document.getElementById('z_offset');
                  if (isWindow) {
                    offsetEl.value = rawOffset;
                    offsetEl.disabled = false;
                    document.getElementById('top_cote').value = rawOffset + rawH;
                  } else {
                    offsetEl.value = 0;
                    offsetEl.disabled = true;
                    document.getElementById('top_cote').value = rawH;
                  }

                  updateCalculatedHeight();

                  document.getElementById('panel_count').value = data.panel_count || 1;

                  // 4 Fix options
                  document.getElementById('has_fix_top').checked = !!data.has_fix_top;
                  document.getElementById('fix_top_height').value = data.fix_top_height || 350;
                  document.getElementById('fix_top_height').disabled = !data.has_fix_top;

                  document.getElementById('has_fix_bottom').checked = !!data.has_fix_bottom;
                  document.getElementById('fix_bottom_height').value = data.fix_bottom_height || 400;
                  document.getElementById('fix_bottom_height').disabled = !data.has_fix_bottom;

                  document.getElementById('has_fix_left').checked = !!data.has_fix_left;
                  document.getElementById('fix_left_width').value = data.fix_left_width || 300;
                  document.getElementById('fix_left_width').disabled = !data.has_fix_left;

                  document.getElementById('has_fix_right').checked = !!data.has_fix_right;
                  document.getElementById('fix_right_width').value = data.fix_right_width || 300;
                  document.getElementById('fix_right_width').disabled = !data.has_fix_right;

                  const label = document.getElementById('target_label');
                  if (data.count > 1) {
                    label.innerText = data.name + ' (Hàng loạt)';
                  } else {
                    label.innerText = data.name;
                  }

                  renderPreview();
                  updateLuBanInfo();
                }

                function onInputChanged() {
                  var w = Number(document.getElementById('width').value) || 0;
                  var isModified = (initialWidth > 0 && Math.abs(w - initialWidth) > 0.5);
                  if (window.sketchup && sketchup.set_show_anchors) {
                    sketchup.set_show_anchors(isModified);
                  }
                  renderPreview();
                  updateLuBanInfo();
                }

                function renderPreview() {
                  var isDoor = currentType === 'door';
                  var wInput = Number(document.getElementById('width').value) || 900;
                  var hInput = updateCalculatedHeight() || 2200;
                  var panels = Math.min(Math.max(Number(document.getElementById('panel_count').value) || 1, 1), 10);

                  var hasFixT = document.getElementById('has_fix_top').checked;
                  var hasFixB = document.getElementById('has_fix_bottom').checked;
                  var hasFixL = document.getElementById('has_fix_left').checked;
                  var hasFixR = document.getElementById('has_fix_right').checked;

                  var fixTopH_val = hasFixT ? (Number(document.getElementById('fix_top_height').value) || 350) : 0;
                  var fixBotH_val = hasFixB ? (Number(document.getElementById('fix_bottom_height').value) || 400) : 0;
                  var fixLeftW_val = hasFixL ? (Number(document.getElementById('fix_left_width').value) || 300) : 0;
                  var fixRightW_val = hasFixR ? (Number(document.getElementById('fix_right_width').value) || 300) : 0;

                  var fixTags = [];
                  if (hasFixT) fixTags.push('T');
                  if (hasFixB) fixTags.push('B');
                  if (hasFixL) fixTags.push('L');
                  if (hasFixR) fixTags.push('R');

                  var tag = (isDoor ? 'DOOR' : 'WINDOW') + ' (' + panels + 'P' + (fixTags.length > 0 ? ' + FIX ' + fixTags.join('/') : '') + ')';
                  document.getElementById('preview_tag').innerText = tag;

                  // Proportional Geometric Layout Engine (Tỷ lệ thẩm mỹ cố định)
                  var frameT = 4;
                  var basePanelW = (panels === 1) ? 90 : (panels === 2 ? 65 : (panels === 3 ? 50 : 45));
                  var actW = basePanelW * panels;
                  var fixLW = hasFixL ? 38 : 0;
                  var fixRW = hasFixR ? 38 : 0;

                  var W = fixLW + actW + fixRW + 2 * frameT + (hasFixL ? frameT : 0) + (hasFixR ? frameT : 0);
                  var H = 160;

                  var fixTH = hasFixT ? 30 : 0;
                  var fixBH = hasFixB ? 30 : 0;

                  var ox = 10;
                  var oy = 10;

                  var svg = '<svg width="100%" height="100%" viewBox="0 0 ' + (W + 20) + ' ' + (H + 20) + '" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet">';
                  svg += '<defs>';
                  svg += '  <linearGradient id="glassGrad" x1="0" y1="0" x2="1" y2="1">';
                  svg += '    <stop offset="0%" stop-color="#e0f2fe" stop-opacity="0.9"/>';
                  svg += '    <stop offset="100%" stop-color="#bae6fd" stop-opacity="0.7"/>';
                  svg += '  </linearGradient>';
                  svg += '  <linearGradient id="fixGlassGrad" x1="0" y1="0" x2="1" y2="1">';
                  svg += '    <stop offset="0%" stop-color="#dbeafe" stop-opacity="0.95"/>';
                  svg += '    <stop offset="100%" stop-color="#bfdbfe" stop-opacity="0.75"/>';
                  svg += '  </linearGradient>';
                  svg += '</defs>';

                  // 1. Outer Frame Box
                  if (isDoor && !hasFixB) {
                    // Door without bottom fix (U-shaped opening at bottom for active area)
                    svg += '<path d="M' + ox + ' ' + (oy + H) + ' V' + oy + ' H' + (ox + W) + ' V' + (oy + H) + ' H' + (ox + W - frameT) + ' V' + (oy + frameT) + ' H' + (ox + frameT) + ' V' + (oy + H) + ' Z" fill="#334155" />';
                  } else {
                    // Closed 4-sided outer frame
                    svg += '<rect x="' + ox + '" y="' + oy + '" width="' + W + '" height="' + H + '" fill="#334155" rx="1" />';
                    svg += '<rect x="' + (ox + frameT) + '" y="' + (oy + frameT) + '" width="' + (W - 2 * frameT) + '" height="' + (H - 2 * frameT) + '" fill="#f8fafc" />';
                  }

                  // 2. Active Leaf Coordinate Bounds
                  var actX0 = ox + frameT + (hasFixL ? (fixLW + frameT) : 0);
                  var actY0 = oy + frameT + (hasFixT ? (fixTH + frameT) : 0);
                  var actY1 = hasFixB ? (oy + H - frameT - fixBH - frameT) : (isDoor ? (oy + H) : (oy + H - frameT));
                  var actH = Math.max(actY1 - actY0, 20);

                  // 3. Draw Fix Panels
                  // Left Fix
                  if (hasFixL) {
                    var lfx = ox + frameT;
                    var lfy = oy + frameT;
                    var lfh = (oy + H - frameT) - lfy;

                    // Fix Glass
                    svg += '<rect x="' + lfx + '" y="' + lfy + '" width="' + fixLW + '" height="' + Math.max(lfh, 1) + '" fill="url(#fixGlassGrad)" stroke="#3b82f6" stroke-width="0.5" />';
                    // Mullion Bar
                    svg += '<rect x="' + (lfx + fixLW) + '" y="' + lfy + '" width="' + frameT + '" height="' + Math.max(lfh, 1) + '" fill="#334155" />';
                    // Bottom Sill Bar (always present under side fixes)
                    svg += '<rect x="' + lfx + '" y="' + (oy + H - frameT) + '" width="' + (fixLW + frameT) + '" height="' + frameT + '" fill="#334155" />';
                  }

                  // Right Fix
                  if (hasFixR) {
                    var rfx = ox + W - frameT - fixRW;
                    var rfy = oy + frameT;
                    var rfh = (oy + H - frameT) - rfy;

                    // Mullion Bar
                    svg += '<rect x="' + (rfx - frameT) + '" y="' + rfy + '" width="' + frameT + '" height="' + Math.max(rfh, 1) + '" fill="#334155" />';
                    // Fix Glass
                    svg += '<rect x="' + rfx + '" y="' + rfy + '" width="' + fixRW + '" height="' + Math.max(rfh, 1) + '" fill="url(#fixGlassGrad)" stroke="#3b82f6" stroke-width="0.5" />';
                    // Bottom Sill Bar (always present under side fixes)
                    svg += '<rect x="' + (rfx - frameT) + '" y="' + (oy + H - frameT) + '" width="' + (fixRW + frameT) + '" height="' + frameT + '" fill="#334155" />';
                  }

                  // Top Fix (Transom)
                  if (hasFixT) {
                    var tfy = oy + frameT;
                    // Glass
                    svg += '<rect x="' + actX0 + '" y="' + tfy + '" width="' + actW + '" height="' + fixTH + '" fill="url(#fixGlassGrad)" stroke="#3b82f6" stroke-width="0.5" />';
                    // Transom Bar
                    svg += '<rect x="' + actX0 + '" y="' + (tfy + fixTH) + '" width="' + actW + '" height="' + frameT + '" fill="#334155" />';
                  }

                  // Bottom Fix (Sill Transom)
                  if (hasFixB) {
                    var bfy = oy + H - frameT - fixBH;
                    // Transom Bar
                    svg += '<rect x="' + actX0 + '" y="' + (bfy - frameT) + '" width="' + actW + '" height="' + frameT + '" fill="#334155" />';
                    // Glass
                    svg += '<rect x="' + actX0 + '" y="' + bfy + '" width="' + actW + '" height="' + fixBH + '" fill="url(#fixGlassGrad)" stroke="#3b82f6" stroke-width="0.5" />';
                  }

                  // 4. Draw Active Door / Window Leaves
                  var singleLeafW = actW / panels;
                  for (var i = 0; i < panels; i++) {
                    var lx = actX0 + i * singleLeafW;
                    var ly = actY0;
                    var lw = singleLeafW;
                    var lh = actH;
                    var lFrame = 3;

                    // Leaf Frame Outer
                    svg += '<rect x="' + (lx + 0.5) + '" y="' + ly + '" width="' + (lw - 1) + '" height="' + lh + '" fill="#475569" stroke="#1e293b" stroke-width="0.75" rx="0.5" />';
                    // Leaf Glass
                    svg += '<rect x="' + (lx + lFrame) + '" y="' + (ly + lFrame) + '" width="' + Math.max(lw - 2 * lFrame - 1, 1) + '" height="' + Math.max(lh - 2 * lFrame, 1) + '" fill="url(#glassGrad)" stroke="#0284c7" stroke-width="0.5" />';

                    // Architectural Handle Indicator (Tay nắm cửa)
                    if (isDoor) {
                      var hx = (panels === 1 || i % 2 === 0) ? (lx + lw - 6) : (lx + 6);
                      var hy = ly + lh * 0.5 - 8;
                      svg += '<rect x="' + hx + '" y="' + hy + '" width="2" height="16" fill="#cbd5e1" stroke="#0f172a" stroke-width="0.5" rx="1" />';
                    }
                  }

                  svg += '</svg>';
                  document.getElementById('svg_container').innerHTML = svg;
                }

                function activatePicker() {
                  if (window.sketchup) {
                    sketchup.activate_picker();
                  }
                }

                function doResize() {
                  const w = Number(document.getElementById('width').value);
                  const topCote = Number(document.getElementById('top_cote').value);
                  const isDoor = (currentType === 'door');
                  const offset = isDoor ? 0 : (Number(document.getElementById('z_offset').value) || 0);
                  const h = isDoor ? topCote : Math.max(topCote - offset, 100);
                  const p = Number(document.getElementById('panel_count').value);

                  const fixTop = document.getElementById('has_fix_top').checked;
                  const fixTopH = Number(document.getElementById('fix_top_height').value) || 350;
                  const fixBot = document.getElementById('has_fix_bottom').checked;
                  const fixBotH = Number(document.getElementById('fix_bottom_height').value) || 400;
                  const fixLeft = document.getElementById('has_fix_left').checked;
                  const fixLeftW = Number(document.getElementById('fix_left_width').value) || 300;
                  const fixRight = document.getElementById('has_fix_right').checked;
                  const fixRightW = Number(document.getElementById('fix_right_width').value) || 300;

                  if (!w || !topCote || w <= 0 || topCote <= 0) {
                    showStatus('Vui lòng nhập kích thước Rộng và Cote trên cửa hợp lệ.', 'error');
                    return;
                  }

                  const data = {
                    type: currentType,
                    width: w,
                    height: h,
                    z_offset: offset,
                    panel_count: p,
                    has_fix_top: fixTop,
                    fix_top_height: fixTopH,
                    has_fix_bottom: fixBot,
                    fix_bottom_height: fixBotH,
                    has_fix_left: fixLeft,
                    fix_left_width: fixLeftW,
                    has_fix_right: fixRight,
                    fix_right_width: fixRightW,
                    anchor: currentAnchor
                  };

                  if (window.sketchup) {
                    sketchup.do_resize(data);
                  }
                }

                function doSyncOpening() {
                  if (window.sketchup && sketchup.sync_with_opening) {
                    sketchup.sync_with_opening();
                  }
                }

                function startMoveTool() {
                  if (window.sketchup && sketchup.start_move_tool) {
                    sketchup.start_move_tool();
                  }
                }

                function closeForm() {
                  if (window.sketchup) {
                    sketchup.close_dialog();
                  }
                }
              </script>
            </body>
            </html>
          HTML
        end
      end
    end
  end
end
