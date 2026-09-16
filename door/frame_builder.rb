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
            elsif opts[:fix_module_height]
              safe_to_inch(opts[:fix_module_height])
            elsif opts[:leaf_height]
              h - safe_to_inch(opts[:leaf_height]) - 2 * fw
            else
              safe_to_inch((Config.get(:glass_height) || 350.0).mm)
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
            right_fix: has_fix_r && fix_r_w > 0 ? { x0: right_fix_x0, x1: right_fix_x1, z0: fw, z1: (z_max - fw), w: fix_r_w, h: (z_max - 2 * fw) } : nil,
            corner_radius: opts[:corner_radius]
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

          raw_r = opts[:corner_radius] ? opts[:corner_radius].to_f : 0.0
          r = raw_r > 0 ? [raw_r, (w / 2.0), (h - 100.mm.to_f)].min : 0.0
          inner_r = r > 1.0.mm ? [r - fw, 0.0].max : 0.0
          n_segs = 12

          # Holes to cut into outer face
          holes = []
          outer_face = nil

          # 1. Outer Face
          if is_win || has_fix_b
            p_out = []
            p_out << Geom::Point3d.new(x_off, 0, 0)
            p_out << Geom::Point3d.new(x_off + w, 0, 0)

            if r > 1.0.mm
              p_out << Geom::Point3d.new(x_off + w, 0, h - r)
              n_segs.times do |i|
                ang = (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
                px = (x_off + w - r) + r * Math.cos(ang)
                pz = (h - r) + r * Math.sin(ang)
                p_out << Geom::Point3d.new(px, 0, pz)
              end
              if (w - r) > r + 0.001.mm
                p_out << Geom::Point3d.new(x_off + r, 0, h)
              end
              n_segs.times do |i|
                ang = (Math::PI / 2.0) + (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
                px = (x_off + r) + r * Math.cos(ang)
                pz = (h - r) + r * Math.sin(ang)
                p_out << Geom::Point3d.new(px, 0, pz)
              end
            else
              p_out << Geom::Point3d.new(x_off + w, 0, h)
              p_out << Geom::Point3d.new(x_off, 0, h)
            end

            clean_p_out = []
            p_out.each do |pt|
              clean_p_out << pt if clean_p_out.empty? || clean_p_out.last.distance(pt) > 0.001.mm
            end
            outer_face = entities.add_face(clean_p_out)

            # Active leaf hole
            active_hole_r = layout[:top_fix] ? 0.0 : inner_r
            act_sides = if !layout[:has_fix_left] && !layout[:has_fix_right]
                          :both
                        elsif !layout[:has_fix_left]
                          :left
                        elsif !layout[:has_fix_right]
                          :right
                        end
            holes << [layout[:active_x0], layout[:active_x1], layout[:active_z0], layout[:active_z1], active_hole_r, act_sides]
          else
            # Door without bottom fix (U-shaped opening at bottom for active leaf)
            p_out = []
            p_out << Geom::Point3d.new(x_off, 0, 0)
            p_out << Geom::Point3d.new(layout[:active_x0], 0, 0)

            act_x0 = layout[:active_x0]
            act_x1 = layout[:active_x1]
            act_z1 = layout[:active_z1]
            active_inner_r = layout[:top_fix] ? 0.0 : inner_r
            round_act_l = active_inner_r > 1.0.mm && !layout[:has_fix_left]
            round_act_r = active_inner_r > 1.0.mm && !layout[:has_fix_right]

            if round_act_l
              p_out << Geom::Point3d.new(act_x0, 0, act_z1 - active_inner_r)
              n_segs.times do |i|
                ang = Math::PI - (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
                px = (act_x0 + active_inner_r) + active_inner_r * Math.cos(ang)
                pz = (act_z1 - active_inner_r) + active_inner_r * Math.sin(ang)
                p_out << Geom::Point3d.new(px, 0, pz)
              end
            else
              p_out << Geom::Point3d.new(act_x0, 0, act_z1)
            end

            top_act_l_x = round_act_l ? (act_x0 + active_inner_r) : act_x0
            top_act_r_x = round_act_r ? (act_x1 - active_inner_r) : act_x1
            if top_act_r_x > top_act_l_x + 0.001.mm
              p_out << Geom::Point3d.new(top_act_r_x, 0, act_z1)
            end

            if round_act_r
              n_segs.times do |i|
                ang = (Math::PI / 2.0) - (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
                px = (act_x1 - active_inner_r) + active_inner_r * Math.cos(ang)
                pz = (act_z1 - active_inner_r) + active_inner_r * Math.sin(ang)
                p_out << Geom::Point3d.new(px, 0, pz)
              end
              p_out << Geom::Point3d.new(act_x1, 0, 0)
            else
              p_out << Geom::Point3d.new(act_x1, 0, act_z1)
              p_out << Geom::Point3d.new(act_x1, 0, 0)
            end

            p_out << Geom::Point3d.new(x_off + w, 0, 0)

            if r > 1.0.mm
              p_out << Geom::Point3d.new(x_off + w, 0, h - r)
              n_segs.times do |i|
                ang = (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
                px = (x_off + w - r) + r * Math.cos(ang)
                pz = (h - r) + r * Math.sin(ang)
                p_out << Geom::Point3d.new(px, 0, pz)
              end
              if (w - r) > r + 0.001.mm
                p_out << Geom::Point3d.new(x_off + r, 0, h)
              end
              n_segs.times do |i|
                ang = (Math::PI / 2.0) + (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
                px = (x_off + r) + r * Math.cos(ang)
                pz = (h - r) + r * Math.sin(ang)
                p_out << Geom::Point3d.new(px, 0, pz)
              end
            else
              p_out << Geom::Point3d.new(x_off + w, 0, h)
              p_out << Geom::Point3d.new(x_off, 0, h)
            end

            clean_p_out = []
            p_out.each do |pt|
              clean_p_out << pt if clean_p_out.empty? || clean_p_out.last.distance(pt) > 0.001.mm
            end
            clean_p_out.pop if clean_p_out.size > 2 && clean_p_out.first.distance(clean_p_out.last) < 0.001.mm
            outer_face = entities.add_face(clean_p_out)
          end

          # Add fix panel holes
          if layout[:top_fix]
            tf_sides = if !layout[:has_fix_left] && !layout[:has_fix_right]
                         :both
                       elsif !layout[:has_fix_left]
                         :left
                       elsif !layout[:has_fix_right]
                         :right
                       end
            holes << [layout[:top_fix][:x0], layout[:top_fix][:x1], layout[:top_fix][:z0], layout[:top_fix][:z1], inner_r, tf_sides]
          end
          holes << [layout[:bot_fix][:x0], layout[:bot_fix][:x1], layout[:bot_fix][:z0], layout[:bot_fix][:z1], 0.0, nil] if layout[:bot_fix]
          if layout[:left_fix]
            lf_sides = (inner_r > 1.0.mm) ? :left : nil
            holes << [layout[:left_fix][:x0], layout[:left_fix][:x1], layout[:left_fix][:z0], layout[:left_fix][:z1], inner_r, lf_sides]
          end
          if layout[:right_fix]
            rf_sides = (inner_r > 1.0.mm) ? :right : nil
            holes << [layout[:right_fix][:x0], layout[:right_fix][:x1], layout[:right_fix][:z0], layout[:right_fix][:z1], inner_r, rf_sides]
          end

          # Cut all inner holes
          if outer_face && outer_face.valid?
            inner_faces = []
            holes.each do |hx0, hx1, hz0, hz1, hr, sides|
              next unless hx0 && hx1 && hz0 && hz1 && hx1 > hx0 && hz1 > hz0
              pts = []
              pts << Geom::Point3d.new(hx0, 0, hz0)
              pts << Geom::Point3d.new(hx1, 0, hz0)

              max_r = sides == :both ? ((hx1 - hx0) / 2.0) : (hx1 - hx0)
              cur_r = (hr && hr > 1.0.mm && sides) ? [hr, max_r, (hz1 - hz0) - 10.mm.to_f].min : 0.0
              round_r = cur_r > 1.0.mm && [:both, :right].include?(sides)
              round_l = cur_r > 1.0.mm && [:both, :left].include?(sides)

              if round_r
                pts << Geom::Point3d.new(hx1, 0, hz1 - cur_r)
                n_segs.times do |i|
                  ang = (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
                  px = (hx1 - cur_r) + cur_r * Math.cos(ang)
                  pz = (hz1 - cur_r) + cur_r * Math.sin(ang)
                  pts << Geom::Point3d.new(px, 0, pz)
                end
              else
                pts << Geom::Point3d.new(hx1, 0, hz1)
              end

              top_r_x = round_r ? (hx1 - cur_r) : hx1
              top_l_x = round_l ? (hx0 + cur_r) : hx0
              if top_r_x > top_l_x + 0.001.mm
                pts << Geom::Point3d.new(top_l_x, 0, hz1)
              end

              if round_l
                n_segs.times do |i|
                  ang = (Math::PI / 2.0) + (Math::PI / 2.0) * ((i + 1) / n_segs.to_f)
                  px = (hx0 + cur_r) + cur_r * Math.cos(ang)
                  pz = (hz1 - cur_r) + cur_r * Math.sin(ang)
                  pts << Geom::Point3d.new(px, 0, pz)
                end
              else
                last_pt = pts.last
                tl_pt = Geom::Point3d.new(hx0, 0, hz1)
                pts << tl_pt if !last_pt || last_pt.distance(tl_pt) > 0.001.mm
              end

              clean_pts = []
              pts.each { |p| clean_pts << p if clean_pts.empty? || clean_pts.last.distance(p) > 0.001.mm }
              clean_pts.pop if clean_pts.size > 2 && clean_pts.first.distance(clean_pts.last) < 0.001.mm
              next if clean_pts.size < 3

              f = entities.add_face(clean_pts)
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
