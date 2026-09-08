# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # HtmlDialog for Replace Door/Window feature
    # Dialog remains open and non-blocking while allowing continuous interaction/replacement
    module ReplaceDialog
      # Tool to pick single door/window or drag selection window to replace multiple
      class ReplacePickerTool
        attr_accessor :type, :panel_count, :has_fix_top

        def initialize(type, panel_count, has_fix_top, dialog)
          @type = type
          @panel_count = panel_count
          @has_fix_top = has_fix_top
          @dialog = dialog
          @hover_target = nil
          @highlight_color = Sketchup::Color.new(5, 150, 105, 255) # Emerald green (#059669)
          @fill_color = Sketchup::Color.new(5, 150, 105, 60)      # Semi-transparent fill
          
          # Drag selection box state
          @dragging = false
          @drag_start = nil
          @drag_current = nil
          @drag_box_color = Sketchup::Color.new(5, 150, 105, 255)
          @drag_fill_color = Sketchup::Color.new(5, 150, 105, 40)
        end

        def activate
          label = @type == :door ? 'Cửa đi (Door)' : 'Cửa sổ (Window)'
          Sketchup.status_text = "[NAUQ CAD TO 3D] Click vào 1 cửa HOẶC Kéo quét vùng chọn để Replace #{label}..."
        end

        def deactivate(view)
          ReplaceDialog.active_picker_tool = nil if ReplaceDialog.active_picker_tool == self
          @hover_target = nil
          @dragging = false
          view.invalidate
        end

        def onMouseMove(flags, x, y, view)
          if @drag_start
            @drag_current = Geom::Point3d.new(x, y, 0)
            if (@drag_start.x - x).abs > 3 || (@drag_start.y - y).abs > 3
              @dragging = true
              @hover_target = nil
            end
            view.invalidate
          else
            ph = view.pick_helper
            ph.do_pick(x, y)
            
            target = find_valid_target(ph)
            if target != @hover_target
              @hover_target = target
              view.invalidate
            end
          end
        end

        def onLButtonDown(flags, x, y, view)
          @drag_start = Geom::Point3d.new(x, y, 0)
          @drag_current = @drag_start
          @dragging = false
          view.invalidate
        end

        def onLButtonUp(flags, x, y, view)
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

            replace_entities_in_rect(view, min_x, min_y, max_x, max_y)
          else
            # Single click replace
            if @hover_target && @hover_target.valid?
              target = @hover_target
              @hover_target = nil
              view.invalidate
              ReplaceDialog.execute_replace(target, @type, @panel_count, @has_fix_top)
            end
          end
          view.invalidate
        end

        def onSetCursor
          UI.set_cursor(0)
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

            # Draw transparent fill
            view.drawing_color = @drag_fill_color
            view.draw2d(GL_POLYGON, [p1, p2, p3, p4])

            # Draw dashed outline
            view.drawing_color = @drag_box_color
            view.line_width = 2
            view.line_stipple = '- - '
            view.draw2d(GL_LINE_LOOP, [p1, p2, p3, p4])
            return
          end

          # 2. Draw 3D bounding box highlight for hover target
          return unless @hover_target && @hover_target.valid?

          bbox = @hover_target.bounds
          return if bbox.empty?

          pts = (0..7).map { |i| bbox.corner(i) }

          edges = [
            [0, 1], [1, 3], [3, 2], [2, 0], # bottom
            [4, 5], [5, 7], [7, 6], [6, 4], # top
            [0, 4], [1, 5], [2, 6], [3, 7]  # pillars
          ]

          view.drawing_color = @highlight_color
          view.line_width = 3
          view.line_stipple = ''

          edges.each do |p1_idx, p2_idx|
            view.draw(GL_LINES, pts[p1_idx], pts[p2_idx])
          end

          view.drawing_color = @fill_color
          faces = [
            [0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4],
            [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]
          ]
          faces.each do |f|
            view.draw(GL_POLYGON, f.map { |i| pts[i] })
          end
        end

        private

        # Find and replace all matching entities whose bounding boxes intersect screen rectangle
        def replace_entities_in_rect(view, min_x, min_y, max_x, max_y)
          model = Sketchup.active_model
          return unless model

          targets = []
          container_name = (@type == :door ? 'NAUQ_DOORS' : 'NAUQ_WINDOWS')
          container = model.active_entities.find { |e| e.is_a?(Sketchup::Group) && e.name == container_name }

          search_pool = []
          if container && container.valid?
            container.entities.each do |child|
              search_pool << child if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
            end
          end

          # Also check active entities
          model.active_entities.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            search_pool << e if matches_selected_type?(e)
          end

          search_pool.uniq.each do |ent|
            next unless ent && ent.valid? && matches_selected_type?(ent)
            bbox = ent.bounds
            next if bbox.empty?

            # Check center point
            center_pt = view.screen_coords(bbox.center)
            # screen_coords in Sketchup returns Point3d where z is depth (z >= 0 is in front of camera)
            if center_pt.z >= 0 && center_pt.x >= min_x && center_pt.x <= max_x && center_pt.y >= min_y && center_pt.y <= max_y
              targets << ent
              next
            end

            # Check 8 corner points of bounding box
            corners = (0..7).map { |i| view.screen_coords(bbox.corner(i)) }
            any_corner_in = corners.any? do |s|
              s.z >= 0 && s.x >= min_x && s.x <= max_x && s.y >= min_y && s.y <= max_y
            end
            targets << ent if any_corner_in
          end

          targets.uniq!

          if targets.empty?
            label = @type == :door ? 'Cửa đi' : 'Cửa sổ'
            ReplaceDialog.update_status("⚠️ Không tìm thấy #{label} nào trong vùng quét chọn.", 'error')
            return
          end

          ReplaceDialog.execute_replace_list(targets, @type, @panel_count, @has_fix_top)
        end

        # Find valid Door or Window based STRICTLY on @type
        def find_valid_target(pick_helper)
          path = pick_helper.path_at(0) || []
          
          # 1. First, search along the hierarchy (bottom-up) for an exact match of selected type
          candidate = path.reverse.find do |ent|
            next false unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
            matches_selected_type?(ent)
          end
          return candidate if candidate

          # 2. If nothing matched directly, check if best_picked or its parents match
          target = pick_helper.best_picked
          if target.nil? || (!target.is_a?(Sketchup::Group) && !target.is_a?(Sketchup::ComponentInstance))
            target = path.reverse.find { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          end

          if target && (target.is_a?(Sketchup::Group) || target.is_a?(Sketchup::ComponentInstance))
            name = (target.name || '').upcase
            # Exclude walls, slabs, cad drawing
            return nil if name.include?('NAUQ_WALL') || name.include?('NAUQ_SLAB') || name.include?('NAUQ_CAD')
            return target if matches_selected_type?(target)
          end

          nil
        end

        def matches_selected_type?(entity)
          return false unless entity.respond_to?(:get_attribute)
          
          # Check entity explicit type
          is_window = is_entity_window?(entity)
          is_door   = is_entity_door?(entity)

          if @type == :door
            # MUST be a door and MUST NOT be a window
            return is_door && !is_window
          elsif @type == :window
            # MUST be a window and MUST NOT be a door
            return is_window && !is_door
          end

          false
        end

        def is_entity_window?(entity)
          # 1. Attribute dictionary checks
          return true if Attribute.tagged_as?(entity, 'window')
          return true if entity.attribute_dictionary('NAUQ_WINDOW')
          return true if entity.get_attribute('NAUQ_CAD_TO_3D', 'type') == 'window'

          # 2. Entity name checks
          name = (entity.name || '').upcase
          return true if name.start_with?('WINDOW') || name.include?('CUA SO') || name.include?('TT_WIN')

          # 3. Component Definition name checks
          if entity.respond_to?(:definition) && entity.definition
            def_name = (entity.definition.name || '').upcase
            return true if def_name.include?('WIN_LEAF') || def_name.start_with?('WINDOW')
          end

          # 4. Parent container name
          parent_name = entity.parent.respond_to?(:name) ? (entity.parent.name || '').upcase : ''
          return true if parent_name == 'NAUQ_WINDOWS'

          false
        end

        def is_entity_door?(entity)
          # 1. Attribute dictionary checks
          return true if Attribute.tagged_as?(entity, 'door')
          return true if entity.attribute_dictionary('TT_Door') || entity.attribute_dictionary('NAUQ_DOOR')
          return true if entity.get_attribute('NAUQ_CAD_TO_3D', 'type') == 'door'

          # 2. Entity name checks
          name = (entity.name || '').upcase
          return true if name.start_with?('DOOR') || name.include?('CUA DI') || name.include?('TT_DOOR')

          # 3. Component Definition name checks
          if entity.respond_to?(:definition) && entity.definition
            def_name = (entity.definition.name || '').upcase
            return true if def_name.include?('DOOR_LEAF') || def_name.start_with?('DOOR')
          end

          # 4. Parent container name (only if not a window)
          parent_name = entity.parent.respond_to?(:name) ? (entity.parent.name || '').upcase : ''
          return true if parent_name == 'NAUQ_DOORS'

          false
        end
      end

      class << self
        def show
          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            return
          end

          @dialog = UI::HtmlDialog.new(
            dialog_title: 'Replace Door / Window',
            preferences_key: 'NAUQ_CAD_TO_3D_Replace_Dialog',
            scrollable: true,
            resizable: true,
            width: 660,
            height: 480,
            left: 250,
            top: 180,
            style: UI::HtmlDialog::STYLE_DIALOG
          )

          # Reset active tool when dialog closes
          @dialog.set_on_closed do
            stop_picker_tool
          end

          @dialog.set_html(html_content)
          attach_callbacks(@dialog)
          @dialog.show
        end

        def close
          stop_picker_tool
          @dialog&.close
        end

        def stop_picker_tool
          model = Sketchup.active_model
          if @active_picker_tool
            @active_picker_tool = nil
            model.select_tool(nil) if model
          elsif model && model.tools.active_tool_name == 'NAUQ::CadTo3D::ReplaceDialog::ReplacePickerTool'
            model.select_tool(nil)
          end
        end

        def active_picker_tool
          @active_picker_tool
        end

        def active_picker_tool=(tool)
          @active_picker_tool = tool
        end

        def update_status(msg, status_type = 'info')
          return unless @dialog && @dialog.visible?

          @dialog.execute_script("showStatus(#{msg.to_s.to_json}, #{status_type.to_json});")
        end

        # Core logic: replace a given door/window target (Public for ReplacePickerTool)
        def execute_replace(target, type, panel_count, has_fix_top)
          model = Sketchup.active_model
          return unless model && target && target.valid?

          # Read dimensions from old entity attributes
          old_width_mm = read_dimension(target, 'width') || 900.0
          old_height_mm = read_dimension(target, 'height') || (type == :door ? 2200.0 : 1200.0)

          # Preserve transform of old entity
          old_transform = target.transformation

          # Execute replacement within an operation
          model.start_operation('NAUQ Replace Door/Window', true)
          begin
            parent_entities = target.parent.respond_to?(:entities) ? target.parent.entities : model.active_entities
            parent_entities.erase_entities(target)

            # Build replacement
            glass_h_mm = Config.get(:glass_height) || 350.0

            if type == :door
              frame_s_mm = Config.get(:frame_size) || 50.0
              fix_h_mm = has_fix_top ? (glass_h_mm > 0 ? glass_h_mm : 350.0) : 0.0

              # If door is too short for fix transom, clamp or disable fix_top
              min_needed_h = (2 * frame_s_mm) + fix_h_mm + 100.0
              effective_has_fix = has_fix_top
              if has_fix_top && old_height_mm < min_needed_h
                # Adjust fix module height if height is tight
                fix_h_mm = [old_height_mm - (2 * frame_s_mm) - 500.0, 100.0].max
                if old_height_mm <= (2 * frame_s_mm) + 200.0
                  effective_has_fix = false
                end
              end

              new_group = DoorGenerator.generate(
                parent: parent_entities,
                name: "DOOR_REPLACED_#{panel_count}P",
                width: old_width_mm.mm,
                height: old_height_mm.mm,
                panel_count: panel_count,
                has_fix_top: effective_has_fix,
                fix_module_height: fix_h_mm.mm
              )
              new_group.transform!(old_transform)
              Attribute.tag(new_group, 'door', width: old_width_mm, height: old_height_mm, panel_count: panel_count, has_fix_top: effective_has_fix)
            else
              # Window build
              frame_w = (Config.get(:frame_size) || 50.0).mm
              w_len = old_width_mm.to_f.mm
              h_len = old_height_mm.to_f.mm
              active_w = [w_len - (2.0 * frame_w), 100.mm].max

              if has_fix_top && glass_h_mm > 0
                leaf_h_mm = [old_height_mm - glass_h_mm - (2.0 * frame_w.to_mm), 100.0].max
                leaf_h_len = leaf_h_mm.to_f.mm
                active_h = [leaf_h_len - frame_w, 100.mm].max
              else
                leaf_h_mm = old_height_mm
                leaf_h_len = h_len
                active_h = [h_len - (2.0 * frame_w), 100.mm].max
              end

              leaf_w = active_w / panel_count.to_f
              leaf_h = active_h

              win_assembly = parent_entities.add_group
              win_assembly.name = "WINDOW_REPLACED_#{panel_count}P"

              frame_mat = MaterialLoader.get_material(model, 'kimloaidengoaithat') rescue nil
              glass_mat = MaterialLoader.get_material(model, 'kinhh6') rescue nil

              FrameBuilder.build_frame(
                win_assembly, w_len, h_len,
                is_window: true,
                has_fix_top: has_fix_top,
                leaf_height: has_fix_top ? leaf_h_len : nil,
                material: frame_mat
              )

              definition = LeafBuilder.get_or_create_leaf_definition(model, leaf_w, leaf_h, frame_mat, 'TT_WIN_LEAF')
              panel_count.times do |index|
                inst = LeafBuilder.create_leaf_instance(win_assembly, definition, index, leaf_w, x_offset: 0.mm, frame_width: frame_w, material: frame_mat)
                inst.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, frame_w)))
              end

              glass_group = GlassBuilder.build_glass(win_assembly, active_w, active_h, x_offset: 0.mm, frame_width: frame_w, material: glass_mat)
              glass_group.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, frame_w))) if glass_group

              if has_fix_top && glass_h_mm > 0
                transom_glass = GlassBuilder.build_glass(win_assembly, active_w, glass_h_mm.mm, x_offset: 0.mm, frame_width: frame_w, material: glass_mat)
                transom_glass.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, leaf_h_len + frame_w))) if transom_glass
              end

              win_assembly.transform!(old_transform)
              Attribute.tag(win_assembly, 'window', width: old_width_mm, height: old_height_mm, leaf_count: panel_count, has_fix_top: has_fix_top)
            end

            model.commit_operation
            msg = "Đã thay thế #{type == :door ? 'Cửa đi' : 'Cửa sổ'} thành công (#{panel_count} cánh#{has_fix_top ? ', có ô fix' : ''})."
            Logger.info(msg)
            update_status("✅ #{msg}", 'success')
          rescue StandardError => e
            model.abort_operation
            Logger.error("Lỗi khi thay thế #{type}: #{e.message}")
            update_status("❌ Lỗi: #{e.message}", 'error')
          end
        end

        # Replace ALL doors or windows currently in model according to settings
        def execute_replace_all(type, panel_count, has_fix_top)
          model = Sketchup.active_model
          return unless model

          # Collect all target entities of chosen type
          targets = []
          container_name = (type == :door ? 'NAUQ_DOORS' : 'NAUQ_WINDOWS')
          container = model.active_entities.find { |e| e.is_a?(Sketchup::Group) && e.name == container_name }

          if container && container.valid?
            container.entities.each do |child|
              if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
                targets << child
              end
            end
          else
            # Search all top-level / active entities
            model.active_entities.each do |ent|
              next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
              if type == :door
                targets << ent if Attribute.tagged_as?(ent, 'door') || (ent.name || '').upcase.start_with?('DOOR')
              else
                targets << ent if Attribute.tagged_as?(ent, 'window') || (ent.name || '').upcase.start_with?('WINDOW')
              end
            end
          end

          if targets.empty?
            update_status("⚠️ Không tìm thấy #{type == :door ? 'Cửa đi' : 'Cửa sổ'} nào trong model để thay thế.", 'error')
            return
          end

          model.start_operation("NAUQ Replace All #{type.to_s.capitalize}", true)
          success_count = 0
          begin
            targets.each do |t|
              next unless t && t.valid?
              old_width_mm = read_dimension(t, 'width') || 900.0
              old_height_mm = read_dimension(t, 'height') || (type == :door ? 2200.0 : 1200.0)
              target_panel_count = read_panel_count(t, type)
              old_transform = t.transformation
              parent_entities = t.parent.respond_to?(:entities) ? t.parent.entities : model.active_entities

              t.erase!

              glass_h_mm = Config.get(:glass_height) || 350.0

              if type == :door
                frame_s_mm = Config.get(:frame_size) || 50.0
                fix_h_mm = has_fix_top ? (glass_h_mm > 0 ? glass_h_mm : 350.0) : 0.0

                min_needed_h = (2 * frame_s_mm) + fix_h_mm + 100.0
                effective_has_fix = has_fix_top
                if has_fix_top && old_height_mm < min_needed_h
                  fix_h_mm = [old_height_mm - (2 * frame_s_mm) - 500.0, 100.0].max
                  effective_has_fix = false if old_height_mm <= (2 * frame_s_mm) + 200.0
                end

                new_group = DoorGenerator.generate(
                  parent: parent_entities,
                  name: "DOOR_REPLACED_#{target_panel_count}P",
                  width: old_width_mm.mm,
                  height: old_height_mm.mm,
                  panel_count: target_panel_count,
                  has_fix_top: effective_has_fix,
                  fix_module_height: fix_h_mm.mm
                )
                new_group.transform!(old_transform)
                Attribute.tag(new_group, 'door', width: old_width_mm, height: old_height_mm, panel_count: target_panel_count, has_fix_top: effective_has_fix)
              else
                frame_w = (Config.get(:frame_size) || 50.0).mm
                w_len = old_width_mm.to_f.mm
                h_len = old_height_mm.to_f.mm
                active_w = [w_len - (2.0 * frame_w), 100.mm].max

                if has_fix_top && glass_h_mm > 0
                  leaf_h_mm = [old_height_mm - glass_h_mm - (2.0 * frame_w.to_mm), 100.0].max
                  leaf_h_len = leaf_h_mm.to_f.mm
                  active_h = [leaf_h_len - frame_w, 100.mm].max
                else
                  leaf_h_mm = old_height_mm
                  leaf_h_len = h_len
                  active_h = [h_len - (2.0 * frame_w), 100.mm].max
                end

                leaf_w = active_w / target_panel_count.to_f
                leaf_h = active_h

                win_assembly = parent_entities.add_group
                win_assembly.name = "WINDOW_REPLACED_#{target_panel_count}P"

                frame_mat = MaterialLoader.get_material(model, 'kimloaidengoaithat') rescue nil
                glass_mat = MaterialLoader.get_material(model, 'kinhh6') rescue nil

                FrameBuilder.build_frame(
                  win_assembly, w_len, h_len,
                  is_window: true,
                  has_fix_top: has_fix_top,
                  leaf_height: has_fix_top ? leaf_h_len : nil,
                  material: frame_mat
                )

                definition = LeafBuilder.get_or_create_leaf_definition(model, leaf_w, leaf_h, frame_mat, 'TT_WIN_LEAF')
                target_panel_count.times do |index|
                  inst = LeafBuilder.create_leaf_instance(win_assembly, definition, index, leaf_w, x_offset: 0.mm, frame_width: frame_w, material: frame_mat)
                  inst.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, frame_w)))
                end

                glass_group = GlassBuilder.build_glass(win_assembly, active_w, active_h, x_offset: 0.mm, frame_width: frame_w, material: glass_mat)
                glass_group.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, frame_w))) if glass_group

                if has_fix_top && glass_h_mm > 0
                  transom_glass = GlassBuilder.build_glass(win_assembly, active_w, glass_h_mm.mm, x_offset: 0.mm, frame_width: frame_w, material: glass_mat)
                  transom_glass.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, leaf_h_len + frame_w))) if transom_glass
                end

                win_assembly.transform!(old_transform)
                Attribute.tag(win_assembly, 'window', width: old_width_mm, height: old_height_mm, leaf_count: target_panel_count, has_fix_top: has_fix_top)
              end

              success_count += 1
            end

            model.commit_operation
            fix_status_text = has_fix_top ? 'có ô fix' : 'không có ô fix'
            msg = "Đã Replace ALL thành công #{success_count} #{type == :door ? 'Cửa đi' : 'Cửa sổ'} sang dạng #{fix_status_text} (giữ nguyên số cánh từng cửa)."
            Logger.info(msg)
            update_status("✅ #{msg}", 'success')
          rescue StandardError => e
            model.abort_operation
            Logger.error("Lỗi khi Replace ALL: #{e.message}")
            update_status("❌ Lỗi Replace ALL: #{e.message}", 'error')
          end
        end

        # Replace a list of selected entities (from drag box selection)
        def execute_replace_list(targets, type, panel_count, has_fix_top)
          model = Sketchup.active_model
          return unless model && targets && !targets.empty?

          model.start_operation("NAUQ Replace Multiple #{type.to_s.capitalize}", true)
          success_count = 0
          begin
            targets.each do |t|
              next unless t && t.valid?
              old_width_mm = read_dimension(t, 'width') || 900.0
              old_height_mm = read_dimension(t, 'height') || (type == :door ? 2200.0 : 1200.0)
              target_panel_count = read_panel_count(t, type)
              old_transform = t.transformation
              parent_entities = t.parent.respond_to?(:entities) ? t.parent.entities : model.active_entities

              t.erase!

              glass_h_mm = Config.get(:glass_height) || 350.0

              if type == :door
                frame_s_mm = Config.get(:frame_size) || 50.0
                fix_h_mm = has_fix_top ? (glass_h_mm > 0 ? glass_h_mm : 350.0) : 0.0

                min_needed_h = (2 * frame_s_mm) + fix_h_mm + 100.0
                effective_has_fix = has_fix_top
                if has_fix_top && old_height_mm < min_needed_h
                  fix_h_mm = [old_height_mm - (2 * frame_s_mm) - 500.0, 100.0].max
                  effective_has_fix = false if old_height_mm <= (2 * frame_s_mm) + 200.0
                end

                new_group = DoorGenerator.generate(
                  parent: parent_entities,
                  name: "DOOR_REPLACED_#{target_panel_count}P",
                  width: old_width_mm.mm,
                  height: old_height_mm.mm,
                  panel_count: target_panel_count,
                  has_fix_top: effective_has_fix,
                  fix_module_height: fix_h_mm.mm
                )
                new_group.transform!(old_transform)
                Attribute.tag(new_group, 'door', width: old_width_mm, height: old_height_mm, panel_count: target_panel_count, has_fix_top: effective_has_fix)
              else
                frame_w = (Config.get(:frame_size) || 50.0).mm
                w_len = old_width_mm.to_f.mm
                h_len = old_height_mm.to_f.mm
                active_w = [w_len - (2.0 * frame_w), 100.mm].max

                if has_fix_top && glass_h_mm > 0
                  leaf_h_mm = [old_height_mm - glass_h_mm - (2.0 * frame_w.to_mm), 100.0].max
                  leaf_h_len = leaf_h_mm.to_f.mm
                  active_h = [leaf_h_len - frame_w, 100.mm].max
                else
                  leaf_h_mm = old_height_mm
                  leaf_h_len = h_len
                  active_h = [h_len - (2.0 * frame_w), 100.mm].max
                end

                leaf_w = active_w / target_panel_count.to_f
                leaf_h = active_h

                win_assembly = parent_entities.add_group
                win_assembly.name = "WINDOW_REPLACED_#{target_panel_count}P"

                frame_mat = MaterialLoader.get_material(model, 'kimloaidengoaithat') rescue nil
                glass_mat = MaterialLoader.get_material(model, 'kinhh6') rescue nil

                FrameBuilder.build_frame(
                  win_assembly, w_len, h_len,
                  is_window: true,
                  has_fix_top: has_fix_top,
                  leaf_height: has_fix_top ? leaf_h_len : nil,
                  material: frame_mat
                )

                definition = LeafBuilder.get_or_create_leaf_definition(model, leaf_w, leaf_h, frame_mat, 'TT_WIN_LEAF')
                target_panel_count.times do |index|
                  inst = LeafBuilder.create_leaf_instance(win_assembly, definition, index, leaf_w, x_offset: 0.mm, frame_width: frame_w, material: frame_mat)
                  inst.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, frame_w)))
                end

                glass_group = GlassBuilder.build_glass(win_assembly, active_w, active_h, x_offset: 0.mm, frame_width: frame_w, material: glass_mat)
                glass_group.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, frame_w))) if glass_group

                if has_fix_top && glass_h_mm > 0
                  transom_glass = GlassBuilder.build_glass(win_assembly, active_w, glass_h_mm.mm, x_offset: 0.mm, frame_width: frame_w, material: glass_mat)
                  transom_glass.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, leaf_h_len + frame_w))) if transom_glass
                end

                win_assembly.transform!(old_transform)
                Attribute.tag(win_assembly, 'window', width: old_width_mm, height: old_height_mm, leaf_count: target_panel_count, has_fix_top: has_fix_top)
              end

              success_count += 1
            end

            model.commit_operation
            fix_status_text = has_fix_top ? 'có ô fix' : 'không có ô fix'
            msg = "Đã Replace thành công #{success_count} #{type == :door ? 'Cửa đi' : 'Cửa sổ'} trong vùng chọn sang dạng #{fix_status_text}."
            Logger.info(msg)
            update_status("✅ #{msg}", 'success')
          rescue StandardError => e
            model.abort_operation
            Logger.error("Lỗi khi Replace Multiple: #{e.message}")
            update_status("❌ Lỗi: #{e.message}", 'error')
          end
        end

        private

        def attach_callbacks(dialog)
          dialog.add_action_callback('do_replace') do |_ctx, data_hash|
            next unless data_hash.is_a?(Hash)

            type = data_hash['type'].to_s == 'window' ? :window : :door
            panel_count = [data_hash['panel_count'].to_i, 1].max
            has_fix_top = data_hash['has_fix_top'] == true || data_hash['has_fix_top'] == 'true'

            model = Sketchup.active_model
            next unless model

            tool = ReplacePickerTool.new(type, panel_count, has_fix_top, dialog)
            @active_picker_tool = tool
            model.select_tool(tool)

            label = type == :door ? 'Cửa đi (Door)' : 'Cửa sổ (Window)'
            update_status("👉 Đang tìm #{label} (#{panel_count} cánh#{has_fix_top ? ', có ô fix' : ''}): Hover và Click vào cửa để thay thế...", 'waiting')
          end

          dialog.add_action_callback('do_replace_all') do |_ctx, data_hash|
            next unless data_hash.is_a?(Hash)

            type = data_hash['type'].to_s == 'window' ? :window : :door
            panel_count = [data_hash['panel_count'].to_i, 1].max
            has_fix_top = data_hash['has_fix_top'] == true || data_hash['has_fix_top'] == 'true'

            execute_replace_all(type, panel_count, has_fix_top)
          end

          dialog.add_action_callback('update_params') do |_ctx, data_hash|
            next unless data_hash.is_a?(Hash)

            type = data_hash['type'].to_s == 'window' ? :window : :door
            panel_count = [data_hash['panel_count'].to_i, 1].max
            has_fix_top = data_hash['has_fix_top'] == true || data_hash['has_fix_top'] == 'true'

            model = Sketchup.active_model
            next unless model

            if @active_picker_tool
              @active_picker_tool.type = type
              @active_picker_tool.panel_count = panel_count
              @active_picker_tool.has_fix_top = has_fix_top

              label = type == :door ? 'Cửa đi (Door)' : 'Cửa sổ (Window)'
              update_status("👉 Đang tìm #{label} (#{panel_count} cánh#{has_fix_top ? ', có ô fix' : ''}): Hover và Click vào cửa để thay thế...", 'waiting')
              model.active_view.invalidate
            end
          end

          dialog.add_action_callback('close_dialog') do |_ctx|
            close
          end
        end

        # Read width/height from various attribute dictionaries, fallback to bounds
        def read_dimension(entity, key)
          # Check width_mm / height_mm first
          val = Attribute.get(entity, "#{key}_mm") ||
                Attribute.get(entity, key) ||
                entity.get_attribute('TT_Door', "#{key}_mm") ||
                entity.get_attribute('NAUQ_DOOR', key) ||
                entity.get_attribute('NAUQ_WINDOW', key)

          if val
            val_f = val.to_f
            # If attribute was stored in inches (< 150 for door height/width), convert to mm
            if key == 'height' && val_f > 0 && val_f < 150.0
              val_f = val_f.inch.to_mm
            elsif key == 'width' && val_f > 0 && val_f < 100.0
              val_f = val_f.inch.to_mm
            end
            return val_f if val_f > 100.0
          end

          # Fallback: check TT_Door attributes (stored in inches by default in TT_Door dictionary)
          tt_val = entity.get_attribute('TT_Door', key)
          if tt_val
            tt_f = tt_val.to_f
            # If TT_Door stored inches, convert
            tt_mm = tt_f < 150.0 ? tt_f.inch.to_mm : tt_f
            return tt_mm if tt_mm > 100.0
          end

          # Fallback: calculate from bounding box of entity
          if entity.respond_to?(:bounds) && !entity.bounds.empty?
            if key == 'height'
              h_mm = entity.bounds.height.to_mm
              return h_mm if h_mm > 100.0
            elsif key == 'width'
              # Width could be max of width or depth in bounding box (depending on rotation)
              w_mm = [entity.bounds.width.to_mm, entity.bounds.depth.to_mm].max
              return w_mm if w_mm > 100.0
            end
          end

          nil
        end

        # Read panel count from various attributes, entity name, or child components
        def read_panel_count(entity, type)
          # 1. Direct attribute
          cnt = Attribute.get(entity, 'panel_count') ||
                Attribute.get(entity, 'leaf_count') ||
                entity.get_attribute('TT_Door', 'panel_count') ||
                entity.get_attribute('NAUQ_DOOR', 'panel_count') ||
                entity.get_attribute('NAUQ_WINDOW', 'leaf_count')
          return cnt.to_i if cnt && cnt.to_i >= 1

          # 2. Extract from group/component name (e.g. DOOR_2P, WINDOW_REPLACED_4P, etc.)
          name = (entity.name || '').upcase
          if name =~ /(\d+)\s*P/
            return $1.to_i if $1.to_i >= 1
          end

          # 3. Count child leaf instances inside entity
          if entity.respond_to?(:entities)
            leaf_count = entity.entities.count do |e|
              next false unless e.is_a?(Sketchup::ComponentInstance)
              def_name = (e.definition.name || '').upcase
              def_name.include?('LEAF') || def_name.include?('CANH')
            end
            return leaf_count if leaf_count >= 1
          end

          1
        end

        def html_content
          <<~HTML
            <!DOCTYPE html>
            <html lang="vi">
            <head>
              <meta charset="UTF-8">
              <title>Replace Door / Window</title>
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
                  font-size: 12px;
                  line-height: 1.4;
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
                  padding-bottom: 8px;
                  margin-bottom: 12px;
                  border-bottom: 1px solid var(--border-color);
                }

                .header h2 {
                  font-size: 14px;
                  font-weight: 700;
                  color: var(--text-main);
                }

                .header p {
                  font-size: 11px;
                  color: var(--text-muted);
                  margin-top: 1px;
                }

                .main-layout {
                  display: grid;
                  grid-template-columns: 1fr 240px;
                  gap: 12px;
                }

                .section {
                  background: var(--card-bg);
                  border: 1px solid var(--border-color);
                  border-radius: 6px;
                  padding: 10px 12px;
                  margin-bottom: 10px;
                }

                .section-title {
                  font-size: 11px;
                  font-weight: 700;
                  color: var(--text-main);
                  text-transform: uppercase;
                  letter-spacing: 0.4px;
                  margin-bottom: 8px;
                  padding-bottom: 4px;
                  border-bottom: 1px solid #f1f5f9;
                }

                .form-grid {
                  display: grid;
                  grid-template-columns: 1fr 1fr;
                  gap: 8px;
                }

                .form-group {
                  display: flex;
                  flex-direction: column;
                  gap: 3px;
                }

                .form-group.full {
                  grid-column: span 2;
                }

                .checkbox-row {
                  display: flex;
                  align-items: center;
                  gap: 8px;
                  margin-top: 4px;
                }

                label {
                  font-size: 11px;
                  font-weight: 600;
                  color: var(--text-muted);
                }

                input[type="number"], select {
                  background: #ffffff;
                  border: 1px solid var(--border-color);
                  color: var(--text-main);
                  border-radius: 4px;
                  padding: 5px 8px;
                  font-size: 12px;
                  outline: none;
                  transition: border-color 0.2s;
                }

                input[type="number"]:focus, select:focus {
                  border-color: var(--primary-color);
                }

                input[type="checkbox"] {
                  width: 15px;
                  height: 15px;
                  cursor: pointer;
                  accent-color: var(--primary-color);
                }

                /* Type selector buttons */
                .type-selector {
                  display: grid;
                  grid-template-columns: 1fr 1fr;
                  gap: 6px;
                  margin-bottom: 4px;
                }

                .type-btn {
                  padding: 7px 10px;
                  text-align: center;
                  font-size: 12px;
                  font-weight: 600;
                  cursor: pointer;
                  background: #f8fafc;
                  color: var(--text-muted);
                  border: 1px solid var(--border-color);
                  border-radius: 4px;
                  transition: all 0.2s;
                  user-select: none;
                }

                .type-btn.active {
                  background: var(--primary-color);
                  color: #ffffff;
                  border-color: var(--primary-color);
                }

                .type-btn:hover:not(.active) {
                  background: #f1f5f9;
                  color: var(--text-main);
                }

                .status-box {
                  display: none;
                  margin-bottom: 10px;
                  padding: 6px 10px;
                  border-radius: 4px;
                  font-size: 11px;
                  line-height: 1.4;
                  font-weight: 500;
                  border: 1px solid transparent;
                }

                .status-box.info, .status-box.waiting {
                  display: block;
                  background-color: #eff6ff;
                  color: #1e40af;
                  border-color: #bfdbfe;
                }

                .status-box.success {
                  display: block;
                  background-color: #f0fdf4;
                  color: #166534;
                  border-color: #bbf7d0;
                }

                .status-box.error {
                  display: block;
                  background-color: #fef2f2;
                  color: #991b1b;
                  border-color: #fecaca;
                }

                /* Preview Box */
                .preview-container {
                  background: var(--card-bg);
                  border: 1px solid var(--border-color);
                  border-radius: 6px;
                  padding: 10px;
                  display: flex;
                  flex-direction: column;
                  align-items: center;
                  justify-content: space-between;
                  height: 250px;
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
                }

                .preview-svg-wrap {
                  flex: 1;
                  width: 100%;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  background: #f8fafc;
                  border: 1px dashed #cbd5e1;
                  border-radius: 4px;
                  overflow: hidden;
                  padding: 6px;
                }

                .preview-footer {
                  margin-top: 6px;
                  font-size: 10px;
                  font-weight: 600;
                  color: var(--text-muted);
                }

                .actions {
                  display: flex;
                  justify-content: flex-end;
                  gap: 8px;
                  margin-top: 12px;
                }

                button {
                  padding: 6px 14px;
                  border-radius: 4px;
                  border: 1px solid transparent;
                  font-size: 12px;
                  font-weight: 600;
                  cursor: pointer;
                  transition: all 0.15s;
                }

                .btn-primary {
                  background-color: var(--primary-color);
                  color: #ffffff;
                }

                .btn-primary:hover {
                  background-color: var(--primary-hover);
                }

                .btn-secondary {
                  background-color: var(--btn-secondary);
                  color: var(--text-main);
                  border-color: var(--border-color);
                }

                .btn-outline {
                  background-color: transparent;
                  color: var(--primary-color);
                  border: 1px solid var(--primary-color);
                }

                .btn-outline:hover {
                  background-color: #ecfdf5;
                }
              </style>
            </head>
            <body>
              <div class="header">
                <h2>Replace Door / Window</h2>
                <p>Click chọn 1 cửa hoặc Kéo chuột quét vùng chọn nhiều cửa để thay thế</p>
              </div>

              <div id="status_msg" class="status-box"></div>

              <div class="main-layout">
                <!-- Left: Form Controls -->
                <div>
                  <div class="section">
                    <div class="section-title">Loại cửa</div>
                    <div class="type-selector">
                      <div class="type-btn active" id="btn_door" onclick="selectType('door')">🚪 Cửa đi (Door)</div>
                      <div class="type-btn" id="btn_window" onclick="selectType('window')">🪟 Cửa sổ (Window)</div>
                    </div>
                  </div>

                  <div class="section">
                    <div class="section-title">Cấu hình thông số</div>
                    <div class="form-grid">
                      <div class="form-group full">
                        <label>Số cánh (Panel Count)</label>
                        <input type="number" id="panel_count" value="1" min="1" max="6" step="1" oninput="onInputChanged()" onchange="onInputChanged()">
                      </div>
                      <div class="form-group full">
                        <div class="checkbox-row">
                          <input type="checkbox" id="has_fix_top" onchange="onInputChanged()">
                          <label for="has_fix_top" style="color: var(--text-main); cursor: pointer;">Ô fix kính phía trên</label>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Right: Realtime Preview -->
                <div class="preview-container">
                  <div class="preview-header">
                    <span>Mô phỏng 2D</span>
                    <span id="preview_tag" style="color: var(--primary-color); font-weight:700;">DOOR (1P)</span>
                  </div>
                  <div class="preview-svg-wrap" id="svg_container">
                    <!-- Dynamic SVG injected here -->
                  </div>
                  <div class="preview-footer" id="preview_dimensions">Khung nhôm kính Profile V20</div>
                </div>
              </div>

              <div class="actions">
                <button type="button" class="btn-secondary" onclick="closeForm()">Đóng</button>
                <button type="button" class="btn-primary" onclick="doReplace()">REPLACE</button>
              </div>

              <script>
                var selectedType = 'door';

                document.addEventListener('DOMContentLoaded', () => {
                  renderPreview();
                });

                function selectType(type) {
                  selectedType = type;
                  document.getElementById('btn_door').classList.toggle('active', type === 'door');
                  document.getElementById('btn_window').classList.toggle('active', type === 'window');
                  onInputChanged();
                }

                function onInputChanged() {
                  renderPreview();
                  sendParamsUpdate();
                }

                function getFormData() {
                  return {
                    type: selectedType,
                    panel_count: Number(document.getElementById('panel_count').value) || 1,
                    has_fix_top: document.getElementById('has_fix_top').checked
                  };
                }

                function sendParamsUpdate() {
                  var data = getFormData();
                  if (window.sketchup && sketchup.update_params) {
                    sketchup.update_params(data);
                  }
                }

                function doReplace() {
                  var data = getFormData();
                  if (window.sketchup) {
                    sketchup.do_replace(data);
                  }
                }

                function showStatus(msg, type) {
                  var el = document.getElementById('status_msg');
                  if (!el) return;
                  el.className = 'status-box ' + (type || 'info');
                  el.innerHTML = msg;
                }

                function closeForm() {
                  if (window.sketchup) {
                    sketchup.close_dialog();
                  }
                }

                // Render dynamic SVG Preview of Door/Window
                function renderPreview() {
                  var data = getFormData();
                  var isDoor = data.type === 'door';
                  var panels = Math.min(Math.max(data.panel_count, 1), 6);
                  var hasFix = !!data.has_fix_top;

                  var tag = (isDoor ? 'DOOR' : 'WINDOW') + ' (' + panels + 'P' + (hasFix ? ' + FIX' : '') + ')';
                  document.getElementById('preview_tag').innerText = tag;

                  var W = 160;
                  var H = 180;
                  var frameT = 6;
                  var transomH = hasFix ? 34 : 0;
                  var mainH = H - (hasFix ? (transomH + frameT) : 0);

                  var svg = '<svg width="100%" height="100%" viewBox="0 0 ' + (W + 20) + ' ' + (H + 20) + '" xmlns="http://www.w3.org/2000/svg">';
                  svg += '<defs>';
                  svg += '  <linearGradient id="glassGrad" x1="0" y1="0" x2="1" y2="1">';
                  svg += '    <stop offset="0%" stop-color="#e0f2fe" stop-opacity="0.8"/>';
                  svg += '    <stop offset="100%" stop-color="#bae6fd" stop-opacity="0.6"/>';
                  svg += '  </linearGradient>';
                  svg += '</defs>';

                  var ox = 10;
                  var oy = 10;

                  // 1. Outer Frame
                  if (isDoor) {
                    // U-shape frame (top, left, right)
                    svg += '<path d="M' + ox + ' ' + (oy + H) + ' V' + oy + ' H' + (ox + W) + ' V' + (oy + H) + ' H' + (ox + W - frameT) + ' V' + (oy + frameT) + ' H' + (ox + frameT) + ' V' + (oy + H) + ' Z" fill="#334155" />';
                  } else {
                    // 4-side closed frame
                    svg += '<rect x="' + ox + '" y="' + oy + '" width="' + W + '" height="' + H + '" fill="#334155" rx="1" />';
                    svg += '<rect x="' + (ox + frameT) + '" y="' + (oy + frameT) + '" width="' + (W - 2 * frameT) + '" height="' + (H - 2 * frameT) + '" fill="#f8fafc" />';
                  }

                  // 2. Fix Transom Top
                  if (hasFix) {
                    var fixY = oy + frameT;
                    var fixW = W - 2 * frameT;
                    // Fix Glass
                    svg += '<rect x="' + (ox + frameT) + '" y="' + fixY + '" width="' + fixW + '" height="' + transomH + '" fill="url(#glassGrad)" stroke="#0284c7" stroke-width="0.5" />';
                    // Transom Bar
                    svg += '<rect x="' + (ox + frameT) + '" y="' + (fixY + transomH) + '" width="' + fixW + '" height="' + frameT + '" fill="#334155" />';
                  }

                  // 3. Leaves (Panels)
                  var leafStartY = hasFix ? (oy + frameT + transomH + frameT) : (oy + frameT);
                  var leafTotalH = isDoor ? (H - (hasFix ? (transomH + 2 * frameT) : frameT)) : (H - (hasFix ? (transomH + 3 * frameT) : 2 * frameT));
                  var leafTotalW = W - 2 * frameT;
                  var singleLeafW = leafTotalW / panels;

                  for (var i = 0; i < panels; i++) {
                    var lx = ox + frameT + i * singleLeafW;
                    var ly = leafStartY;
                    var lw = singleLeafW;
                    var lh = leafTotalH;
                    var lFrame = 4;

                    // Leaf Frame
                    svg += '<rect x="' + (lx + 0.5) + '" y="' + ly + '" width="' + (lw - 1) + '" height="' + lh + '" fill="#475569" stroke="#1e293b" stroke-width="0.75" rx="1" />';
                    // Leaf Glass
                    svg += '<rect x="' + (lx + lFrame) + '" y="' + (ly + lFrame) + '" width="' + Math.max(lw - 2 * lFrame - 1, 2) + '" height="' + (lh - 2 * lFrame) + '" fill="url(#glassGrad)" stroke="#0284c7" stroke-width="0.5" />';
                  }

                  svg += '</svg>';
                  document.getElementById('svg_container').innerHTML = svg;
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
