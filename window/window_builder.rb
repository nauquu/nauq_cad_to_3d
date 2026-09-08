# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Generates 3D windows in NAUQ_WINDOWS group container
    # All window geometry is intentionally built in the ROOT model context
    # (model.entities), never inside the user's active group/component.
    # rubocop:disable SketchupSuggestions/ModelEntities
    module WindowBuilder
      DEFAULT_FIX_BOTTOM_HEIGHT_MM = 400.0

      class << self
        # Procedurally generate a complete 3D window assembly
        # @param options [Hash]
        # @return [Sketchup::Group]
        def generate(options = {})
          model = Sketchup.active_model

          width = options[:width] ? (options[:width].is_a?(Length) ? options[:width] : options[:width].to_f.mm) : 900.mm
          height = options[:height] ? (options[:height].is_a?(Length) ? options[:height] : options[:height].to_f.mm) : 1200.mm
          panel_count = [options[:panel_count] || 1, 1].max
          x_offset = options[:x_offset] ? (options[:x_offset].is_a?(Length) ? options[:x_offset] : options[:x_offset].to_f.mm) : 0.mm
          win_name = (options[:name] || "WINDOW_#{panel_count}P").to_s

          parent = options[:parent] || model.active_entities
          target_entities = parent.respond_to?(:entities) ? parent.entities : parent

          layout = FrameBuilder.calculate_layout(width, height, options.merge(is_window: true, x_offset: x_offset))

          active_width = layout[:active_width]
          active_height = layout[:active_height]

          is_sliding = !!options[:is_sliding]
          overlap = is_sliding ? (LeafBuilder::LEAF_FRAME_WIDTH || 71.0.mm) : 0.0.mm

          if is_sliding && panel_count == 2
            leaf_width = (active_width + overlap) / 2.0
            leaf_specs = [
              { x: layout[:active_x0], y_shift: -20.0.mm, w: leaf_width },
              { x: layout[:active_x0] + active_width - leaf_width, y_shift: 20.0.mm, w: leaf_width }
            ]
          elsif is_sliding && panel_count == 4
            leaf_width = (active_width + 2 * overlap) / 4.0
            leaf_specs = [
              { x: layout[:active_x0], y_shift: -20.0.mm, w: leaf_width },
              { x: layout[:active_x0] + leaf_width - overlap, y_shift: 20.0.mm, w: leaf_width },
              { x: layout[:active_x0] + 2 * leaf_width - overlap, y_shift: 20.0.mm, w: leaf_width },
              { x: layout[:active_x0] + active_width - leaf_width, y_shift: -20.0.mm, w: leaf_width }
            ]
          else
            leaf_width = active_width / panel_count.to_f
            leaf_specs = panel_count.times.map do |idx|
              { x: layout[:active_x0] + (idx * leaf_width), y_shift: 0.mm, w: leaf_width }
            end
          end

          leaf_height = active_height

          frame_mat = options[:frame_material] || (MaterialLoader.get_material(model, 'kimloaidengoaithat') rescue nil)
          glass_mat = options[:glass_material] || (MaterialLoader.get_material(model, 'kinhh6') rescue nil)

          win_assembly = target_entities.add_group
          win_assembly.name = win_name

          # 1. Build FRAME
          FrameBuilder.build_frame(
            win_assembly,
            width,
            height,
            options.merge(material: frame_mat, is_window: true, x_offset: x_offset)
          )

          # 2. Get or create LEAF Definition (embeds aluminum frame + GLASS group inside LEAF)
          definition = LeafBuilder.get_or_create_leaf_definition(
            model,
            leaf_width,
            leaf_height,
            frame_mat,
            glass_mat,
            'TT_WIN_LEAF'
          )

          # 3. Create LEAF Instances (each instance contains frame + its own embedded glass)
          leaf_specs.each_with_index do |spec, index|
            inst = LeafBuilder.create_leaf_instance(
              win_assembly,
              definition,
              index,
              spec[:w],
              exact_x: spec[:x],
              material: frame_mat
            )
            t_z = Geom::Transformation.translation(Geom::Vector3d.new(0, spec[:y_shift], layout[:active_z0]))
            inst.transform!(t_z)
          end

          # 4. Build Fix Glasses if present (Top Transom / Fix Panels)
          GlassBuilder.build_layout_glasses(
            win_assembly,
            layout,
            glass_mat,
            include_active: false
          )

          win_assembly
        end

        # Build all windows based on detected openings
        # @param openings_data [Array<Hash>] list of window openings
        # @param windows_group [Sketchup::Group, nil] NAUQ_WINDOWS group
        # @param cad_group [Sketchup::Group, Sketchup::ComponentInstance, nil] source CAD item
        def build_windows(openings_data, windows_group = nil, cad_group = nil)
          win_openings = openings_data.select { |op| op[:type] == :window }
          return if win_openings.empty?

          model = Sketchup.active_model
          cad_id = cad_group ? (cad_group.respond_to?(:persistent_id) ? cad_group.persistent_id.to_s : cad_group.object_id.to_s) : nil
          floor_name = cad_group && cad_group.respond_to?(:name) && !cad_group.name.empty? ? cad_group.name : "Floor_#{cad_id || Time.now.to_i}"

          model.start_operation('NAUQ Build 3D Windows', true)

          # Remove previous window geometry for this CAD source without touching doors.
          grouping_mode = Config.get(:door_grouping).to_i
          if cad_id
            if grouping_mode == 2
              existing = model.entities.grep(Sketchup::Group).find do |g|
                g.valid? && g.name == "WINDOWS_#{floor_name}"
              end
              existing.erase! if existing&.valid?
            elsif grouping_mode == 1
              shared = model.entities.grep(Sketchup::Group).find do |g|
                g.valid? && g.name == "OPENINGS_#{floor_name}"
              end
              if shared
                shared.entities.to_a.each do |entity|
                  if entity.valid? && Attribute.get(entity, 'type').to_s == 'window' && Attribute.get(entity, 'source_cad_id').to_s == cad_id.to_s
                    entity.erase!
                  end
                end
              end
            else
              model.entities.to_a.each do |entity|
                if entity.valid? && entity.respond_to?(:entities) && Attribute.get(entity, 'type').to_s == 'window' && Attribute.get(entity, 'source_cad_id').to_s == cad_id.to_s
                  entity.erase!
                end
              end
            end
          end

          # Resolve grouping mode from Settings.
          # 2 = separate Door/Window groups, 1 = one shared group, 0 = no parent group.
          grouping_mode = Config.get(:door_grouping).to_i
          model.selection.clear rescue nil
          windows_group = case grouping_mode
                          when 2
                            model.entities.add_group.tap do |g|
                              g.name = "WINDOWS_#{floor_name}"
                              Attribute.tag(g, 'window_floor', source_cad_id: cad_id)
                            end
                          when 1
                            existing = model.entities.grep(Sketchup::Group).find { |g| g.valid? && g.name == "OPENINGS_#{floor_name}" }
                            existing || model.entities.add_group.tap do |g|
                              g.name = "OPENINGS_#{floor_name}"
                              Attribute.tag(g, 'opening_floor', source_cad_id: cad_id)
                            end
                          else
                            model.entities
                          end

          max_win_w_mm = Config.get(:window_max_width) || 900.0
          frame_w = (Config.get(:frame_size) || 50.0).mm

          built_count = 0
          target_entities = windows_group.respond_to?(:entities) ? windows_group.entities : windows_group

          win_openings.each do |op|
            begin
              w_mm = op[:width_mm] || 900.0
              h_mm = op[:height_mm] || 1200.0
              pos = op[:position] || Geom::Point3d.new(0, 0, 0)
              dir = op[:direction]

              w_len = w_mm.to_f.mm
              h_len = h_mm.to_f.mm
              active_w = [w_len - (2.0 * frame_w), 100.mm].max

              has_transom = (Config.get(:glass_height) || 0.0) > 0
              glass_h_mm = Config.get(:glass_height) || 350.0

              z_off_mm = (op[:z_offset_mm] || Config.get(:window_offset) || 900.0).to_f
              has_bottom_fix = z_off_mm < 200.0
              fix_bot_h_mm = has_bottom_fix ? DEFAULT_FIX_BOTTOM_HEIGHT_MM : 0.0

              panel_count = [(active_w.to_mm / max_win_w_mm).ceil, 1].max

              # Window assembly group using unified generate
              win_assembly = generate(
                parent: target_entities,
                name: "WINDOW_#{op[:id]}",
                width: w_len,
                height: h_len,
                panel_count: panel_count,
                has_fix_top: has_transom,
                fix_top_height: glass_h_mm.to_f.mm,
                has_fix_bottom: has_bottom_fix,
                fix_bottom_height: fix_bot_h_mm.mm
              )

              # Move assembly to opening position and orientation (shifted by -half width on local X)
              t_shift = Geom::Transformation.translation(Geom::Vector3d.new(-w_len / 2.0, 0, 0))
              rad = dir && dir.valid? ? Math.atan2(dir.y, dir.x) : 0.0
              t_rot = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), rad)
              t_pos = Geom::Transformation.translation(pos)
              win_assembly.transform!(t_pos * t_rot * t_shift)

              # Set Attributes
              Attribute.set(win_assembly, 'type', 'window', 'NAUQ_WINDOW')
              Attribute.set(win_assembly, 'width', w_mm, 'NAUQ_WINDOW')
              Attribute.set(win_assembly, 'height', h_mm, 'NAUQ_WINDOW')
              Attribute.set(win_assembly, 'leaf_count', panel_count, 'NAUQ_WINDOW')
              Attribute.set(win_assembly, 'z_offset', z_off_mm, 'NAUQ_WINDOW')
              Attribute.tag(
                win_assembly,
                'window',
                id: op[:id],
                width: w_mm,
                height: h_mm,
                leaf_count: panel_count,
                z_offset: z_off_mm,
                has_fix_top: has_transom,
                has_fix_bottom: has_bottom_fix,
                fix_bottom_height: fix_bot_h_mm,
                source_cad_id: cad_id
              )

              built_count += 1
            rescue StandardError => e
              Logger.error("Lỗi khi tạo cửa sổ #{op[:id]}: #{e.message}\n#{e.backtrace ? e.backtrace.first(6).join("\n") : ''}")
            end
          end

          model.commit_operation
          Logger.info("Đã tạo #{built_count} bộ Cửa sổ 3D hoàn chỉnh trong group 'NAUQ_WINDOWS'")
        end
      end
    end
  end
end
