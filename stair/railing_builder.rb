# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Architectural 3D Stair Railing Generator
    # Strict geometric invariants:
    # 1. No hidden edges (visible = true, hidden = false).
    # 2. No soft or smooth edges (soft = false, smooth = false).
    # 3. Every edge is strictly parallel to X, Y, Z, or exact stair flight slope.
    # 4. Flight -> Landing -> Flight junctions are strictly axis-aligned (X, Y, Z) without arbitrary diagonals.
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

            # 1. Build continuous top Handrail with Clean Segmented Joints
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

        # Compute an explicit polyline: stair slope segments + axis-aligned landing/transition segments (pure X, pure Y, pure Z).
        # Inner railing aligns strictly along the inner stair well (giếng thang), outer aligns along walls.
        def compute_exact_railing_path(type, side, total_steps, f1, f2, f3, h, b, w, winder_mode, inset, total_h)
          nodes = []
          landing_step = winder_mode == 3 ? 2 : (winder_mode == 2 ? 1 : 0)

          case type
          when :straight
            y = side == :inner ? -inset : -(w - inset)
            nodes << Geom::Point3d.new(0, y, 0)
            nodes << Geom::Point3d.new(total_steps * b, y, total_h)

          when :l_shape
            f2n = [1, total_steps - f1 - landing_step].max
            f1_len = (f1 - 1) * b
            f2_len = (f2n - 1) * b
            z1 = (f1 - 1) * h
            zl1 = f1 * h
            z2s = zl1 + landing_step * h
            z2 = z2s + (f2n - 1) * h

            if side == :inner
              y1 = -inset
              y2 = -w - inset
              xc = f1_len + inset
              # 1. Flight 1 exact slope (+X, +Z) along inner edge
              nodes << Geom::Point3d.new(0, y1, 0)
              nodes << Geom::Point3d.new(f1_len, y1, z1)
              # 2. Landing 1: pure Z -> pure X -> pure Y -> pure Z (if winder)
              nodes << Geom::Point3d.new(f1_len, y1, zl1)
              nodes << Geom::Point3d.new(xc, y1, zl1)
              nodes << Geom::Point3d.new(xc, y2, zl1)
              nodes << Geom::Point3d.new(xc, y2, z2s) if landing_step > 0
              # 3. Flight 2 exact slope (-Y, +Z) along inner edge
              nodes << Geom::Point3d.new(xc, -w - f2_len - inset, z2)
              nodes << Geom::Point3d.new(xc, -w - f2_len - inset, total_h)
            else
              y1 = -(w - inset)
              y2 = -w
              xc = f1_len + w - inset
              # 1. Flight 1 exact slope (+X, +Z) along outer wall
              nodes << Geom::Point3d.new(0, y1, 0)
              nodes << Geom::Point3d.new(f1_len, y1, z1)
              # 2. Landing 1
              nodes << Geom::Point3d.new(f1_len, y1, zl1)
              nodes << Geom::Point3d.new(xc, y1, zl1)
              nodes << Geom::Point3d.new(xc, -w - f2_len, zl1)
              nodes << Geom::Point3d.new(xc, -w - f2_len, z2s) if landing_step > 0
              # 3. Flight 2 exact slope (-Y, +Z)
              nodes << Geom::Point3d.new(xc, -w - f2_len, total_h)
            end

          else # :u_shape_3
            f3n = [1, total_steps - f1 - f2 - (winder_mode == 3 ? 4 : (winder_mode == 2 ? 2 : 0))].max
            f1_len = (f1 - 1) * b
            f2_len = (f2 - 1) * b
            f3_len = (f3n - 1) * b
            z1 = (f1 - 1) * h
            zl1 = f1 * h
            z2s = zl1 + landing_step * h
            z2 = z2s + (f2 - 1) * h
            zl2 = z2s + f2 * h
            z3s = zl2 + landing_step * h
            z3 = z3s + (f3n - 1) * h
            f3_end_x = f1_len - (f3n - 1) * b

            if side == :inner
              y1 = -inset
              y2 = -w - inset
              y3 = -w - f2_len - inset
              xc = f1_len + inset

              # 1. Flight 1 exact slope (+X, +Z) along inner well (y = -inset)
              nodes << Geom::Point3d.new(0, y1, 0)
              nodes << Geom::Point3d.new(f1_len, y1, z1)

              # 2. Landing 1: pure Z -> pure X -> pure Y
              nodes << Geom::Point3d.new(f1_len, y1, zl1)
              nodes << Geom::Point3d.new(xc, y1, zl1)
              nodes << Geom::Point3d.new(xc, y2, zl1)
              nodes << Geom::Point3d.new(xc, y2, z2s) if landing_step > 0

              # 3. Flight 2 exact slope (-Y, +Z) along inner well (x = f1_len + inset)
              nodes << Geom::Point3d.new(xc, y3, z2)

              # 4. Landing 2: pure Z -> pure Y -> pure X
              nodes << Geom::Point3d.new(xc, y3, zl2)
              nodes << Geom::Point3d.new(xc, y3, z3s) if landing_step > 0
              nodes << Geom::Point3d.new(f1_len, y3, z3s)

              # 5. Flight 3 exact slope (-X, +Z) along inner well (y = -f2_len - inset)
              nodes << Geom::Point3d.new(f3_end_x, y3, z3)
              nodes << Geom::Point3d.new(f3_end_x, y3, total_h)
            else
              y1 = -(w - inset)
              y2 = -w
              y3 = -w - f2_len + inset
              xc = f1_len + w - inset

              # 1. Flight 1 exact slope (+X, +Z) along outer wall
              nodes << Geom::Point3d.new(0, y1, 0)
              nodes << Geom::Point3d.new(f1_len, y1, z1)

              # 2. Landing 1
              nodes << Geom::Point3d.new(f1_len, y1, zl1)
              nodes << Geom::Point3d.new(xc, y1, zl1)
              nodes << Geom::Point3d.new(xc, y2, zl1)
              nodes << Geom::Point3d.new(xc, y2, z2s) if landing_step > 0

              # 3. Flight 2 exact slope (-Y, +Z)
              nodes << Geom::Point3d.new(xc, -w - f2_len, z2)

              # 4. Landing 2
              nodes << Geom::Point3d.new(xc, -w - f2_len, zl2)
              nodes << Geom::Point3d.new(xc, y3, zl2)
              nodes << Geom::Point3d.new(xc, y3, z3s) if landing_step > 0
              nodes << Geom::Point3d.new(f1_len, y3, z3s)

              # 5. Flight 3 exact slope (-X, +Z)
              nodes << Geom::Point3d.new(f3_end_x, y3, z3)
              nodes << Geom::Point3d.new(f3_end_x, y3, total_h)
            end
          end

          cleaned = []
          nodes.each { |pt| cleaned << pt if cleaned.empty? || pt.distance(cleaned.last) > 1.mm }
          cleaned
        end

        # Build Continuous 3D Top Handrail with Planar Segments and Clean Miter Corner Faces
        # 100% planar quad faces, no twisted non-planar polygons, no gaps, no disjointed blocks.
        def build_continuous_handrail(entities, path_nodes, rail_height, profile, material)
          return if path_nodes.nil? || path_nodes.size < 2

          up_z = Geom::Vector3d.new(0, 0, 1)
          top_nodes = path_nodes.map { |p| p.offset(up_z, rail_height) }

          grp = entities.add_group
          grp.name = 'HANDRAIL'
          grp.material = material if material

          hw = (profile == :square_40 ? 20.0 : 30.0).mm
          hh = 20.0.mm

          (0...(top_nodes.size - 1)).each do |i|
            p1 = top_nodes[i]
            p2 = top_nodes[i + 1]
            vec = p2 - p1
            len = vec.length
            next if len < 1.mm

            # Determine lateral width vector in horizontal XY plane
            side_vec = if vec.x.abs >= vec.y.abs && vec.x.abs > 1e-3
                         Geom::Vector3d.new(0, 1, 0)
                       elsif vec.y.abs > 1e-3
                         Geom::Vector3d.new(1, 0, 0)
                       else
                         Geom::Vector3d.new(1, 0, 0)
                       end

            ring1 = [
              p1.offset(side_vec, -hw).offset(up_z, hh),
              p1.offset(side_vec, hw).offset(up_z, hh),
              p1.offset(side_vec, hw).offset(up_z, -hh),
              p1.offset(side_vec, -hw).offset(up_z, -hh)
            ]
            ring2 = [
              p2.offset(side_vec, -hw).offset(up_z, hh),
              p2.offset(side_vec, hw).offset(up_z, hh),
              p2.offset(side_vec, hw).offset(up_z, -hh),
              p2.offset(side_vec, -hw).offset(up_z, -hh)
            ]

            # 4 perfectly planar quad faces
            grp.entities.add_face([ring1[0], ring2[0], ring2[1], ring1[1]]) rescue nil # Top
            grp.entities.add_face([ring1[1], ring2[1], ring2[2], ring1[2]]) rescue nil # Right
            grp.entities.add_face([ring1[2], ring2[2], ring2[3], ring1[3]]) rescue nil # Bottom
            grp.entities.add_face([ring1[3], ring2[3], ring2[0], ring1[0]]) rescue nil # Left

            # Start cap on first segment, end cap on last segment
            grp.entities.add_face(ring1.reverse) rescue nil if i == 0
            grp.entities.add_face(ring2) rescue nil if i == top_nodes.size - 2
          end
        end

        # Style 1: Glass Panels (Kính Cường Lực + Chấu Inox Vuông)
        # All edges strictly parallel to X, Y, Z, or stair slope.
        def build_glass_panels(entities, path_nodes, rail_height, glass_mat, steel_mat)
          grp = entities.add_group
          grp.name = 'GLASS_PANELS'

          glass_thick = DEFAULT_GLASS_THICKNESS_MM.mm
          h_glass_top = rail_height - 25.0.mm
          h_glass_bot = 35.0.mm
          up = Geom::Vector3d.new(0, 0, 1)

          (0...(path_nodes.size - 1)).each do |i|
            begin
              b1 = path_nodes[i]
              b2 = path_nodes[i + 1]
              vec = b2 - b1
              len = vec.length
              # Skip very short segments and pure vertical riser transitions
              next if len < 40.mm || (vec.x.abs < 1e-3 && vec.y.abs < 1e-3)

              panel_grp = grp.entities.add_group
              panel_grp.name = "GLASS_PANEL_#{i + 1}"
              panel_grp.material = glass_mat if glass_mat

              # Offset each base point along Z independently to form a pure planar vertical panel
              p_b1 = b1.offset(up, h_glass_bot)
              p_b2 = b2.offset(up, h_glass_bot)
              p_t2 = b2.offset(up, h_glass_top)
              p_t1 = b1.offset(up, h_glass_top)

              face = panel_grp.entities.add_face([p_b1, p_b2, p_t2, p_t1]) rescue nil
              face.pushpull(glass_thick) if face

              # Add stainless steel square clamps at 25% and 75%
              seg_dir = vec.length > 1e-3 ? vec.normalize : Geom::Vector3d.new(1, 0, 0)
              [0.25, 0.75].each do |ratio|
                clamp_pt = b1.offset(seg_dir, len * ratio).offset(up, h_glass_bot / 2.0)
                build_square_clamp(panel_grp.entities, clamp_pt, 24.0.mm, 40.0.mm, steel_mat)
              end
            rescue StandardError => e
              Logger.error("Lỗi panel kính #{i + 1}: #{e.message}") if defined?(Logger)
              next
            end
          end
        end

        # Style 2: Vertical Balusters (Nan sắt cắm vát ăn sâu vào lòng tay vịn)
        # All edges strictly parallel to X, Y, Z, or stair slope.
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

          # 1. Place Main Newel Posts (40x40mm, all edges along X, Y, Z)
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
          balusters_data = [] # [[base_pt, flight_slope_direction, h_top_at_center, slope_gradient]]

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

            # 4 bottom vertices on tread surface (parallel to X, Y)
            b1 = base_pt.offset(vx, -hs).offset(vy, -hs)
            b2 = base_pt.offset(vx, hs).offset(vy, -hs)
            b3 = base_pt.offset(vx, hs).offset(vy, hs)
            b4 = base_pt.offset(vx, -hs).offset(vy, hs)

            # 4 top vertices with slope incline matching stair slope exactly
            t1 = b1.offset(vz, h_center + (s_dir.x * -hs + s_dir.y * -hs) * slope_grad)
            t2 = b2.offset(vz, h_center + (s_dir.x * hs + s_dir.y * -hs) * slope_grad)
            t3 = b3.offset(vz, h_center + (s_dir.x * hs + s_dir.y * hs) * slope_grad)
            t4 = b4.offset(vz, h_center + (s_dir.x * -hs + s_dir.y * hs) * slope_grad)

            # 6 faces: all edges are strictly parallel to X, Y, Z, or stair slope
            bar_grp.entities.add_face([b1, b2, b3, b4]) rescue nil # Bottom (X, Y)
            bar_grp.entities.add_face([t4, t3, t2, t1]) rescue nil # Sloped Top (stair slope, X/Y)
            bar_grp.entities.add_face([b1, b2, t2, t1]) rescue nil # Side 1 (Z, X/Y, stair slope)
            bar_grp.entities.add_face([b2, b3, t3, t2]) rescue nil # Side 2 (Z, X/Y, stair slope)
            bar_grp.entities.add_face([b3, b4, t4, t3]) rescue nil # Side 3 (Z, X/Y, stair slope)
            bar_grp.entities.add_face([b4, b1, t1, t4]) rescue nil # Side 4 (Z, X/Y, stair slope)
          end
        end

        # Style 3: Horizontal Rails (Trụ Góc Vuông + 3 Thanh Suốt Vuông Liền Mạch)
        # All edges strictly parallel to X, Y, Z, or stair slope.
        def build_horizontal_rails(entities, path_nodes, rail_height, steel_mat)
          grp = entities.add_group
          grp.name = 'HORIZONTAL_RAILS'
          grp.material = steel_mat if steel_mat

          post_size = 35.0.mm
          rail_size = 16.0.mm # 16x16mm square tube
          vx = Geom::Vector3d.new(1, 0, 0)
          vy = Geom::Vector3d.new(0, 1, 0)
          vz = Geom::Vector3d.new(0, 0, 1)

          # 1. Place vertical corner posts at key nodes extending UPWARDS (X, Y, Z)
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

          # 2. Build 3 horizontal intermediate square tubes at 25%, 50%, 75% height
          [0.25, 0.50, 0.75].each do |ratio|
            h_curr = rail_height * ratio
            (0...(path_nodes.size - 1)).each do |i|
              p1 = path_nodes[i].offset(vz, h_curr)
              p2 = path_nodes[i + 1].offset(vz, h_curr)
              build_square_tube_segment(grp.entities, p1, p2, rail_size)
            end
          end
        end

        # Helper: Build square tube segment along a path vector (X, Y, Z, or stair slope)
        def build_square_tube_segment(entities, p1, p2, size)
          vec = p2 - p1
          len = vec.length
          return if len < 1.mm

          tangent = vec.normalize
          tangent_xy = Geom::Vector3d.new(tangent.x, tangent.y, 0)
          is_vertical = tangent_xy.length <= 1e-3

          vx, vy = if is_vertical
                     [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0)]
                   else
                     side_vec = Geom::Vector3d.new(tangent_xy.y, -tangent_xy.x, 0).normalize
                     [side_vec, Geom::Vector3d.new(0, 0, 1)]
                   end
          hs = size / 2.0

          ring1 = [
            p1.offset(vx, -hs).offset(vy, -hs),
            p1.offset(vx, hs).offset(vy, -hs),
            p1.offset(vx, hs).offset(vy, hs),
            p1.offset(vx, -hs).offset(vy, hs)
          ]
          ring2 = [
            p2.offset(vx, -hs).offset(vy, -hs),
            p2.offset(vx, hs).offset(vy, -hs),
            p2.offset(vx, hs).offset(vy, hs),
            p2.offset(vx, -hs).offset(vy, hs)
          ]

          entities.add_face(ring1.reverse) rescue nil
          entities.add_face(ring2) rescue nil
          4.times do |k|
            kn = (k + 1) % 4
            entities.add_face([ring1[k], ring1[kn], ring2[kn], ring2[k]]) rescue nil
          end
        end

        # Style 4: Handrail Only with square wall brackets / mounting posts
        def build_handrail_brackets(entities, path_nodes, rail_height, steel_mat)
          grp = entities.add_group
          grp.name = 'HANDRAIL_BRACKETS'
          grp.material = steel_mat if steel_mat

          vz = Geom::Vector3d.new(0, 0, 1)
          path_nodes.each do |node|
            post_grp = grp.entities.add_group
            h_pin = rail_height - 5.0.mm
            build_square_clamp(post_grp.entities, node, 20.0.mm, h_pin, steel_mat)
          end
        end

        # Helper: Build vertical square clamp/spigot
        def build_square_clamp(entities, base_pt, size, height, mat)
          spigot_grp = entities.add_group
          spigot_grp.material = mat if mat
          vx = Geom::Vector3d.new(1, 0, 0)
          vy = Geom::Vector3d.new(0, 1, 0)
          hs = size / 2.0
          pts = [
            base_pt.offset(vx, -hs).offset(vy, -hs),
            base_pt.offset(vx, hs).offset(vy, -hs),
            base_pt.offset(vx, hs).offset(vy, hs),
            base_pt.offset(vx, -hs).offset(vy, hs)
          ]
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
