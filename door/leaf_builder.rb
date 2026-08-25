# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Component builder for door leaves using V20 proven FollowMe geometry & Profile
    module LeafBuilder
      FRAME_DEPTH = 80.0.mm unless defined?(FRAME_DEPTH)
      LEAF_DEPTH = 40.0.mm unless defined?(LEAF_DEPTH)
      LEAF_FRAME_WIDTH = 71.0.mm unless defined?(LEAF_FRAME_WIDTH)
      LEAF_DEPTH_OFFSET = ((FRAME_DEPTH - LEAF_DEPTH) / 2.0) unless defined?(LEAF_DEPTH_OFFSET) # 20.mm

      PROFILE_POINTS = [
        [0.0, 0.0],    # P0
        [11.0, 0.0],   # P1
        [11.0, 10.0],  # P2
        [16.0, 10.0],  # P3
        [16.0, 0.0],   # P4
        [68.0, 0.0],   # P5
        [68.0, 10.0],  # P6
        [71.0, 10.0],  # P7
        [71.0, 40.0],  # P8
        [16.0, 40.0],  # P9
        [16.0, 30.0],  # P10
        [11.0, 30.0],  # P11
        [11.0, 40.0],  # P12
        [0.0, 40.0],   # P13
        [0.0, 30.0],   # P14
        [0.0, 10.0]    # P15
      ].freeze

      PROFILE_ANCHOR_INDEX = 8 unless defined?(PROFILE_ANCHOR_INDEX)

      class << self
        # Get or create ComponentDefinition for LEAF
        # @param model [Sketchup::Model]
        # @param leaf_width [Length, Float]
        # @param leaf_height [Length, Float]
        # @param material [Sketchup::Material, nil]
        # @param prefix [String]
        # @return [Sketchup::ComponentDefinition]
        # Get or create ComponentDefinition for LEAF (contains aluminum leaf frame + embedded GLASS group)
        # @param model [Sketchup::Model]
        # @param leaf_width [Length, Float]
        # @param leaf_height [Length, Float]
        # @param frame_material [Sketchup::Material, nil]
        # @param glass_material [Sketchup::Material, nil]
        # @param prefix [String]
        # @return [Sketchup::ComponentDefinition]
        def get_or_create_leaf_definition(model, leaf_width, leaf_height, frame_material = nil, glass_material = nil, prefix = nil)
          if glass_material.is_a?(String) && (glass_material.start_with?('TT_') || prefix.nil?)
            # Handle legacy signature (model, leaf_width, leaf_height, frame_material, prefix)
            prefix = glass_material
            glass_material = nil
          end
          prefix ||= 'TT_DOOR_LEAF'

          width_mm = leaf_width.to_mm.round(2)
          height_mm = leaf_height.to_mm.round(2)
          definition_name = "#{prefix}_#{width_mm}x#{height_mm}"

          definition = model.definitions[definition_name]
          if definition && definition.valid?
            has_glass = definition.entities.grep(Sketchup::Group).any? { |g| g.name == 'GLASS' }
            return definition if has_glass
            definition.entities.clear!
          else
            definition = model.definitions.add(definition_name)
          end

          create_leaf_geometry(definition, leaf_width, leaf_height, frame_material, glass_material)
          definition
        end

        # Create leaf geometry inside definition using V20 FollowMe algorithm with embedded GLASS group
        # @param definition [Sketchup::ComponentDefinition]
        # @param leaf_width [Length, Float]
        # @param leaf_height [Length, Float]
        # @param frame_material [Sketchup::Material, nil]
        # @param glass_material [Sketchup::Material, nil]
        def create_leaf_geometry(definition, leaf_width, leaf_height, frame_material = nil, glass_material = nil)
          temp = definition.entities.add_group
          entities = temp.entities

          x0 = 0.mm
          x1 = leaf_width
          z0 = 0.mm
          z1 = leaf_height
          path_y = 0.mm

          # 1. 5-Edge Path Starting at Bottom Midpoint
          start_x = leaf_width / 2.0
          p_start = Geom::Point3d.new(start_x, path_y, z0)
          p_bottom_right = Geom::Point3d.new(x1, path_y, z0)
          p_top_right = Geom::Point3d.new(x1, path_y, z1)
          p_top_left = Geom::Point3d.new(x0, path_y, z1)
          p_bottom_left = Geom::Point3d.new(x0, path_y, z0)

          path_edges = []
          path_edges << entities.add_line(p_start, p_bottom_right)
          path_edges << entities.add_line(p_bottom_right, p_top_right)
          path_edges << entities.add_line(p_top_right, p_top_left)
          path_edges << entities.add_line(p_top_left, p_bottom_left)
          path_edges << entities.add_line(p_bottom_left, p_start)

          validate_path(path_edges)

          # 2. Profile Generation relative to P8 anchor
          anchor = PROFILE_POINTS[PROFILE_ANCHOR_INDEX]
          anchor_x = anchor[0].mm
          anchor_y = anchor[1].mm

          profile_points = []
          PROFILE_POINTS.each do |px_raw, py_raw|
            inward = anchor_x - px_raw.mm
            depth = anchor_y - py_raw.mm
            profile_points << Geom::Point3d.new(
              p_start.x,
              p_start.y + depth,
              p_start.z + inward
            )
          end

          p8 = profile_points[PROFILE_ANCHOR_INDEX]
          raise 'P8 không trùng START.' unless same_point?(p8, p_start)

          profile = entities.add_face(profile_points)
          raise 'Không tạo được LEAF profile.' unless profile

          profile.followme(path_edges)

          # 3. Depth Offset Translation (+20mm Y)
          temp.transform!(
            Geom::Transformation.translation(Geom::Vector3d.new(0, LEAF_DEPTH_OFFSET, 0))
          )

          # 4. Flip XZ around Leaf Center (Y = 40mm)
          leaf_center_y = LEAF_DEPTH_OFFSET + (LEAF_DEPTH / 2.0)
          temp.transform!(
            Geom::Transformation.scaling(
              Geom::Point3d.new(0, leaf_center_y, 0),
              1, -1, 1
            )
          )

          MaterialLoader.apply_material(temp, frame_material) if frame_material

          temp.explode

          # 5. Build embedded GLASS Group inside LEAF Definition
          glass_mat = glass_material || (MaterialLoader.get_material(definition.model || Sketchup.active_model, 'kinhh6') rescue nil)
          glass_margin = 55.0.mm
          gx0 = glass_margin
          gx1 = leaf_width - glass_margin
          gz0 = glass_margin
          gz1 = leaf_height - glass_margin
          glass_thickness = 10.0.mm
          glass_y = leaf_center_y - (glass_thickness / 2.0)

          if gx1 > gx0 && gz1 > gz0
            glass_group = definition.entities.add_group
            glass_group.name = 'GLASS'
            pts = [
              Geom::Point3d.new(gx0, glass_y, gz0),
              Geom::Point3d.new(gx1, glass_y, gz0),
              Geom::Point3d.new(gx1, glass_y, gz1),
              Geom::Point3d.new(gx0, glass_y, gz1)
            ]
            face = glass_group.entities.add_face(pts)
            if face
              face.pushpull(-glass_thickness)
              MaterialLoader.apply_material(glass_group, glass_mat) if glass_mat
            end
          end

          definition
        end

        # Create Leaf Component Instance
        # @param parent_group [Sketchup::Group, Sketchup::Entities]
        # @param definition [Sketchup::ComponentDefinition]
        # @param index [Integer] 0-based index
        # @param leaf_width [Length, Float]
        # @param x_offset [Length, Float]
        # @param frame_width [Length, Float]
        # @param exact_x [Length, Float, nil] Direct X position (overrides x_offset calculation)
        # @return [Sketchup::ComponentInstance]
        def create_leaf_instance(parent_group, definition, index, leaf_width, x_offset: 0.mm, frame_width: 50.mm, material: nil, exact_x: nil)
          target_entities = parent_group.respond_to?(:entities) ? parent_group.entities : parent_group

          x = exact_x ? exact_x : (x_offset + frame_width + (index * leaf_width))
          t = Geom::Transformation.translation(Geom::Vector3d.new(x, 0, 0))

          instance = target_entities.add_instance(definition, t)
          instance.name = "LEAF_#{index + 1}"
          instance.material = material if material

          instance.set_attribute('TT_Door', 'panel_index', index + 1)
          instance.set_attribute('TT_Door', 'component_definition', definition.name)
          Attribute.tag(instance, 'leaf', index: index + 1, width_mm: leaf_width.to_mm, height_mm: definition.bounds.depth.to_mm) if defined?(Attribute)

          instance
        end

        # Validate that path edges are closed and continuous
        def validate_path(edges)
          raise 'Path phải có 5 edge.' unless edges.length == 5

          4.times do |i|
            unless same_point?(edges[i].end.position, edges[i + 1].start.position)
              raise "Path không liên tục tại edge #{i}."
            end
          end

          unless same_point?(edges[4].end.position, edges[0].start.position)
            raise 'Path chưa đóng.'
          end

          true
        end

        # Compare two points with epsilon
        def same_point?(a, b)
          a.distance(b) <= 0.001.mm
        end
      end
    end
  end
end
