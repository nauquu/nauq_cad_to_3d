# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Scans imported CAD geometry filtering by specific AutoCAD layers
    module LayerParser
      class << self
        # Find all edges/lines on a given layer inside CAD group or instance
        # @param cad_group [Sketchup::Group, Sketchup::ComponentInstance]
        # @param layer_name [String] layer to parse (e.g. '0-netcat')
        # @return [Array<Sketchup::Edge>]
        def collect_edges_by_layer(cad_group, layer_name)
          return [] if cad_group.nil? || !cad_group.valid? || layer_name.to_s.empty?

          all_edges = []
          entities = cad_group.is_a?(Sketchup::ComponentInstance) ? cad_group.definition.entities : cad_group.entities
          scan_entities(entities, layer_name.to_s.downcase, all_edges)
          all_edges
        end

        # Collect segment start/end point pairs (in mm) for parsed edges
        # @param edges [Array<Sketchup::Edge>]
        # @return [Array<Hash>] [{start_pt: Point3d, end_pt: Point3d, edge: Edge}]
        def parse_line_segments(edges)
          edges.map do |edge|
            {
              start_pt: edge.start.position,
              end_pt: edge.end.position,
              length_mm: Geometry.inch_to_mm(edge.length),
              edge: edge
            }
          end
        end

        # Collect line segments on layer with coordinate transformations
        def collect_segments_with_transform(cad_group, layer_name)
          return [] if cad_group.nil? || !cad_group.valid? || layer_name.to_s.empty?

          target_layer_lower = layer_name.to_s.strip.downcase
          segments = []
          initial_transform = cad_group.respond_to?(:transformation) ? cad_group.transformation : Geom::Transformation.new
          entities = cad_group.is_a?(Sketchup::ComponentInstance) ? cad_group.definition.entities : cad_group.entities

          scan_entities_with_transform(entities, target_layer_lower, initial_transform, segments, nil)
          segments
        end

        private

        def scan_entities_with_transform(entities, target_layer_lower, current_transform, collector, parent_layer_lower)
          entities.each do |entity|
            next unless entity.valid?

            entity_layer = entity.respond_to?(:layer) && entity.layer ? entity.layer.name.to_s.strip.downcase : nil
            effective_layer = if entity_layer && entity_layer != 'untagged' && entity_layer != 'layer0' && entity_layer != '0'
                                entity_layer
                              else
                                parent_layer_lower
                              end

            if entity.is_a?(Sketchup::Edge)
              if effective_layer == target_layer_lower || entity_layer == target_layer_lower
                pt1 = entity.start.position.transform(current_transform)
                pt2 = entity.end.position.transform(current_transform)
                collector << {
                  start_pt: pt1,
                  end_pt: pt2,
                  length_mm: Geometry.inch_to_mm(pt1.distance(pt2)),
                  edge: entity
                }
              end
            elsif entity.is_a?(Sketchup::Group)
              child_transform = current_transform * entity.transformation
              scan_entities_with_transform(entity.entities, target_layer_lower, child_transform, collector, effective_layer)
            elsif entity.is_a?(Sketchup::ComponentInstance)
              next if is_door_or_window_block?(entity)

              child_transform = current_transform * entity.transformation
              scan_entities_with_transform(entity.definition.entities, target_layer_lower, child_transform, collector, effective_layer)
            end
          end
        end

        def scan_entities(entities, target_layer_lower, collector)
          entities.each do |entity|
            if entity.is_a?(Sketchup::Edge)
              collector << entity if entity_on_layer?(entity, target_layer_lower)
            elsif entity.is_a?(Sketchup::Group)
              scan_entities(entity.entities, target_layer_lower, collector)
            elsif entity.is_a?(Sketchup::ComponentInstance)
              next if is_door_or_window_block?(entity)

              scan_entities(entity.definition.entities, target_layer_lower, collector)
            end
          end
        end

        def is_door_or_window_block?(entity)
          return false unless entity.is_a?(Sketchup::ComponentInstance)
          return false if Attribute.tagged_as?(entity, 'dwg_import') ||
                          Attribute.tagged_as?(entity, 'dwg_import_item') ||
                          Attribute.tagged_as?(entity, 'cad_original')
          return false if entity.name.to_s.start_with?('CAD_') || entity.name.to_s.start_with?('DWG_')

          entity_layer = entity.layer ? entity.layer.name.to_s.strip.downcase : ''
          def_name = entity.definition ? entity.definition.name.to_s.strip.downcase : ''

          door_layer = (Config.get(:door_layer) || '0-cua').to_s.strip.downcase
          win_layer = (Config.get(:window_layer) || 'nho').to_s.strip.downcase
          door_block = (Config.get(:door_block) || 'cua di').to_s.strip.downcase

          return true if door_layer != '' && (entity_layer == door_layer || entity_layer.include?(door_layer))
          return true if win_layer != '' && (entity_layer == win_layer || entity_layer.include?(win_layer))
          return true if door_block != '' && (def_name == door_block || def_name.include?(door_block))

          false
        end

        def entity_on_layer?(entity, target_layer_lower)
          return false unless entity.respond_to?(:layer) && entity.layer

          entity.layer.name.to_s.downcase == target_layer_lower
        end
      end
    end
  end
end
