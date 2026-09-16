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
        def build_panel(parent_group, x0, x1, z0, z1, material = nil, name = 'GLASS', y_offset: 0.mm, corner_radius: 0.mm, corner_sides: nil)
          return nil unless x1 > x0 && z1 > z0

          target_entities = parent_group.respond_to?(:entities) ? parent_group.entities : parent_group
          glass = target_entities.add_group
          glass.name = name
          entities = glass.entities

          leaf_center_y = LEAF_DEPTH_OFFSET + (LEAF_DEPTH / 2.0) + y_offset
          glass_y = leaf_center_y - (GLASS_THICKNESS / 2.0)

          r = corner_radius ? corner_radius.to_f : 0.0
          max_r = corner_sides == :both ? ((x1 - x0) / 2.0) : (x1 - x0)
          cur_r = (r > 1.0.mm && corner_sides) ? [r, max_r, (z1 - z0) - 10.mm.to_f].min : 0.0
          round_r = cur_r > 1.0.mm && [:both, :right].include?(corner_sides)
          round_l = cur_r > 1.0.mm && [:both, :left].include?(corner_sides)

          points = []
          points << Geom::Point3d.new(x0, glass_y, z0)
          points << Geom::Point3d.new(x1, glass_y, z0)

          if round_r
            n_segs = 12
            points << Geom::Point3d.new(x1, glass_y, z1 - cur_r)
            n_segs.times do |i|
              ang = (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
              px = (x1 - cur_r) + cur_r * Math.cos(ang)
              pz = (z1 - cur_r) + cur_r * Math.sin(ang)
              points << Geom::Point3d.new(px, glass_y, pz)
            end
          else
            points << Geom::Point3d.new(x1, glass_y, z1)
          end

          top_r_x = round_r ? (x1 - cur_r) : x1
          top_l_x = round_l ? (x0 + cur_r) : x0
          if top_r_x > top_l_x + 0.001.mm
            points << Geom::Point3d.new(top_l_x, glass_y, z1)
          end

          if round_l
            n_segs = 12
            n_segs.times do |i|
              ang = (Math::PI / 2.0) + (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
              px = (x0 + cur_r) + cur_r * Math.cos(ang)
              pz = (z1 - cur_r) + cur_r * Math.sin(ang)
              points << Geom::Point3d.new(px, glass_y, pz)
            end
          else
            last_pt = points.last
            tl_pt = Geom::Point3d.new(x0, glass_y, z1)
            points << tl_pt if !last_pt || last_pt.distance(tl_pt) > 0.001.mm
          end

          clean_pts = []
          points.each { |p| clean_pts << p if clean_pts.empty? || clean_pts.last.distance(p) > 0.001.mm }
          clean_pts.pop if clean_pts.size > 2 && clean_pts.first.distance(clean_pts.last) < 0.001.mm

          face = entities.add_face(clean_pts)
          return nil unless face

          face.pushpull(-GLASS_THICKNESS)
          MaterialLoader.apply_material(glass, material) if material
          glass
        end

        # Build individual glass solid for each leaf panel (1 Leaf = 1 Glass)
        # @param parent_group [Sketchup::Group, Sketchup::Entities]
        # @param leaf_specs [Array<Hash>] [{ x:, y_shift:, w: }]
        # @param layout [Hash]
        # @param material [Sketchup::Material, nil]
        # @param prefix [String]
        # @return [Array<Sketchup::Group>]
        def build_leaf_panels(parent_group, leaf_specs, layout, material = nil, prefix = 'GLASS_LEAF')
          glasses = []
          z0 = layout[:active_z0]
          z1 = layout[:active_z1]

          leaf_specs.each_with_index do |spec, idx|
            x0 = spec[:x]
            x1 = spec[:x] + spec[:w]
            y_shift = spec[:y_shift] || 0.mm

            g = build_panel(parent_group, x0, x1, z0, z1, material, "#{prefix}_#{idx + 1}", y_offset: y_shift)
            glasses << g if g
          end

          glasses
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

          cr = layout[:corner_radius] ? layout[:corner_radius].to_f : 0.0
          fw = layout[:frame_width] || 60.0.mm
          inner_r = cr > 1.0.mm ? [cr - fw, 0.0].max : 0.0

          # 2. Fix Glasses
          if layout[:top_fix]
            tf = layout[:top_fix]
            tf_sides = if !layout[:has_fix_left] && !layout[:has_fix_right]
                         :both
                       elsif !layout[:has_fix_left]
                         :left
                       elsif !layout[:has_fix_right]
                         :right
                       end
            g_tf = build_panel(parent_group, tf[:x0], tf[:x1], tf[:z0], tf[:z1], material, 'GLASS_FIX_TOP',
                               corner_radius: inner_r, corner_sides: tf_sides)
            glasses << g_tf if g_tf
          end

          if layout[:bot_fix]
            bf = layout[:bot_fix]
            g_bf = build_panel(parent_group, bf[:x0], bf[:x1], bf[:z0], bf[:z1], material, 'GLASS_FIX_BOTTOM')
            glasses << g_bf if g_bf
          end

          if layout[:left_fix]
            lf = layout[:left_fix]
            lf_sides = (inner_r > 1.0.mm) ? :left : nil
            g_lf = build_panel(parent_group, lf[:x0], lf[:x1], lf[:z0], lf[:z1], material, 'GLASS_FIX_LEFT',
                               corner_radius: inner_r, corner_sides: lf_sides)
            glasses << g_lf if g_lf
          end

          if layout[:right_fix]
            rf = layout[:right_fix]
            rf_sides = (inner_r > 1.0.mm) ? :right : nil
            g_rf = build_panel(parent_group, rf[:x0], rf[:x1], rf[:z0], rf[:z1], material, 'GLASS_FIX_RIGHT',
                               corner_radius: inner_r, corner_sides: rf_sides)
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
