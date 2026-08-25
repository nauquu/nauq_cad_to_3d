# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Continuous glass panel builder with multi-directional fix support
    module GlassBuilder
      GLASS_THICKNESS = 15.0.mm unless defined?(GLASS_THICKNESS)
      FRAME_DEPTH = 80.0.mm unless defined?(FRAME_DEPTH)
      LEAF_DEPTH = 40.0.mm unless defined?(LEAF_DEPTH)
      LEAF_DEPTH_OFFSET = ((FRAME_DEPTH - LEAF_DEPTH) / 2.0) unless defined?(LEAF_DEPTH_OFFSET) # 20.mm

      class << self
        # Build a single rectangular glass solid
        # @param parent_group [Sketchup::Group, Sketchup::Entities]
        # @param x0 [Length, Float]
        # @param x1 [Length, Float]
        # @param z0 [Length, Float]
        # @param z1 [Length, Float]
        # @param material [Sketchup::Material, nil]
        # @return [Sketchup::Group, nil]
        def build_panel(parent_group, x0, x1, z0, z1, material = nil, name = 'GLASS')
          return nil unless x1 > x0 && z1 > z0

          target_entities = parent_group.respond_to?(:entities) ? parent_group.entities : parent_group
          glass = target_entities.add_group
          glass.name = name
          entities = glass.entities

          leaf_center_y = LEAF_DEPTH_OFFSET + (LEAF_DEPTH / 2.0)
          glass_y = leaf_center_y - (GLASS_THICKNESS / 2.0)

          points = [
            Geom::Point3d.new(x0, glass_y, z0),
            Geom::Point3d.new(x1, glass_y, z0),
            Geom::Point3d.new(x1, glass_y, z1),
            Geom::Point3d.new(x0, glass_y, z1)
          ]

          face = entities.add_face(points)
          return nil unless face

          face.pushpull(-GLASS_THICKNESS)
          MaterialLoader.apply_material(glass, material) if material
          glass
        end

        # Build all glasses from layout (active glass + all fix panels)
        # @param parent_group [Sketchup::Group, Sketchup::Entities]
        # @param layout [Hash] layout from FrameBuilder.calculate_layout
        # @param material [Sketchup::Material, nil]
        # @param include_active [Boolean] whether to include active leaf glass
        # @return [Array<Sketchup::Group>]
        def build_layout_glasses(parent_group, layout, material = nil, include_active: true)
          glasses = []

          # 1. Active Leaf Glass
          if include_active
            g_act = build_panel(parent_group, layout[:active_x0], layout[:active_x1], layout[:active_z0], layout[:active_z1], material, 'GLASS_LEAF')
            glasses << g_act if g_act
          end

          # 2. Fix Glasses
          if layout[:top_fix]
            tf = layout[:top_fix]
            g_tf = build_panel(parent_group, tf[:x0], tf[:x1], tf[:z0], tf[:z1], material, 'GLASS_FIX_TOP')
            glasses << g_tf if g_tf
          end

          if layout[:bot_fix]
            bf = layout[:bot_fix]
            g_bf = build_panel(parent_group, bf[:x0], bf[:x1], bf[:z0], bf[:z1], material, 'GLASS_FIX_BOTTOM')
            glasses << g_bf if g_bf
          end

          if layout[:left_fix]
            lf = layout[:left_fix]
            g_lf = build_panel(parent_group, lf[:x0], lf[:x1], lf[:z0], lf[:z1], material, 'GLASS_FIX_LEFT')
            glasses << g_lf if g_lf
          end

          if layout[:right_fix]
            rf = layout[:right_fix]
            g_rf = build_panel(parent_group, rf[:x0], rf[:x1], rf[:z0], rf[:z1], material, 'GLASS_FIX_RIGHT')
            glasses << g_rf if g_rf
          end

          glasses
        end

        # Legacy backward-compatible glass builder
        def build_glass(parent_group, active_width, leaf_height, x_offset: 0.mm, frame_width: 50.mm, has_fix_top: false, total_height: nil, material: nil)
          x0 = x_offset + frame_width
          x1 = x0 + active_width
          z0 = 0.mm
          z1 = leaf_height

          glass = build_panel(parent_group, x0, x1, z0, z1, material, 'GLASS')

          if has_fix_top && total_height && total_height > (leaf_height + frame_width)
            z0_fix = leaf_height + frame_width
            z1_fix = total_height - frame_width
            build_panel(parent_group, x0, x1, z0_fix, z1_fix, material, 'GLASS_FIX')
          end

          glass
        end
      end
    end
  end
end
