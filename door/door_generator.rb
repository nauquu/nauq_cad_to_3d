# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Main procedural Door Generator module porting V20 proven geometry
    # Decoupled from Opening/Wall logic, takes independent geometric parameters.
    module DoorGenerator
      FRAME_MATERIAL_KEY = 'kimloaidengoaithat' unless defined?(FRAME_MATERIAL_KEY)
      GLASS_MATERIAL_KEY = 'kinhh6' unless defined?(GLASS_MATERIAL_KEY)

      class << self
        # Procedurally generate a complete 3D door assembly
        # @param options [Hash]
        # @option options [Length, Float] :width Total door width (e.g. 1800.mm)
        # @option options [Length, Float] :height Total door height (e.g. 2200.mm)
        # @option options [Integer] :panel_count Number of leaves / panels (1, 2, 3, 4)
        # @option options [Boolean] :has_fix_top Whether top fix transom is present
        # @option options [Length, Float] :fix_module_height Total height of fix module (default 400.mm: 50mm transom frame + 350mm fix glass)
        # @option options [Sketchup::Group, Sketchup::Entities] :parent Container for the door
        # @option options [Length, Float] :x_offset Local X coordinate offset (default 0.mm)
        # @option options [String] :name Door group name (default "DOOR")
        # @option options [Sketchup::Material, String, nil] :frame_material Material or key for frame and leaves
        # @option options [Sketchup::Material, String, nil] :glass_material Material or key for glass
        # @option options [Hash, nil] :material_data Pre-loaded materials JSON hash
        # @return [Sketchup::Group] Generated Door assembly group
        def generate(options = {})
          model = Sketchup.active_model

          # 1. Parse & normalize geometric parameters
          width = normalize_length(options[:width] || 900.mm)
          height = normalize_length(options[:height] || 2200.mm)
          panel_count = [options[:panel_count] || 1, 1].max
          x_offset = normalize_length(options[:x_offset] || 0.mm)
          door_name = (options[:name] || "DOOR_#{panel_count}P").to_s

          parent = options[:parent] || model.active_entities
          target_entities = parent.respond_to?(:entities) ? parent.entities : parent

          # 2. Geometric calculations using FrameBuilder.calculate_layout
          layout = FrameBuilder.calculate_layout(width, height, options.merge(is_window: false, x_offset: x_offset))

          active_width = layout[:active_width]
          active_height = layout[:active_height]

          raise "#{door_name}: Chiều rộng vùng cánh (#{active_width.to_mm}mm) <= 0" if active_width <= 0
          is_sliding = !!options[:is_sliding]
          overlap = is_sliding ? 30.0.mm : 0.0.mm

          if is_sliding && panel_count == 2
            leaf_width = (active_width + overlap) / 2.0
            leaf_specs = [
              { x: layout[:active_x0], y_shift: -12.mm, w: leaf_width },
              { x: layout[:active_x0] + active_width - leaf_width, y_shift: 12.mm, w: leaf_width }
            ]
          elsif is_sliding && panel_count == 4
            leaf_width = (active_width + 2 * overlap) / 4.0
            leaf_specs = [
              { x: layout[:active_x0], y_shift: -12.mm, w: leaf_width },
              { x: layout[:active_x0] + leaf_width - overlap, y_shift: 12.mm, w: leaf_width },
              { x: layout[:active_x0] + 2 * leaf_width - overlap, y_shift: 12.mm, w: leaf_width },
              { x: layout[:active_x0] + active_width - leaf_width, y_shift: -12.mm, w: leaf_width }
            ]
          else
            leaf_width = active_width / panel_count.to_f
            leaf_specs = panel_count.times.map do |idx|
              { x: layout[:active_x0] + (idx * leaf_width), y_shift: 0.mm, w: leaf_width }
            end
          end

          leaf_height = active_height

          # 3. Resolve Materials
          material_data = options[:material_data]
          frame_mat = resolve_material(model, options[:frame_material] || FRAME_MATERIAL_KEY, material_data)
          glass_mat = resolve_material(model, options[:glass_material] || GLASS_MATERIAL_KEY, material_data)

          # 4. Create Main Door Group
          door = target_entities.add_group
          door.name = door_name

          # 5. Build FRAME
          FrameBuilder.build_frame(
            door,
            width,
            height,
            options.merge(material: frame_mat, is_window: false, x_offset: x_offset)
          )

          # 6. Get or Create Shared LEAF Definition (embeds aluminum frame + GLASS group inside LEAF)
          definition = LeafBuilder.get_or_create_leaf_definition(
            model,
            leaf_width,
            leaf_height,
            frame_mat,
            glass_mat,
            'TT_DOOR_LEAF'
          )

          # 7. Create LEAF Instances (each instance contains frame + its own embedded glass)
          leaf_specs.each_with_index do |spec, index|
            inst = LeafBuilder.create_leaf_instance(
              door,
              definition,
              index,
              spec[:w],
              exact_x: spec[:x],
              material: frame_mat
            )
            t_z = Geom::Transformation.translation(Geom::Vector3d.new(0, spec[:y_shift], layout[:active_z0]))
            inst.transform!(t_z)
          end

          # 8. Build Fix Glasses if present (Top Transom / Fix Panels)
          GlassBuilder.build_layout_glasses(
            door,
            layout,
            glass_mat,
            include_active: false
          )

          # 9. Set Attributes (V20 standard attributes + NAUQ Tagging)
          add_attributes(
            door,
            door_name: door_name,
            door_width: width,
            door_height: height,
            panel_count: panel_count,
            active_width: active_width,
            leaf_width: leaf_width,
            leaf_height: leaf_height,
            has_fix_top: layout[:has_fix_top],
            has_fix_bottom: layout[:has_fix_bottom],
            has_fix_left: layout[:has_fix_left],
            has_fix_right: layout[:has_fix_right],
            definition: definition
          )

          door
        end

        private

        def normalize_length(val)
          return val if val.is_a?(Length)
          val.respond_to?(:mm) ? val.mm : val.to_f.mm
        end

        def resolve_material(model, mat_or_key, material_data)
          return mat_or_key if mat_or_key.is_a?(Sketchup::Material)
          return nil unless mat_or_key

          MaterialLoader.get_material(model, mat_or_key.to_s, material_data)
        rescue StandardError => e
          Logger.warn("Không thể tải material '#{mat_or_key}': #{e.message}") if defined?(Logger)
          nil
        end

        def add_attributes(door, data)
          door.set_attribute('TT_Door', 'test_version', 'v20')
          door.set_attribute('TT_Door', 'door_name', data[:door_name])
          door.set_attribute('TT_Door', 'panel_count', data[:panel_count])
          door.set_attribute('TT_Door', 'width', data[:door_width].to_f)
          door.set_attribute('TT_Door', 'height', data[:door_height].to_f)
          door.set_attribute('TT_Door', 'active_width', data[:active_width].to_f)
          door.set_attribute('TT_Door', 'leaf_width', data[:leaf_width].to_f)
          door.set_attribute('TT_Door', 'leaf_height', data[:leaf_height].to_f)
          door.set_attribute('TT_Door', 'has_fix_top', data[:has_fix_top])
          door.set_attribute('TT_Door', 'leaf_component_definition', data[:definition].name)

          if defined?(Attribute)
            Attribute.tag(
              door,
              'door',
              name: data[:door_name],
              width_mm: data[:door_width].to_mm,
              height_mm: data[:door_height].to_mm,
              panel_count: data[:panel_count],
              has_fix_top: data[:has_fix_top]
            )
          end
        end
      end
    end
  end
end
