# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Scans AutoCAD component blocks (e.g., door blocks like CUA DI, D1, D2, Door, *U...) in imported CAD data
    module BlockParser
      class << self
        # Find all component instances matching block name / door keywords inside container with full world transformation
        # @param cad_group [Sketchup::Group, Sketchup::ComponentInstance]
        # @param block_name [String] e.g. 'CUA DI'
        # @param layer_name [String] optional layer name filter e.g. '0-cua'
        # @return [Array<Hash>] parsed block details with world positions and transformations
        def collect_blocks(cad_group, block_name = nil, layer_name = nil)
          return [] if cad_group.nil? || !cad_group.valid?

          items = []
          target_block_lower = block_name.to_s.strip.downcase
          target_layer_lower = layer_name.to_s.strip.downcase

          initial_transform = cad_group.respond_to?(:transformation) ? cad_group.transformation : Geom::Transformation.new
          entities = cad_group.is_a?(Sketchup::ComponentInstance) ? cad_group.definition.entities : cad_group.entities
          scan_blocks(entities, target_block_lower, target_layer_lower, initial_transform, items)

          items.map do |item|
            inst = item[:instance]
            world_t = item[:world_transform]
            # Use definition bounds transformed to world coordinate system
            def_bounds = inst.definition.bounds
            size_mm = Geometry.bbox_size_mm(def_bounds)

            # Compute world bounds
            world_corners = (0..7).map { |i| def_bounds.corner(i).transform(world_t) }
            world_bbox = Geom::BoundingBox.new
            world_corners.each { |pt| world_bbox.add(pt) }

            {
              instance: inst,
              definition_name: inst.definition.name,
              position: world_t.origin,
              transformation: world_t,
              width_mm: size_mm[0],
              depth_mm: size_mm[1],
              height_mm: size_mm[2],
              bounds: world_bbox
            }
          end
        end

        private

        def scan_blocks(entities, target_block_lower, target_layer_lower, current_transform, collector)
          entities.each do |entity|
            next unless entity.valid?

            if entity.is_a?(Sketchup::ComponentInstance)
              # Ignore root container groups or CAD import markers
              next if is_cad_system_wrapper?(entity)

              child_transform = current_transform * entity.transformation
              def_name = entity.definition.name.to_s.strip.downcase
              entity_layer = entity.layer ? entity.layer.name.to_s.strip.downcase : ''

              if is_door_match?(entity, def_name, entity_layer, target_block_lower, target_layer_lower)
                collector << { instance: entity, world_transform: child_transform }
              else
                # Recurse inside only if this component itself is not recognized as a leaf door block
                scan_blocks(entity.definition.entities, target_block_lower, target_layer_lower, child_transform, collector)
              end
            elsif entity.is_a?(Sketchup::Group)
              next if is_cad_system_wrapper?(entity)

              child_transform = current_transform * entity.transformation
              scan_blocks(entity.entities, target_block_lower, target_layer_lower, child_transform, collector)
            end
          end
        end

        def is_cad_system_wrapper?(entity)
          return true if Attribute.tagged_as?(entity, 'dwg_import') ||
                         Attribute.tagged_as?(entity, 'dwg_import_item') ||
                         Attribute.tagged_as?(entity, 'cad_original')
          return true if entity.name.to_s.start_with?('CAD_') || entity.name.to_s.start_with?('DWG_')

          false
        end

        # Smart door block recognition supporting:
        # 1. Configured block name (e.g. 'CUA DI')
        # 2. Configured door layer (e.g. '0-cua', 'cua', 'door')
        # 3. Dynamic AutoCAD blocks (*U..., *X...)
        # 4. Standard architectural naming conventions (D1, D2, D3, CUA_PHONG, DOOR_SINGLE, C-01, etc.)
        # 5. Internal entities on door layer
        def is_door_match?(entity, def_name, entity_layer, target_block_lower, target_layer_lower)
          # A. Direct layer match with configured layer (e.g. '0-cua')
          if !target_layer_lower.empty? && target_layer_lower != 'all' && target_layer_lower != '*'
            if entity_layer == target_layer_lower ||
               entity_layer.include?(target_layer_lower) ||
               target_layer_lower.include?(entity_layer)
              return true
            end
          end

          # B. Layer contains generic door keywords (e.g. 'cua', 'door')
          if entity_layer.include?('cua') || entity_layer.include?('door')
            return true
          end

          # C. Target block name match (if specified and not default 'all')
          if !target_block_lower.empty? && target_block_lower != 'all' && target_block_lower != '*'
            return true if def_name == target_block_lower || def_name.include?(target_block_lower)
          end

          # D. Standard architectural naming conventions for doors
          # Matches: d1, d2, d01, d_1, d-1, cua, cua_di, cua_phong, door, door_single, c1, c2, etc.
          if def_name =~ /^(d\d+|d_\d+|d-\d+|c\d+|c_\d+|c-\d+|cua|door)/ ||
             def_name.include?('cua') ||
             def_name.include?('door')
            return true
          end

          # E. AutoCAD Dynamic Anonymous Blocks (*U..., *X...) on door layer or containing door entities
          if def_name.start_with?('*u') || def_name.start_with?('*') || def_name.include?('anonymous')
            return true if entity_layer.include?('cua') || entity_layer.include?('door')
          end

          # F. Check internal entities inside definition (if block reference was inserted on Layer 0)
          if entity.definition&.entities
            has_internal_door_layer = entity.definition.entities.any? do |child|
              c_layer = child.layer ? child.layer.name.to_s.strip.downcase : ''
              c_layer == target_layer_lower ||
                c_layer.include?(target_layer_lower) ||
                c_layer.include?('cua') ||
                c_layer.include?('door')
            end
            return true if has_internal_door_layer
          end

          false
        end
      end
    end
  end
end
