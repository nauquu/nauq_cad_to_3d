# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Frame builder for procedural doors & windows with multi-directional fix panels
    module FrameBuilder
      FRAME_WIDTH = 50.0.mm unless defined?(FRAME_WIDTH)
      FRAME_DEPTH = 80.0.mm unless defined?(FRAME_DEPTH)

      class << self
        # Calculate geometric bounding boxes for active area and all fix panels
        # @param door_width [Length, Float]
        # @param door_height [Length, Float]
        # @param opts [Hash]
        # @return [Hash]
        def calculate_layout(door_width, door_height, opts = {})
          fw = opts[:frame_width] || (Config.get(:frame_size) || 50.0).mm
          x_off = safe_to_inch(opts[:x_offset] || 0)
          w = safe_to_inch(door_width)
          h = safe_to_inch(door_height)
          is_win = !!opts[:is_window]

          has_fix_t = !!(opts[:has_fix_top] || opts[:has_glass_transom])
          has_fix_b = !!opts[:has_fix_bottom]
          has_fix_l = !!opts[:has_fix_left]
          has_fix_r = !!opts[:has_fix_right]

          fix_t_h = if has_fix_t
            if opts[:fix_top_height]
              safe_to_inch(opts[:fix_top_height])
            elsif opts[:leaf_height]
              h - safe_to_inch(opts[:leaf_height]) - 2 * fw
            else
              350.0.mm
            end
          else
            0
          end
          fix_t_h = [fix_t_h, 50.mm].max if has_fix_t

          fix_b_h = has_fix_b ? [safe_to_inch(opts[:fix_bottom_height] || 400.0.mm), 50.mm].max : 0
          fix_l_w = has_fix_l ? [safe_to_inch(opts[:fix_left_width] || 300.0.mm), 50.mm].max : 0
          fix_r_w = has_fix_r ? [safe_to_inch(opts[:fix_right_width] || 300.0.mm), 50.mm].max : 0

          # 1. Horizontal division
          x_min = x_off
          x_max = x_off + w

          if has_fix_l && fix_l_w > 0
            left_fix_x0 = x_min + fw
            left_fix_x1 = left_fix_x0 + fix_l_w
            x_act_0 = left_fix_x1 + fw
          else
            left_fix_x0 = left_fix_x1 = nil
            x_act_0 = x_min + fw
          end

          if has_fix_r && fix_r_w > 0
            right_fix_x1 = x_max - fw
            right_fix_x0 = right_fix_x1 - fix_r_w
            x_act_1 = right_fix_x0 - fw
          else
            right_fix_x0 = right_fix_x1 = nil
            x_act_1 = x_max - fw
          end

          active_w = [x_act_1 - x_act_0, 100.mm].max

          # 2. Vertical division
          z_min = 0.mm
          z_max = h

          if has_fix_b && fix_b_h > 0
            bot_fix_z0 = fw
            bot_fix_z1 = bot_fix_z0 + fix_b_h
            z_act_0 = bot_fix_z1 + fw
          else
            bot_fix_z0 = bot_fix_z1 = nil
            z_act_0 = is_win ? fw : 0.mm
          end

          if has_fix_t && fix_t_h > 0
            top_fix_z1 = z_max - fw
            top_fix_z0 = top_fix_z1 - fix_t_h
            z_act_1 = top_fix_z0 - fw
          else
            top_fix_z0 = top_fix_z1 = nil
            z_act_1 = z_max - fw
          end

          active_h = [z_act_1 - z_act_0, 100.mm].max

          {
            door_width: w,
            door_height: h,
            frame_width: fw,
            x_offset: x_off,
            is_window: is_win,
            has_fix_top: has_fix_t,
            has_fix_bottom: has_fix_b,
            has_fix_left: has_fix_l,
            has_fix_right: has_fix_r,
            active_x0: x_act_0,
            active_x1: x_act_1,
            active_width: active_w,
            active_z0: z_act_0,
            active_z1: z_act_1,
            active_height: active_h,
            top_fix: has_fix_t && fix_t_h > 0 ? { x0: x_act_0, x1: x_act_1, z0: top_fix_z0, z1: top_fix_z1, w: active_w, h: fix_t_h } : nil,
            bot_fix: has_fix_b && fix_b_h > 0 ? { x0: x_act_0, x1: x_act_1, z0: bot_fix_z0, z1: bot_fix_z1, w: active_w, h: fix_b_h } : nil,
            left_fix: has_fix_l && fix_l_w > 0 ? { x0: left_fix_x0, x1: left_fix_x1, z0: fw, z1: (z_max - fw), w: fix_l_w, h: (z_max - 2 * fw) } : nil,
            right_fix: has_fix_r && fix_r_w > 0 ? { x0: right_fix_x0, x1: right_fix_x1, z0: fw, z1: (z_max - fw), w: fix_r_w, h: (z_max - 2 * fw) } : nil
          }
        end

        # Build FRAME group structure inside parent container
        # @param parent_group [Sketchup::Group, Sketchup::Entities]
        # @param door_width [Length, Float] total door/window width
        # @param door_height [Length, Float] total door/window height
        # @param opts [Hash]
        # @return [Sketchup::Group] FRAME group
        def build_frame(parent_group, door_width, door_height, opts = {})
          target_entities = parent_group.respond_to?(:entities) ? parent_group.entities : parent_group
          material = opts[:material]

          layout = calculate_layout(door_width, door_height, opts)

          frame = target_entities.add_group
          frame.name = 'FRAME'
          entities = frame.entities

          w = layout[:door_width]
          h = layout[:door_height]
          x_off = layout[:x_offset]
          fw = layout[:frame_width]
          is_win = layout[:is_window]
          has_fix_b = layout[:has_fix_bottom]

          # Holes to cut into outer face
          holes = []

          # 1. Outer Face
          if is_win || has_fix_b
            # Closed 4-sided outer rectangle
            p_out = [
              Geom::Point3d.new(x_off, 0, 0),
              Geom::Point3d.new(x_off + w, 0, 0),
              Geom::Point3d.new(x_off + w, 0, h),
              Geom::Point3d.new(x_off, 0, h)
            ]
            outer_face = entities.add_face(p_out)

            # Active leaf hole
            holes << [layout[:active_x0], layout[:active_x1], layout[:active_z0], layout[:active_z1]]
          else
            # Door without bottom fix (U-shaped opening at bottom for active leaf)
            p_out = [
              Geom::Point3d.new(x_off, 0, 0),
              Geom::Point3d.new(layout[:active_x0], 0, 0),
              Geom::Point3d.new(layout[:active_x0], 0, layout[:active_z1]),
              Geom::Point3d.new(layout[:active_x1], 0, layout[:active_z1]),
              Geom::Point3d.new(layout[:active_x1], 0, 0),
              Geom::Point3d.new(x_off + w, 0, 0),
              Geom::Point3d.new(x_off + w, 0, h),
              Geom::Point3d.new(x_off, 0, h)
            ]
            outer_face = entities.add_face(p_out)
          end

          # Add fix panel holes
          holes << [layout[:top_fix][:x0], layout[:top_fix][:x1], layout[:top_fix][:z0], layout[:top_fix][:z1]] if layout[:top_fix]
          holes << [layout[:bot_fix][:x0], layout[:bot_fix][:x1], layout[:bot_fix][:z0], layout[:bot_fix][:z1]] if layout[:bot_fix]
          holes << [layout[:left_fix][:x0], layout[:left_fix][:x1], layout[:left_fix][:z0], layout[:left_fix][:z1]] if layout[:left_fix]
          holes << [layout[:right_fix][:x0], layout[:right_fix][:x1], layout[:right_fix][:z0], layout[:right_fix][:z1]] if layout[:right_fix]

          # Cut all inner holes
          if outer_face && outer_face.valid?
            inner_faces = []
            holes.each do |hx0, hx1, hz0, hz1|
              next unless hx0 && hx1 && hz0 && hz1 && hx1 > hx0 && hz1 > hz0
              pts = [
                Geom::Point3d.new(hx0, 0, hz0),
                Geom::Point3d.new(hx1, 0, hz0),
                Geom::Point3d.new(hx1, 0, hz1),
                Geom::Point3d.new(hx0, 0, hz1)
              ]
              f = entities.add_face(pts)
              inner_faces << f if f && f.valid?
            end

            entities.erase_entities(inner_faces.compact.select(&:valid?)) unless inner_faces.empty?
            outer_face.pushpull(-FRAME_DEPTH) if outer_face && outer_face.valid?
          end

          MaterialLoader.apply_material(frame, material) if material
          frame
        end

        # Safely convert any value to internal inches without double-conversion
        # - Length: already inches internally, just .to_f
        # - Numeric with .mm applied: already in inches, use as-is
        # - Raw mm number: should NOT be passed here; callers must .mm first
        # @param val [Length, Float, Integer, nil]
        # @return [Float] value in inches
        def safe_to_inch(val)
          return 0.0 if val.nil?
          # Length objects: .to_f returns internal inches
          # Float/Integer from .mm conversion: already in inches
          val.to_f
        end
      end
    end
  end
end
