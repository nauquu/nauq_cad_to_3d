# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Generates 3D doors in NAUQ_DOORS group container (Phase 4)
    module DoorBuilder
      class << self
        # Build all doors based on detected openings
        # @param openings_data [Array<Hash>] list of door openings
        # @param doors_group [Sketchup::Group, nil] NAUQ_DOORS group
        # @param cad_group [Sketchup::Group, Sketchup::ComponentInstance, nil] source CAD item
        def build_doors(openings_data, doors_group = nil, cad_group = nil)
          door_openings = openings_data.select { |op| op[:type] == :door }
          return if door_openings.empty?

          model = Sketchup.active_model
          cad_id = cad_group ? (cad_group.respond_to?(:persistent_id) ? cad_group.persistent_id.to_s : cad_group.object_id.to_s) : nil
          floor_name = cad_group && cad_group.respond_to?(:name) && !cad_group.name.empty? ? cad_group.name : "Floor_#{cad_id || Time.now.to_i}"

          model.start_operation('NAUQ Build 3D Doors', true)

          # Erase previous doors created for this specific CAD drawing if any
          if cad_id
            existing_model = model.entities.grep(Sketchup::Group).select do |g|
              g.valid? && (g.name == "DOORS_#{floor_name}" || (Attribute.get(g, 'source_cad_id') == cad_id && g.name.start_with?('DOORS_')))
            end
            existing_model.each { |g| g.erase! if g.valid? }

            legacy_container = model.entities.grep(Sketchup::Group).find { |g| g.valid? && g.name == DWGReader::DOORS_GROUP_NAME }
            if legacy_container
              existing_sub = legacy_container.entities.grep(Sketchup::ComponentInstance).select do |inst|
                inst.valid? && Attribute.get(inst, 'source_cad_id') == cad_id
              end
              existing_sub.each { |inst| inst.erase! if inst.valid? }
            end
          end

          # Create independent group for this floor's doors directly at model root
          model.selection.clear rescue nil
          doors_group = model.entities.add_group
          doors_group.name = "DOORS_#{floor_name}"
          Attribute.tag(doors_group, 'door_floor', source_cad_id: cad_id)

          glass_h_mm = Config.get(:glass_height) || 350.0
          frame_s_mm = Config.get(:frame_size) || 50.0

          built_count = 0

          door_openings.each do |op|
          if op[:edge_left] && op[:edge_right]
              e_l_len = Geometry.inch_to_mm(op[:edge_left][0].distance(op[:edge_left][1]))
              e_r_len = Geometry.inch_to_mm(op[:edge_right][0].distance(op[:edge_right][1]))
              if (e_l_len - e_r_len).abs > 100.0
                Logger.warn("Bỏ qua tạo cửa #{op[:id]} do cạnh trái (#{e_l_len.round(1)}mm) và cạnh phải (#{e_r_len.round(1)}mm) lệch chiều dài quá 100mm.")
                next
              end
            end

            w_mm = op[:width_mm]
            h_mm = op[:height_mm] || 2200.0
            pos = op[:position]

            max_leaf_w = Config.get(:door_max_width) || 900.0
            frame_s_mm = Config.get(:frame_size) || 50.0
            net_w = [w_mm - (2 * frame_s_mm), 100.0].max
            leaf_count = [(net_w / max_leaf_w).ceil, 1].max

            has_transom = (Config.get(:glass_height) || 0.0) > 0
            dir = op[:direction]

            # Generate door assembly using V20 DoorGenerator
            door_assembly = DoorGenerator.generate(
              parent: doors_group,
              name: "DOOR_#{op[:id]}",
              width: w_mm.mm,
              height: h_mm.mm,
              panel_count: leaf_count,
              has_fix_top: has_transom,
              fix_module_height: glass_h_mm.mm
            )

            # Move assembly to opening position and orientation (shifted by -half width on local X)
            t_shift = Geom::Transformation.translation(Geom::Vector3d.new(-w_mm.mm / 2.0, 0, 0))
            rad = dir && dir.valid? ? Math.atan2(dir.y, dir.x) : 0.0
            t_rot = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), rad)
            t_pos = Geom::Transformation.translation(pos)
            door_assembly.transform!(t_pos * t_rot * t_shift)

            # Set Spec Section 21 attributes
            Attribute.set(door_assembly, 'type', 'door', 'NAUQ_DOOR')
            Attribute.set(door_assembly, 'width', w_mm, 'NAUQ_DOOR')
            Attribute.set(door_assembly, 'height', h_mm, 'NAUQ_DOOR')
            Attribute.set(door_assembly, 'leaf_count', leaf_count, 'NAUQ_DOOR')
            Attribute.tag(door_assembly, 'door', id: op[:id], width: w_mm, leaf_count: leaf_count, source_cad_id: cad_id)

            built_count += 1
          end

          model.commit_operation
          Logger.info("Đã tạo #{built_count} bộ Cửa đi 3D hoàn chỉnh trong group 'NAUQ_DOORS'")
        end
      end
    end
  end
end
