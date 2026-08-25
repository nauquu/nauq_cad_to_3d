# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Architectural 3D Stair Railing Generator
    # Precision Sloped-Top Baluster & Handrail Engine
    # Supports Glass Panels, Vertical Balusters, Horizontal Rails, and Handrail Only
    # 100% mathematically exact slope matching (h/b) for Straight, L-Shape, and U-Shape stairs
    module RailingBuilder
      DEFAULT_RAILING_HEIGHT_MM = 900.0 unless defined?(DEFAULT_RAILING_HEIGHT_MM)
      DEFAULT_INSET_MM = 50.0 unless defined?(DEFAULT_INSET_MM)
      DEFAULT_GLASS_THICKNESS_MM = 10.0 unless defined?(DEFAULT_GLASS_THICKNESS_MM)

      class << self
        # Build 3D railing assembly inside parent_group
        # @param params [Hash] stair & railing parameters
        # @param parent_group [Sketchup::Group] parent stair master group
        # @return [Sketchup::Group, nil] created railing group
        def build(params, parent_group)
          return nil unless parent_group && parent_group.valid?

          railing_opts = params[:railing] || params['railing']
          if railing_opts.is_a?(Hash)
            enabled = railing_opts[:enabled] || railing_opts['enabled']
            return nil if enabled == false || enabled == 'false'
          elsif railing_opts == false || railing_opts == 'false'
            return nil
          end

          opts = railing_opts.is_a?(Hash) ? railing_opts : {}
          style = (opts[:style] || opts['style'] || 'glass').to_sym
          side = (opts[:side] || opts['side'] || 'inner').to_sym
          height_mm = (opts[:height] || opts['height'] || DEFAULT_RAILING_HEIGHT_MM).to_f
          height_mm = DEFAULT_RAILING_HEIGHT_MM if height_mm < 600.0 || height_mm > 1500.0

          profile = (opts[:handrail_profile] || opts['handrail_profile'] || 'rect_60_40').to_sym
          inset_mm = (opts[:inset] || opts['inset'] || DEFAULT_INSET_MM).to_f

          # Extract stair parameters
          type = (params[:type] || params['type'] || 'u_shape_3').to_sym
          floor_height = (params[:floor_height] || params['floor_height'] || 3600.0).to_f.mm
          total_steps = (params[:total_steps] || params['total_steps'] || 21).to_i
          total_steps = 21 if total_steps < 3

          stair_width = (params[:stair_width] || params['stair_width'] || 1000.0).to_f.mm
          tread_run = (params[:tread_run] || params['tread_run'] || 270.0).to_f.mm
          flight1_steps = (params[:flight1_steps] || params['flight1_steps'] || 8).to_i
          flight2_steps = (params[:flight2_steps] || params['flight2_steps'] || 5).to_i
          flight3_steps = (params[:flight3_steps] || params['flight3_steps'] || (total_steps - flight1_steps - flight2_steps)).to_i
          riser_height = floor_height / total_steps.to_f

          raw_winder = params[:winder_landing] || params['winder_landing']
          winder_mode = if raw_winder.to_s == '3' || raw_winder == 3
                          3
                        elsif raw_winder == true || raw_winder == 'true' || raw_winder == 1 || raw_winder.to_s == '2' || raw_winder == 2
                          2
                        else
                          0
                        end

          # Create Railing Container Group inside parent_group
          railing_group = parent_group.entities.add_group
          railing_group.name = 'NAUQ_STAIR_RAILING'
          Attribute.tag(railing_group, 'stair_railing', {
            'style' => style.to_s,
            'side' => side.to_s,
            'height_mm' => height_mm,
            'profile' => profile.to_s
          })

          sides_to_build = case side
                           when :both then [:inner, :outer]
                           when :outer then [:outer]
                           else [:inner]
                           end

          materials = setup_materials(Sketchup.active_model)

          sides_to_build.each do |s|
            path_nodes = compute_exact_railing_path(
              type, s, total_steps, flight1_steps, flight2_steps, flight3_steps,
              riser_height, tread_run, stair_width, winder_mode, inset_mm.mm, floor_height
            )
            next if path_nodes.empty? || path_nodes.size < 2

            side_group = railing_group.entities.add_group
            side_group.name = "RAILING_#{s.to_s.upcase}"

            # 1. Build continuous top Handrail with Clean Miter Joints
            build_continuous_handrail(side_group.entities, path_nodes, height_mm.mm, profile, materials[:wood])

            # 2. Build Infill according to selected style
            case style
            when :glass
              build_glass_panels(side_group.entities, path_nodes, height_mm.mm, materials[:glass], materials[:steel])
            when :vertical_bars
              build_vertical_balusters(
                side_group.entities, path_nodes, height_mm.mm, materials[:metal],
                type, s, total_steps, flight1_steps, flight2_steps, flight3_steps,
                riser_height, tread_run, stair_width, winder_mode, inset_mm.mm, floor_height
              )
            when :horizontal_rails
              build_horizontal_rails(side_group.entities, path_nodes, height_mm.mm, materials[:steel])
            else # :handrail_only
              build_handrail_brackets(side_group.entities, path_nodes, height_mm.mm, materials[:steel])
            end
          end

          Logger.info("Đã tạo Lan can #{style} (#{side}, cao #{height_mm.round(0)}mm) cho cầu thang #{type}.") if defined?(Logger)
          railing_group
        end

        private

        # Compute continuous 3D key path connecting landing corner newel posts with exact slope (h/b)
        def compute_exact_railing_path(type, side, total_steps, f1, f2, f3, h, b, w, winder_mode, inset, total_h)
          nodes = []

          case type
          when :straight
            y_pos = side == :inner ? -inset : -(w - inset)
            nodes << Geom::Point3d.new(0, y_pos, 0)
            nodes << Geom::Point3d.new((total_steps - 1) * b, y_pos, (total_steps - 1) * h)
            nodes << Geom::Point3d.new(total_steps * b, y_pos, total_h)

          when :l_shape
            landing_extra = winder_mode == 3 ? 2 : (winder_mode == 2 ? 1 : 0)
            f2_actual = [1, total_steps - f1 - landing_extra].max
            f1_len = (f1 - 1) * b
            f2_len = (f2_actual - 1) * b
            z1 = (f1 - 1) * h
            z1_landing = f1 * h
            z2_start = z1_landing + landing_extra * h

            if side == :inner
              # Inner Giếng Thang
              nodes << Geom::Point3d.new(0, -(w - inset), 0)
              nodes << Geom::Point3d.new(f1_len, -(w - inset), z1)
              nodes << Geom::Point3d.new(f1_len + inset, -(w - inset), z1_landing)
              nodes << Geom::Point3d.new(f1_len + inset, -w - inset, z2_start)
              nodes << Geom::Point3d.new(f1_len + inset, -w - f2_len, z2_start + f2_len / b * h)
              nodes << Geom::Point3d.new(f1_len + inset, -w - f2_len - b, total_h)
            else
              # Outer Sát Tường
              nodes << Geom::Point3d.new(0, -inset, 0)
              nodes << Geom::Point3d.new(f1_len + w - inset, -inset, z1_landing)
              nodes << Geom::Point3d.new(f1_len + w - inset, -w, z2_start)
              nodes << Geom::Point3d.new(f1_len + w - inset, -w - f2_len, total_h)
            end

          else # :u_shape_3
            landing_extra = winder_mode == 3 ? 4 : (winder_mode == 2 ? 2 : 0)
            f3_actual = [1, total_steps - f1 - f2 - landing_extra].max
            f1_len = (f1 - 1) * b
            f2_len = (f2 - 1) * b
            f3_len = (f3_actual - 1) * b
            l1_extra = winder_mode == 3 ? 2 : (winder_mode == 2 ? 1 : 0)

            z1 = (f1 - 1) * h
            z1_landing = f1 * h
            z2_start = z1_landing + l1_extra * h
            z2 = z2_start + (f2 - 1) * h
            z2_landing = z2_start + f2 * h
            z3_start = z2_landing + l1_extra * h
            z3_top = z3_start + (f3_actual - 1) * h
            f3_end_x = f1_len - f3_len

            if side == :inner
              # Inner Giếng Thang: Chân thang -> Đỉnh Vế 1 -> Góc Chiếu nghỉ 1 -> Đỉnh Vế 2 -> Góc Chiếu nghỉ 2 -> Đỉnh Vế 3 -> Sàn tầng 2
              nodes << Geom::Point3d.new(0, -(w - inset), 0)
              nodes << Geom::Point3d.new(f1_len, -(w - inset), z1)
              nodes << Geom::Point3d.new(f1_len + inset, -(w - inset), z1_landing)
              nodes << Geom::Point3d.new(f1_len + inset, -w - inset, z2_start)
              nodes << Geom::Point3d.new(f1_len + inset, -w - f2_len, z2)
              nodes << Geom::Point3d.new(f1_len + inset, -w - f2_len - inset, z2_landing)
              nodes << Geom::Point3d.new(f1_len, -w - f2_len - inset, z3_start)
              nodes << Geom::Point3d.new(f3_end_x, -w - f2_len - inset, z3_top)
              nodes << Geom::Point3d.new(f3_end_x, -w - f2_len - inset, total_h)
            else
              # Outer Sát Tường
              nodes << Geom::Point3d.new(0, -inset, 0)
              nodes << Geom::Point3d.new(f1_len + w - inset, -inset, z1_landing)
              nodes << Geom::Point3d.new(f1_len + w - inset, -w, z2_start)
              nodes << Geom::Point3d.new(f1_len + w - inset, -w - f2_len, z2_landing)
              nodes << Geom::Point3d.new(f1_len + w - inset, -2 * w - f2_len + inset, z3_start)
              nodes << Geom::Point3d.new(f3_end_x, -2 * w - f2_len + inset, z3_top)
              nodes << Geom::Point3d.new(f3_end_x, -2 * w - f2_len + inset, total_h)
            end
          end

          # Clean consecutive duplicate points
          cleaned = []
          nodes.each do |pt|
            cleaned << pt if cleaned.empty? || pt.distance(cleaned.last) > 1.mm
          end
          cleaned
        end

        # Build Continuous 3D Top Handrail with Zero-Twist Constant Upright Cross-Sections & Clean Miter Joints
        def build_continuous_handrail(entities, path_nodes, rail_height, profile, material)
          return if path_nodes.size < 2

          grp = entities.add_group
          grp.name = 'HANDRAIL'
          grp.material = material if material

          up_z = Geom::Vector3d.new(0, 0, 1)
          top_nodes = path_nodes.map { |p| p.offset(up_z, rail_height) }

          num_nodes = top_nodes.size
          cross_sections = []

          (0...num_nodes).each do |i|
            pt = top_nodes[i]

            # 3D Tangent vector
            t_vec = if i == 0
                      (top_nodes[1] - top_nodes[0]).normalize
                    elsif i == num_nodes - 1
                      (top_nodes[num_nodes - 1] - top_nodes[num_nodes - 2]).normalize
                    else
                      v_prev = (top_nodes[i] - top_nodes[i - 1]).normalize
                      v_next = (top_nodes[i + 1] - top_nodes[i]).normalize
                      bisect = v_prev + v_next
                      bisect.length < 1e-4 ? v_next : bisect.normalize
                    end

            t_xy = Geom::Vector3d.new(t_vec.x, t_vec.y, 0)
            side_vec = if t_xy.length < 1e-4
                         Geom::Vector3d.new(1, 0, 0)
                       else
                         Geom::Vector3d.new(t_xy.y, -t_xy.x, 0).normalize
                       end

            case profile
            when :round_50
              radius = 25.0.mm
              num_segs = 16
              ring = []
              (0...num_segs).each do |idx|
                angle = (2.0 * Math::PI * idx) / num_segs
                ring << pt.offset(side_vec, radius * Math.cos(angle)).offset(up_z, radius * Math.sin(angle))
              end
              cross_sections << ring

            else # :rect_60_40 (or :square_40) with 8-point subtle chamfered profile
              hw = (profile == :square_40 ? 20.0 : 30.0).mm
              hh = 20.0.mm
              cr = 4.0.mm # 4mm rounded corner chamfer

              ring = [
                # Top side
                pt.offset(side_vec, -hw + cr).offset(up_z, hh),
                pt.offset(side_vec, hw - cr).offset(up_z, hh),
                # Right side
                pt.offset(side_vec, hw).offset(up_z, hh - cr),
                pt.offset(side_vec, hw).offset(up_z, -hh + cr),
                # Bottom side
                pt.offset(side_vec, hw - cr).offset(up_z, -hh),
                pt.offset(side_vec, -hw + cr).offset(up_z, -hh),
                # Left side
                pt.offset(side_vec, -hw).offset(up_z, -hh + cr),
                pt.offset(side_vec, -hw).offset(up_z, hh - cr)
              ]
              cross_sections << ring
            end
          end

          # Triangulated loft between adjacent rings with Soft/Smooth surface shading
          (0...(num_nodes - 1)).each do |i|
            r1 = cross_sections[i]
            r2 = cross_sections[i + 1]
            seg_count = r1.size

            (0...seg_count).each do |k|
              k_next = (k + 1) % seg_count
              f1 = grp.entities.add_face([r1[k], r2[k], r2[k_next]]) rescue nil
              f2 = grp.entities.add_face([r1[k], r2[k_next], r1[k_next]]) rescue nil

              [f1, f2].compact.each do |f|
                f.edges.each do |e|
                  e.soft = true
                  e.smooth = true
                end
              end
            end
          end

          # Add start & end caps (keep cap perimeter edges sharp)
          grp.entities.add_face(cross_sections.first) rescue nil
          grp.entities.add_face(cross_sections.last.reverse) rescue nil
        end

        # Style 1: Glass Panels (Kính Cường Lực + Chấu Inox)
        def build_glass_panels(entities, path_nodes, rail_height, glass_mat, steel_mat)
          grp = entities.add_group
          grp.name = 'GLASS_PANELS'

          glass_thick = DEFAULT_GLASS_THICKNESS_MM.mm
          h_glass_top = rail_height - 25.0.mm
          h_glass_bot = 35.0.mm
          up = Geom::Vector3d.new(0, 0, 1)

          (0...(path_nodes.size - 1)).each do |i|
            b1 = path_nodes[i]
            b2 = path_nodes[i + 1]
            vec = b2 - b1
            len = vec.length
            next if len < 40.mm

            panel_grp = grp.entities.add_group
            panel_grp.name = "GLASS_PANEL_#{i + 1}"
            panel_grp.material = glass_mat if glass_mat

            p_b1 = b1.offset(up, h_glass_bot)
            p_b2 = b2.offset(up, h_glass_bot)
            p_t2 = b2.offset(up, h_glass_top)
            p_t1 = b1.offset(up, h_glass_top)

            face = panel_grp.entities.add_face([p_b1, p_b2, p_t2, p_t1])
            face.pushpull(glass_thick) if face

            # Add stainless steel spigot clamps at 25% and 75%
            [0.25, 0.75].each do |ratio|
              clamp_pt = b1.offset(vec.normalize, len * ratio).offset(up, h_glass_bot / 2.0)
              build_cylinder_spigot(panel_grp.entities, clamp_pt, 16.0.mm, 40.0.mm, steel_mat)
            end
          end
        end

        # Style 2: Vertical Balusters (Nan sắt cắm vát ăn sâu vào lòng tay vịn)
        def build_vertical_balusters(entities, path_nodes, rail_height, metal_mat, type, side, total_steps, f1, f2, f3, h, b, w, winder_mode, inset, total_h)
          grp = entities.add_group
          grp.name = 'VERTICAL_BALUSTERS'
          grp.material = metal_mat if metal_mat

          bar_size = 14.0.mm
          vx = Geom::Vector3d.new(1, 0, 0)
          vy = Geom::Vector3d.new(0, 1, 0)
          vz = Geom::Vector3d.new(0, 0, 1)

          f1_len = (f1 - 1) * b
          f2_len = (f2 - 1) * b
          f3_actual = [1, total_steps - f1 - f2 - (winder_mode == 3 ? 4 : (winder_mode == 2 ? 2 : 0))].max
          l1_extra = winder_mode == 3 ? 2 : (winder_mode == 2 ? 1 : 0)
          z1_landing = f1 * h
          z2_start = z1_landing + l1_extra * h
          z2_landing = z2_start + f2 * h
          z3_start = z2_landing + l1_extra * h
          f3_end_x = f1_len - (f3_actual - 1) * b

          # 1. Place Main Newel Posts (40x40mm)
          posts_to_build = []
          case type
          when :straight
            y_pos = side == :inner ? -inset : -(w - inset)
            posts_to_build << [Geom::Point3d.new(0, y_pos, 0), rail_height]
            posts_to_build << [Geom::Point3d.new(total_steps * b, y_pos, total_h), rail_height]

          when :l_shape
            f2_actual_l = [1, total_steps - f1 - (winder_mode == 3 ? 2 : (winder_mode == 2 ? 1 : 0))].max
            f2_len_l = (f2_actual_l - 1) * b
            if side == :inner
              posts_to_build << [Geom::Point3d.new(0, -(w - inset), 0), rail_height]
              posts_to_build << [Geom::Point3d.new(f1_len + inset, -(w - inset), z1_landing), rail_height]
              posts_to_build << [Geom::Point3d.new(f1_len + inset, -w - f2_len_l, total_h), rail_height]
            end

          else # :u_shape_3
            if side == :inner
              posts_to_build << [Geom::Point3d.new(0, -(w - inset), 0), rail_height]
              posts_to_build << [Geom::Point3d.new(f1_len + inset, -(w - inset), z1_landing), rail_height]
              posts_to_build << [Geom::Point3d.new(f1_len + inset, -w - f2_len - inset, z2_landing), rail_height]
              posts_to_build << [Geom::Point3d.new(f3_end_x, -w - f2_len - inset, total_h), rail_height]
            end
          end

          posts_to_build.each do |node_data|
            node = node_data[0]
            h_post = node_data[1] - 5.0.mm
            post_grp = grp.entities.add_group
            hs = 20.0.mm
            pts = [
              node.offset(vx, -hs).offset(vy, -hs),
              node.offset(vx, hs).offset(vy, -hs),
              node.offset(vx, hs).offset(vy, hs),
              node.offset(vx, -hs).offset(vy, hs)
            ]
            face = post_grp.entities.add_face(pts)
            if face
              face.normal.z > 0 ? face.pushpull(h_post) : face.pushpull(-h_post)
            end
          end

          # 2. Place vertical balusters directly on step treads with Sloped Top Cutting into Handrail
          balusters_data = [] # [[base_pt, flight_slope_direction, h_top_at_center]]

          case type
          when :straight
            y_pos = side == :inner ? -(w - inset) : -inset
            slope_dir = Geom::Vector3d.new(1, 0, 0)
            (1...total_steps).each do |i|
              base_pt = Geom::Point3d.new((i - 0.5) * b, y_pos, i * h)
              h_bar = rail_height - 0.5 * h + 5.0.mm
              balusters_data << [base_pt, slope_dir, h_bar, h / b]
            end

          when :l_shape
            landing_extra = winder_mode == 3 ? 2 : (winder_mode == 2 ? 1 : 0)
            f2_actual_l = [1, total_steps - f1 - landing_extra].max
            if side == :inner
              # Flight 1
              (1...f1).each do |i|
                base_pt = Geom::Point3d.new((i - 0.5) * b, -(w - inset), i * h)
                h_bar = rail_height - 0.5 * h + 5.0.mm
                balusters_data << [base_pt, Geom::Vector3d.new(1, 0, 0), h_bar, h / b]
              end
              # Flight 2
              (1...f2_actual_l).each do |j|
                base_pt = Geom::Point3d.new(f1_len + inset, -w - (j - 0.5) * b, z2_start + j * h)
                h_bar = rail_height - 0.5 * h + 5.0.mm
                balusters_data << [base_pt, Geom::Vector3d.new(0, -1, 0), h_bar, h / b]
              end
            end

          else # :u_shape_3
            if side == :inner
              # Flight 1: dốc lên theo +X
              (1...f1).each do |i|
                base_pt = Geom::Point3d.new((i - 0.5) * b, -(w - inset), i * h)
                h_bar = rail_height - 0.5 * h + 5.0.mm
                balusters_data << [base_pt, Geom::Vector3d.new(1, 0, 0), h_bar, h / b]
              end
              # Flight 2: dốc lên theo -Y
              (1...f2).each do |j|
                base_pt = Geom::Point3d.new(f1_len + inset, -w - (j - 0.5) * b, z2_start + j * h)
                h_bar = rail_height - 0.5 * h + 5.0.mm
                balusters_data << [base_pt, Geom::Vector3d.new(0, -1, 0), h_bar, h / b]
              end
              # Flight 3: dốc lên theo -X
              (1...f3_actual).each do |k|
                base_pt = Geom::Point3d.new(f1_len - (k - 0.5) * b, -w - f2_len - inset, z3_start + k * h)
                h_bar = rail_height - 0.5 * h + 5.0.mm
                balusters_data << [base_pt, Geom::Vector3d.new(-1, 0, 0), h_bar, h / b]
              end
            end
          end

          # Create 6-sided solid baluster with sloped top face matching handrail pitch exactly
          balusters_data.each do |b_data|
            base_pt = b_data[0]
            s_dir = b_data[1]
            h_center = b_data[2]
            slope_grad = b_data[3]

            bar_grp = grp.entities.add_group
            hs = bar_size / 2.0

            # 4 bottom vertices on tread surface
            b1 = base_pt.offset(vx, -hs).offset(vy, -hs)
            b2 = base_pt.offset(vx, hs).offset(vy, -hs)
            b3 = base_pt.offset(vx, hs).offset(vy, hs)
            b4 = base_pt.offset(vx, -hs).offset(vy, hs)

            # 4 top vertices with slope incline
            t1 = b1.offset(vz, h_center + (s_dir.x * -hs + s_dir.y * -hs) * slope_grad)
            t2 = b2.offset(vz, h_center + (s_dir.x * hs + s_dir.y * -hs) * slope_grad)
            t3 = b3.offset(vz, h_center + (s_dir.x * hs + s_dir.y * hs) * slope_grad)
            t4 = b4.offset(vz, h_center + (s_dir.x * -hs + s_dir.y * hs) * slope_grad)

            # 6 faces
            bar_grp.entities.add_face([b1, b2, b3, b4]) rescue nil # Bottom
            bar_grp.entities.add_face([t4, t3, t2, t1]) rescue nil # Sloped Top
            bar_grp.entities.add_face([b1, b2, t2, t1]) rescue nil # Side 1
            bar_grp.entities.add_face([b2, b3, t3, t2]) rescue nil # Side 2
            bar_grp.entities.add_face([b3, b4, t4, t3]) rescue nil # Side 3
            bar_grp.entities.add_face([b4, b1, t1, t4]) rescue nil # Side 4
          end
        end

        # Style 3: Horizontal Rails (Trụ Góc + 3 Thanh Suốt Ngang Liền Mạch)
        def build_horizontal_rails(entities, path_nodes, rail_height, steel_mat)
          grp = entities.add_group
          grp.name = 'HORIZONTAL_RAILS'
          grp.material = steel_mat if steel_mat

          post_size = 35.0.mm
          rail_radius = 8.0.mm # Ø16mm
          vx = Geom::Vector3d.new(1, 0, 0)
          vy = Geom::Vector3d.new(0, 1, 0)
          vz = Geom::Vector3d.new(0, 0, 1)

          # 1. Place vertical corner posts at key nodes extending UPWARDS
          path_nodes.each do |node|
            post_grp = grp.entities.add_group
            hs = post_size / 2.0
            pts = [
              node.offset(vx, -hs).offset(vy, -hs),
              node.offset(vx, hs).offset(vy, -hs),
              node.offset(vx, hs).offset(vy, hs),
              node.offset(vx, -hs).offset(vy, hs)
            ]
            face = post_grp.entities.add_face(pts)
            if face
              h_post = rail_height - 5.0.mm
              face.normal.z > 0 ? face.pushpull(h_post) : face.pushpull(-h_post)
            end
          end

          # 2. Sweep 3 continuous horizontal intermediate tubes at 25%, 50%, 75% height
          [0.25, 0.50, 0.75].each do |ratio|
            h_curr = rail_height * ratio
            tube_nodes = path_nodes.map { |p| p.offset(vz, h_curr) }
            tube_grp = grp.entities.add_group
            sweep_continuous_pipe(tube_grp.entities, tube_nodes, rail_radius)
          end
        end

        # Style 4: Handrail Only with wall brackets / mounting posts
        def build_handrail_brackets(entities, path_nodes, rail_height, steel_mat)
          grp = entities.add_group
          grp.name = 'HANDRAIL_BRACKETS'
          grp.material = steel_mat if steel_mat

          vz = Geom::Vector3d.new(0, 0, 1)
          path_nodes.each do |node|
            post_grp = grp.entities.add_group
            radius = 12.0.mm # Ø24mm vertical mount pin
            h_pin = rail_height - 5.0.mm
            build_pipe_segment(post_grp.entities, node, node.offset(vz, h_pin), radius)
          end
        end

        # Helper: Sweep continuous cylindrical pipe through polyline nodes
        def sweep_continuous_pipe(entities, nodes, radius)
          return if nodes.size < 2

          up_z = Geom::Vector3d.new(0, 0, 1)
          num_nodes = nodes.size
          cross_sections = []
          num_segs = 12

          (0...num_nodes).each do |i|
            pt = nodes[i]
            t_vec = if i == 0
                      (nodes[1] - nodes[0]).normalize
                    elsif i == num_nodes - 1
                      (nodes[num_nodes - 1] - nodes[num_nodes - 2]).normalize
                    else
                      v_prev = (nodes[i] - nodes[i - 1]).normalize
                      v_next = (nodes[i + 1] - nodes[i]).normalize
                      bisect = v_prev + v_next
                      bisect.length < 1e-4 ? v_next : bisect.normalize
                    end

            t_xy = Geom::Vector3d.new(t_vec.x, t_vec.y, 0)
            side_vec = if t_xy.length < 1e-4
                         Geom::Vector3d.new(1, 0, 0)
                       else
                         Geom::Vector3d.new(t_xy.y, -t_xy.x, 0).normalize
                       end

            ring = []
            (0...num_segs).each do |idx|
              angle = (2.0 * Math::PI * idx) / num_segs
              ring << pt.offset(side_vec, radius * Math.cos(angle)).offset(up_z, radius * Math.sin(angle))
            end
            cross_sections << ring
          end

          (0...(num_nodes - 1)).each do |i|
            r1 = cross_sections[i]
            r2 = cross_sections[i + 1]
            (0...num_segs).each do |k|
              k_next = (k + 1) % num_segs
              f1 = entities.add_face([r1[k], r2[k], r2[k_next]]) rescue nil
              f2 = entities.add_face([r1[k], r2[k_next], r1[k_next]]) rescue nil
              [f1, f2].compact.each do |f|
                f.edges.each do |e|
                  e.soft = true
                  e.smooth = true
                end
              end
            end
          end

          entities.add_face(cross_sections.first) rescue nil
          entities.add_face(cross_sections.last.reverse) rescue nil
        end

        # Helper: Build cylindrical pipe between two points
        def build_pipe_segment(entities, p1, p2, radius)
          vec = p2 - p1
          len = vec.length
          return if len < 1.mm

          fwd = vec.normalize
          up_temp = Geom::Vector3d.new(0, 0, 1)
          side_vec = (fwd.parallel?(up_temp) ? Geom::Vector3d.new(1, 0, 0) : fwd.cross(up_temp)).normalize
          norm_up_vec = side_vec.cross(fwd).normalize

          num_segs = 8
          pts = []
          (0...num_segs).each do |deg_idx|
            angle = (2.0 * Math::PI * deg_idx) / num_segs
            pts << p1.offset(side_vec, radius * Math.cos(angle)).offset(norm_up_vec, radius * Math.sin(angle))
          end
          face = entities.add_face(pts)
          if face
            face.normal.samedirection?(fwd) ? face.pushpull(-len) : face.pushpull(len)
          end
        end

        # Helper: Build vertical cylindrical clamp/spigot
        def build_cylinder_spigot(entities, base_pt, radius, height, mat)
          spigot_grp = entities.add_group
          spigot_grp.material = mat if mat
          pts = []
          num_segs = 12
          vx = Geom::Vector3d.new(1, 0, 0)
          vy = Geom::Vector3d.new(0, 1, 0)
          (0...num_segs).each do |idx|
            angle = (2.0 * Math::PI * idx) / num_segs
            pts << base_pt.offset(vx, radius * Math.cos(angle)).offset(vy, radius * Math.sin(angle))
          end
          face = spigot_grp.entities.add_face(pts)
          if face
            face.normal.z > 0 ? face.pushpull(height) : face.pushpull(-height)
          end
        end

        # Setup standard materials for railing rendering
        def setup_materials(model)
          mats = model.materials

          # 1. Glass (Translucent)
          glass = mats['NAUQ_Material_Glass'] || mats.add('NAUQ_Material_Glass')
          glass.color = Sketchup::Color.new(210, 235, 245)
          glass.alpha = 0.35

          # 2. Wood Handrail
          wood = mats['NAUQ_Material_Wood_Handrail'] || mats.add('NAUQ_Material_Wood_Handrail')
          wood.color = Sketchup::Color.new(165, 115, 65)

          # 3. Metal Dark (Black Iron)
          metal = mats['NAUQ_Material_Metal_Dark'] || mats.add('NAUQ_Material_Metal_Dark')
          metal.color = Sketchup::Color.new(45, 45, 48)

          # 4. Stainless Steel
          steel = mats['NAUQ_Material_Steel'] || mats.add('NAUQ_Material_Steel')
          steel.color = Sketchup::Color.new(215, 220, 225)

          { glass: glass, wood: wood, metal: metal, steel: steel }
        end
      end
    end
  end
end
