# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Scans AutoCAD component blocks (e.g., door blocks like CUA DI, D1, D2, and window blocks like CUA SO, WINDOW)
    module BlockParser
      WINDOW_KEYWORDS = [
        'cua so', 'cuaso', 'cua_so', 'cua-so', 'window', 'win'
      ].freeze

      DOOR_KEYWORDS = [
        'cua di', 'cuadi', 'cưa đi', 'cưa di', 'cua_di', 'cua-di', 'door'
      ].freeze

      class << self
        # Determine if a block or definition name indicates a door
        def is_door_name?(name)
          str = name.to_s.strip.downcase
          return false if str.empty?
          return true if DOOR_KEYWORDS.any? { |kw| str.include?(kw) }
          return true if str =~ /^(d\d+|d_\d+|d-\d+|c\d+|c_\d+|c-\d+)/
          return true if str =~ /^wd(_|-|\d)/ # Wood Door (WD_LD4, WD_LD2, WD-01, etc.)
          if str.include?('cua') && !is_window_keyword?(str)
            return true
          end
          false
        end

        # Determine if a name or layer matches window keywords or conventions
        def is_window_keyword?(str)
          s = str.to_s.strip.downcase
          return false if s.empty?
          WINDOW_KEYWORDS.any? { |kw| s.include?(kw) } || s =~ /^(w\d+|w_\d+|w-\d+|s\d+|s_\d+|s-\d+|cs\d+)/
        end
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

          initial_transform = Geometry.full_world_transform(cad_group)
          entities = cad_group.is_a?(Sketchup::ComponentInstance) ? cad_group.definition.entities : cad_group.entities
          scan_blocks(entities, target_block_lower, target_layer_lower, initial_transform, items, :door)

          map_items_to_world_data(items)
        end

        # Find all component instances matching window block name / window keywords inside container
        # @param cad_group [Sketchup::Group, Sketchup::ComponentInstance]
        # @param block_name [String] e.g. 'CUA SO'
        # @param layer_name [String] optional layer name filter e.g. 'nho'
        # @return [Array<Hash>] parsed window block details
        def collect_window_blocks(cad_group, block_name = nil, layer_name = nil)
          return [] if cad_group.nil? || !cad_group.valid?

          items = []
          target_block_lower = block_name.to_s.strip.downcase
          target_layer_lower = layer_name.to_s.strip.downcase

          initial_transform = Geometry.full_world_transform(cad_group)
          entities = cad_group.is_a?(Sketchup::ComponentInstance) ? cad_group.definition.entities : cad_group.entities
          scan_blocks(entities, target_block_lower, target_layer_lower, initial_transform, items, :window)

          map_items_to_world_data(items)
        end

        private

        def map_items_to_world_data(items)
          items.map do |item|
            inst = item[:instance]
            world_t = item[:world_transform]
            def_bounds = inst.definition.bounds
            size_mm = Geometry.bbox_size_mm(def_bounds)

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

        def scan_blocks(entities, target_block_lower, target_layer_lower, current_transform, collector, mode = :door)
          entities.each do |entity|
            next unless entity.valid?

            if entity.is_a?(Sketchup::ComponentInstance)
              child_transform = current_transform * entity.transformation
              if is_cad_system_wrapper?(entity)
                scan_blocks(entity.definition.entities, target_block_lower, target_layer_lower, child_transform, collector, mode)
                next
              end

              def_name = entity.definition.name.to_s.strip.downcase
              entity_layer = entity.layer ? entity.layer.name.to_s.strip.downcase : ''

              matched = if mode == :window
                          is_window_match?(entity, def_name, entity_layer, target_block_lower, target_layer_lower)
                        else
                          is_door_match?(entity, def_name, entity_layer, target_block_lower, target_layer_lower)
                        end

              if matched
                collector << { instance: entity, world_transform: child_transform }
              else
                scan_blocks(entity.definition.entities, target_block_lower, target_layer_lower, child_transform, collector, mode)
              end
            elsif entity.is_a?(Sketchup::Group)
              child_transform = current_transform * entity.transformation
              scan_blocks(entity.entities, target_block_lower, target_layer_lower, child_transform, collector, mode)
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

        # Checks if a component definition contains any circular arc entity (door swing trajectory)
        # Note: Arc can be any angle (e.g. 90, 45, 30, arbitrary angle), not strictly 90 degrees.
        def has_arc_entity?(entity)
          defn = if entity.respond_to?(:definition)
                   entity.definition
                 elsif entity.respond_to?(:entities)
                   entity
                 end
          return false unless defn&.entities

          defn.entities.any? do |child|
            if (defined?(Sketchup::ArcCurve) && child.is_a?(Sketchup::ArcCurve)) ||
               child.class.name.include?('ArcCurve') ||
               (child.respond_to?(:curve) && child.curve && (
                 (defined?(Sketchup::ArcCurve) && child.curve.is_a?(Sketchup::ArcCurve)) ||
                 child.curve.class.name.include?('ArcCurve') ||
                 child.curve.respond_to?(:radius)
               ))
              true
            elsif (defined?(Sketchup::ComponentInstance) && child.is_a?(Sketchup::ComponentInstance)) ||
                  (defined?(Sketchup::Group) && child.is_a?(Sketchup::Group))
              has_arc_entity?(child)
            else
              false
            end
          end
        end

        def layer_matches?(entity_layer, target_layer)
          return false if entity_layer.to_s.strip.empty? || target_layer.to_s.strip.empty?
          return true if target_layer == 'all' || target_layer == '*'

          e_lyr = entity_layer.to_s.strip.downcase
          t_lyr = target_layer.to_s.strip.downcase

          e_lyr == t_lyr
        end

        # Smart door block recognition
        def is_door_match?(entity, def_name, entity_layer, target_block_lower, target_layer_lower)
          # Exclude any window blocks explicitly
          return false if is_window_keyword?(def_name)

          door_layer_lower = (target_layer_lower.to_s.empty? ? Config.get(:door_layer) : target_layer_lower).to_s.strip.downcase
          win_layer_lower = Config.get(:window_layer).to_s.strip.downcase
          is_shared_layer = !door_layer_lower.empty? && (door_layer_lower == win_layer_lower)

          # Check if entity is on the door layer
          is_on_door_layer = layer_matches?(entity_layer, door_layer_lower)

          # Check if there is an explicit target_block name match
          has_explicit_block_match = !target_block_lower.empty? &&
                                     target_block_lower != 'all' &&
                                     target_block_lower != '*' &&
                                     (def_name == target_block_lower || def_name.include?(target_block_lower))

          # CRITICAL RULE: Entity MUST be on the door layer (or explicitly match configured block name)!
          # Furniture with arcs (sinks, showers, toilets) on other layers (e.g. 0-noithat) MUST NEVER be treated as doors!
          return false unless is_on_door_layer || has_explicit_block_match

          # 1. Target block name match
          return true if has_explicit_block_match

          # 2. Standard architectural naming conventions for doors (e.g. WD_LD4, D1, CUA DI, etc.)
          return true if is_door_name?(def_name)

          # 3. If layers are the SAME: Check Arc (Dynamic Door Blocks have an arc)
          if is_shared_layer
            # Door dynamic blocks have an arc (swing path)
            return true if has_arc_entity?(entity)

            # On a shared layer, if block has no door name and no arc, do NOT claim it as a door
            return false
          end

          # 4. If layers are DIFFERENT: layer match takes priority ("nếu khác nhau thì thôi")
          return true if is_on_door_layer

          # Check internal entities inside definition
          if entity&.respond_to?(:definition) && entity.definition&.entities
            has_internal_door_layer = entity.definition.entities.any? do |child|
              c_layer = child.respond_to?(:layer) && child.layer ? child.layer.name.to_s.strip.downcase : ''
              layer_matches?(c_layer, door_layer_lower)
            end
            return true if has_internal_door_layer
          end

          false
        end

        # Smart window block recognition
        def is_window_match?(entity, def_name, entity_layer, target_block_lower, target_layer_lower)
          # 1. Exclude doors explicitly
          return false if is_door_name?(def_name)

          door_layer_lower = Config.get(:door_layer).to_s.strip.downcase
          win_layer_lower = (target_layer_lower.to_s.empty? ? Config.get(:window_layer) : target_layer_lower).to_s.strip.downcase
          is_shared_layer = !win_layer_lower.empty? && (door_layer_lower == win_layer_lower)

          # Check if entity is on the window layer
          is_on_win_layer = layer_matches?(entity_layer, win_layer_lower)

          has_explicit_win_block_match = !target_block_lower.empty? &&
                                         target_block_lower != 'all' &&
                                         target_block_lower != '*' &&
                                         (def_name == target_block_lower || def_name.include?(target_block_lower))

          # CRITICAL RULE: Entity MUST be on the window layer (or explicitly match configured block name)!
          # Furniture on other layers (e.g. 0-noithat) MUST NEVER be treated as windows!
          return false unless is_on_win_layer || has_explicit_win_block_match

          # 2. If entity has an arc, it is a DOOR (swing path), never a window!
          return false if has_arc_entity?(entity)

          # 3. Target block match (e.g. configured in Settings)
          return true if has_explicit_win_block_match

          # 4. Explicit window keyword or naming convention in definition
          return true if is_window_keyword?(def_name)

          # 5. If layers are the SAME:
          if is_shared_layer
            # On shared layer: block has NO arc.
            # If it is an anonymous block or configured as dynamic window, it is a window
            if def_name.start_with?('*u') || def_name.start_with?('*') || Config.get(:window_is_dynamic)
              return true
            end
            return false
          end

          # 6. If layers are DIFFERENT: Dedicated window layer match
          return true if is_on_win_layer

          # 7. Check internal entities if dedicated layer
          if entity&.respond_to?(:definition) && entity.definition&.entities
            has_internal_win_layer = entity.definition.entities.any? do |child|
              c_layer = child.respond_to?(:layer) && child.layer ? child.layer.name.to_s.strip.downcase : ''
              layer_matches?(c_layer, win_layer_lower)
            end
            return true if has_internal_win_layer
          end

          false
        end
      end
    end
  end
end
