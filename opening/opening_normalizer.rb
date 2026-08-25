# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Normalizes opening dimensions and determines geometric properties (edge_left, edge_right,
    # wall_thickness, wall_direction, linecenter, open_start, open_end, opening_bottom_z, opening_top_z)
    # by intersecting opening bounding boxes with 0-netcat wall boundaries.
    module OpeningNormalizer
      class << self
        # Normalize opening position, direction, wall thickness, and dimensions for all openings
        # @param openings [Array<Hash>] raw detected openings
        # @param walls_group [Sketchup::Group, nil] NAUQ_WALLS group container (contains reference edges/faces)
        # @param cad_group [Sketchup::Group, nil] NAUQ_CAD_ORIGINAL group
        # @return [Array<Hash>] normalized openings
        def normalize_all(openings, walls_group = nil, cad_group = nil)
          return [] if openings.empty?

          wall_segments = collect_wall_segments(walls_group, cad_group)
          base_z = determine_base_z(walls_group, wall_segments)

          normalized = []

          openings.each do |op|
            norm_op = normalize_single_opening(op, wall_segments, base_z, walls_group)
            next unless norm_op

            normalized << norm_op
          end

          Logger.info("OpeningNormalizer: Đã chuẩn hóa thành công #{normalized.size}/#{openings.size} lỗ mở.")
          normalized
        end

        private

        # Collect 2D wall boundary segments from reference or CAD
        def collect_wall_segments(walls_group, cad_group)
          # 1. From WallBuilder reference data if available
          if defined?(WallBuilder) && walls_group && walls_group.valid?
            ref_data = WallBuilder.instance_variable_get(:@reference_data)
            ref = ref_data ? (ref_data[walls_group.object_id] || (walls_group.respond_to?(:entityID) ? ref_data[walls_group.entityID] : nil)) : nil
            if ref && ref[:cleaned_pairs] && !ref[:cleaned_pairs].empty?
              return ref[:cleaned_pairs]
            end
          end

          # 2. From walls_group entities (cleaned edges added at base_z)
          if walls_group && walls_group.valid?
            edges = walls_group.entities.grep(Sketchup::Edge)
            if !edges.empty?
              # Filter horizontal edges (Z difference near zero)
              horizontal_edges = edges.select do |e|
                (e.start.position.z - e.end.position.z).abs < 0.01
              end
              if !horizontal_edges.empty?
                return horizontal_edges.map { |e| [e.start.position, e.end.position] }
              end
            end
          end

          # 3. From cad_group 0-netcat layer
          if cad_group && cad_group.valid?
            raw_segs = WallDetector.detect_wall_segments(cad_group)
            cleaned = WallCleanup.cleanup_segments(raw_segs)
            return cleaned unless cleaned.empty?
          end

          []
        end

        def determine_base_z(walls_group, wall_segments)
          if defined?(WallBuilder) && walls_group && walls_group.valid?
            ref = WallBuilder.instance_variable_get(:@reference_data)&.[](walls_group.object_id)
            return ref[:base_z] if ref && ref[:base_z]
          end

          if wall_segments && !wall_segments.empty?
            return wall_segments.flatten.map(&:z).min
          end

          0.0
        end

        # Normalize a single opening using 2-overlap / wall edge matching
        def normalize_single_opening(op, wall_segments, base_z, walls_group)
          norm_op = op.dup
          op_id = op[:id] || "OPENING_#{op[:type]}"

          # Candidate BBox & Direction
          bbox_info = compute_candidate_bbox(op)
          cand_dir = op[:direction] && op[:direction].valid? ? op[:direction].normalize : Geom::Vector3d.new(1, 0, 0)

          # Find nearby wall segments within search radius (150mm margin)
          search_margin = Geometry.mm_to_inch(150.0)
          nearby_segments = find_nearby_segments(wall_segments, bbox_info, search_margin)

          # Step 4 & 5: Match 2 wall edges (edge_left, edge_right)
          matched_edges = match_wall_edges(op, nearby_segments, cand_dir)

          unless matched_edges
            Logger.warn("Opening #{op_id}: Không tìm thấy đủ 2 cạnh mép tường (edge_left, edge_right) hợp lệ -> Bỏ qua không tạo cửa.")
            return nil
          end

          edge_left = matched_edges[:edge_left]
          edge_right = matched_edges[:edge_right]

          # Step 6: Determine wall thickness & enforce 100mm tolerance between left and right edges
          e_left_len_in = edge_left[0].distance(edge_left[1])
          e_right_len_in = edge_right[0].distance(edge_right[1])
          e_left_len_mm = Geometry.inch_to_mm(e_left_len_in)
          e_right_len_mm = Geometry.inch_to_mm(e_right_len_in)
          length_diff_mm = (e_left_len_mm - e_right_len_mm).abs

          if length_diff_mm > 100.0
            Logger.warn("Opening #{op_id}: Bỏ qua tạo cửa do độ dài cạnh trái (edge_left: #{e_left_len_mm.round(1)}mm) và cạnh phải (edge_right: #{e_right_len_mm.round(1)}mm) lệch nhau quá 100mm (#{length_diff_mm.round(1)}mm).")
            return nil
          end

          avg_thick_in = (e_left_len_in + e_right_len_in) / 2.0
          wall_thickness_mm = Geometry.inch_to_mm(avg_thick_in)
          wall_thickness_mm = 220.0 if wall_thickness_mm < 30.0

          # Step 7: Determine wall direction (perpendicular to edge_left and edge_right)
          mid_left = Geom::Point3d.new(
            (edge_left[0].x + edge_left[1].x) / 2.0,
            (edge_left[0].y + edge_left[1].y) / 2.0,
            base_z
          )
          mid_right = Geom::Point3d.new(
            (edge_right[0].x + edge_right[1].x) / 2.0,
            (edge_right[0].y + edge_right[1].y) / 2.0,
            base_z
          )

          span_vec = mid_right - mid_left
          if span_vec.length < 1.0e-6
            Logger.warn("Opening #{op_id}: edge_left và edge_right trùng nhau -> Bỏ qua không tạo cửa.")
            return nil
          end

          wall_dir = Geom::Vector3d.new(span_vec.x, span_vec.y, 0).normalize
          wall_norm = Geom::Vector3d.new(-wall_dir.y, wall_dir.x, 0).normalize

          # Step 8: Linecenter
          linecenter = { origin: mid_left, direction: wall_dir }

          # Step 9: Compute open_start and open_end
          open_start = Geometry.line_segment_intersection_2d(mid_left, wall_dir, edge_left[0], edge_left[1]) || mid_left
          open_end = Geometry.line_segment_intersection_2d(mid_left, wall_dir, edge_right[0], edge_right[1]) || mid_right
          open_start = Geom::Point3d.new(open_start.x, open_start.y, base_z)
          open_end = Geom::Point3d.new(open_end.x, open_end.y, base_z)

          raw_width_mm = Geometry.inch_to_mm(open_start.distance(open_end))
          norm_width_mm = Geometry.round_to_grid(raw_width_mm, 10.0, 5.0)

          # Step 10: Elevations from Dialog / Config (Priority to specific opening's height/offset)
          if norm_op[:type] == :door
            z_offset_mm = norm_op[:z_offset_mm] || 0.0
            height_mm = norm_op[:height_mm] || Config.get(:door_height) || 2200.0
            opening_bottom_z = base_z + Geometry.mm_to_inch(z_offset_mm)
            opening_top_z = opening_bottom_z + Geometry.mm_to_inch(height_mm)
          else
            door_top = Config.get(:door_height) || 2200.0
            z_offset_mm = norm_op[:z_offset_mm] || Config.get(:window_offset) || 900.0
            height_mm = norm_op[:height_mm] || Config.get(:window_height) || [door_top - z_offset_mm, 200.0].max
            opening_bottom_z = base_z + Geometry.mm_to_inch(z_offset_mm)
            opening_top_z = opening_bottom_z + Geometry.mm_to_inch(height_mm)
          end

          # Step 15: Validation
          validation_errors = validate_opening(
            id: op_id,
            edge_left: edge_left,
            edge_right: edge_right,
            wall_thickness_mm: wall_thickness_mm,
            wall_dir: wall_dir,
            open_start: open_start,
            open_end: open_end,
            opening_width_mm: raw_width_mm,
            opening_bottom_z: opening_bottom_z,
            opening_top_z: opening_top_z
          )

          unless validation_errors.empty?
            Logger.warn("Opening #{op_id} validation warnings: #{validation_errors.join(', ')}")
          end

          # Center position at opening bottom elevation
          center_pos = Geom::Point3d.new(
            (open_start.x + open_end.x) / 2.0,
            (open_start.y + open_end.y) / 2.0,
            opening_bottom_z
          )

          # Update opening data hash
          norm_op[:edge_left] = edge_left
          norm_op[:edge_right] = edge_right
          norm_op[:wall_thickness] = wall_thickness_mm
          norm_op[:wall_direction] = wall_dir
          norm_op[:wall_normal] = wall_norm
          norm_op[:linecenter] = linecenter
          norm_op[:open_start] = open_start
          norm_op[:open_end] = open_end
          norm_op[:opening_width] = raw_width_mm
          norm_op[:opening_bottom_z] = opening_bottom_z
          norm_op[:opening_top_z] = opening_top_z

          norm_op[:position] = center_pos
          norm_op[:direction] = wall_dir
          norm_op[:raw_width_mm] = raw_width_mm
          norm_op[:width_mm] = norm_width_mm
          norm_op[:depth_mm] = wall_thickness_mm
          norm_op[:height_mm] = height_mm
          norm_op[:z_offset_mm] = z_offset_mm

          # Step 16: Structured Debug Logging
          log_opening_debug(norm_op, matched_edges)

          norm_op
        end

        # Compute 2D bounding box (min_x, max_x, min_y, max_y) in World Coordinates
        def compute_candidate_bbox(op)
          if op[:raw_data].is_a?(Array) # Window line pair
            pts = op[:raw_data].flat_map { |s| [s[:start_pt], s[:end_pt]] }.compact
            return {
              min_x: pts.map(&:x).min,
              max_x: pts.map(&:x).max,
              min_y: pts.map(&:y).min,
              max_y: pts.map(&:y).max
            }
          elsif op[:raw_data].is_a?(Hash) && op[:raw_data][:start_pt] # Single window line
            s = op[:raw_data]
            return {
              min_x: [s[:start_pt].x, s[:end_pt].x].min,
              max_x: [s[:start_pt].x, s[:end_pt].x].max,
              min_y: [s[:start_pt].y, s[:end_pt].y].min,
              max_y: [s[:start_pt].y, s[:end_pt].y].max
            }
          end

          # For doors with real block bounds:
          if op[:raw_data].is_a?(Hash) && op[:raw_data][:bounds]
            b = op[:raw_data][:bounds]
            margin = Geometry.mm_to_inch(300.0)
            return {
              min_x: b.min.x - margin,
              max_x: b.max.x + margin,
              min_y: b.min.y - margin,
              max_y: b.max.y + margin
            }
          end

          # For doors and any opening with world position:
          pos = op[:position] || Geom::Point3d.new(0, 0, 0)
          search_r = Geometry.mm_to_inch(op[:width_mm] ? op[:width_mm] + Config::OPENING_SEARCH_MARGIN : 1200.0)
          {
            min_x: pos.x - search_r,
            max_x: pos.x + search_r,
            min_y: pos.y - search_r,
            max_y: pos.y + search_r
          }
        end

        # Find wall segments near candidate BBox
        def find_nearby_segments(wall_segments, bbox, margin_in)
          wall_segments.select do |seg|
            p1, p2 = seg
            s_min_x = [p1.x, p2.x].min
            s_max_x = [p1.x, p2.x].max
            s_min_y = [p1.y, p2.y].min
            s_max_y = [p1.y, p2.y].max

            !(bbox[:max_x] + margin_in < s_min_x ||
              bbox[:min_x] - margin_in > s_max_x ||
              bbox[:max_y] + margin_in < s_min_y ||
              bbox[:min_y] - margin_in > s_max_y)
          end
        end

        # Match 2 wall edges: Strategy A (Transverse Jambs) or Strategy B (Longitudinal Overlaps)
        def match_wall_edges(op, nearby_segments, cand_dir)
          return nil if nearby_segments.empty?

          min_thick_in = Geometry.mm_to_inch(40.0)
          max_thick_in = Geometry.mm_to_inch(550.0)
          min_span_in  = Geometry.mm_to_inch(400.0)
          max_span_in  = Geometry.mm_to_inch(4000.0)

          # 1. Transverse candidates (perpendicular to candidate direction)
          transverse = []
          longitudinal = []

          nearby_segments.each do |p1, p2|
            seg_vec = Geom::Vector3d.new(p2.x - p1.x, p2.y - p1.y, 0)
            next unless seg_vec.valid? && seg_vec.length > Geometry.mm_to_inch(1.0)

            seg_len = seg_vec.length
            u = seg_vec.normalize

            # Check angle with candidate direction
            dot_prod = (u.x * cand_dir.x) + (u.y * cand_dir.y)

            if seg_len >= min_thick_in && seg_len <= max_thick_in && dot_prod.abs < 0.5
              transverse << { p1: p1, p2: p2, len: seg_len, dir: u }
            elsif seg_len >= min_thick_in && dot_prod.abs > 0.7
              longitudinal << { p1: p1, p2: p2, len: seg_len, dir: u }
            end
          end

          # Strategy A: Pair of transverse segments
          if transverse.size >= 2
            best_pair = nil
            best_score = Float::INFINITY

            transverse.each_with_index do |t1, i|
              (i + 1...transverse.size).each do |j|
                t2 = transverse[j]
                # Check nearly parallel
                dot_t = (t1[:dir].x * t2[:dir].x) + (t1[:dir].y * t2[:dir].y)
                next unless dot_t.abs > 0.94

                mid1 = Geom::Point3d.new((t1[:p1].x + t1[:p2].x) / 2.0, (t1[:p1].y + t1[:p2].y) / 2.0, 0)
                mid2 = Geom::Point3d.new((t2[:p1].x + t2[:p2].x) / 2.0, (t2[:p1].y + t2[:p2].y) / 2.0, 0)
                span = mid1.distance(mid2)

                if span >= min_span_in && span <= max_span_in
                  exp_w_in = Geometry.mm_to_inch(op[:width_mm] || 1000.0)
                  diff = (span - exp_w_in).abs
                  if diff < best_score
                    best_score = diff
                    best_pair = {
                      edge_left: [t1[:p1], t1[:p2]],
                      edge_right: [t2[:p1], t2[:p2]],
                      strategy: :transverse_jambs
                    }
                  end
                end
              end
            end

            return best_pair if best_pair
          end

          # Strategy B: Longitudinal Outlines Overlap
          if longitudinal.size >= 2
            outlines = longitudinal.combination(2).select do |l1, l2|
              dot_l = (l1[:dir].x * l2[:dir].x) + (l1[:dir].y * l2[:dir].y)
              dot_l.abs > 0.94
            end

            best_outline_pair = outlines.min_by do |l1, l2|
              # Perpendicular distance between lines
              Geometry.distance_point_to_line_2d(l1[:p1], l2[:p1], l2[:dir])
            end

            if best_outline_pair
              l1, l2 = best_outline_pair
              thick_in = Geometry.distance_point_to_line_2d(l1[:p1], l2[:p1], l2[:dir])
              if thick_in >= min_thick_in && thick_in <= max_thick_in
                # Project candidate endpoints onto outlines to form edges
                pos = op[:position] || l1[:p1]
                half_w_in = Geometry.mm_to_inch((op[:width_mm] || 1000.0) / 2.0)
                p_start_l1 = Geometry.project_point_to_line_2d(pos.offset(cand_dir, -half_w_in), l1[:p1], l1[:dir])
                p_start_l2 = Geometry.project_point_to_line_2d(p_start_l1, l2[:p1], l2[:dir])
                p_end_l1 = Geometry.project_point_to_line_2d(pos.offset(cand_dir, half_w_in), l1[:p1], l1[:dir])
                p_end_l2 = Geometry.project_point_to_line_2d(p_end_l1, l2[:p1], l2[:dir])

                return {
                  edge_left: [p_start_l1, p_start_l2],
                  edge_right: [p_end_l1, p_end_l2],
                  strategy: :outline_overlap
                }
              end
            end
          end

          # Strategy C: Single Transverse Jamb + Corner/Perpendicular Wall
          if transverse.size >= 1
            exp_w_in = Geometry.mm_to_inch(op[:width_mm] || 900.0)
            transverse.each do |t1|
              p1, p2 = t1[:p1], t1[:p2]
              # Direction perpendicular to transverse segment (along wall span)
              perp_dir = Geom::Vector3d.new(-t1[:dir].y, t1[:dir].x, 0).normalize
              [perp_dir, perp_dir.reverse].each do |check_dir|
                hit1 = nil
                hit2 = nil
                nearby_segments.each do |s1, s2|
                  next if (s1 == p1 && s2 == p2) || (s1 == p2 && s2 == p1)
                  pt_a = Geometry.line_segment_intersection_2d(p1, check_dir, s1, s2)
                  if pt_a && p1.vector_to(pt_a).dot(check_dir) > 0
                    dist = p1.distance(pt_a)
                    if dist >= min_span_in && dist <= max_span_in
                      hit1 = pt_a if hit1.nil? || dist < p1.distance(hit1)
                    end
                  end
                  pt_b = Geometry.line_segment_intersection_2d(p2, check_dir, s1, s2)
                  if pt_b && p2.vector_to(pt_b).dot(check_dir) > 0
                    dist = p2.distance(pt_b)
                    if dist >= min_span_in && dist <= max_span_in
                      hit2 = pt_b if hit2.nil? || dist < p2.distance(hit2)
                    end
                  end
                end

                if hit1 && hit2
                  span = (p1.distance(hit1) + p2.distance(hit2)) / 2.0
                  if span >= min_span_in && span <= max_span_in
                    return {
                      edge_left: [p1, p2],
                      edge_right: [hit1, hit2],
                      strategy: :corner_jamb
                    }
                  end
                elsif hit1 || hit2
                  main_hit = hit1 || hit2
                  span = (hit1 ? p1 : p2).distance(main_hit)
                  if span >= min_span_in && span <= max_span_in
                    corner1 = p1.offset(check_dir, span)
                    corner2 = p2.offset(check_dir, span)
                    return {
                      edge_left: [p1, p2],
                      edge_right: [corner1, corner2],
                      strategy: :corner_jamb
                    }
                  end
                end
              end
            end

            # Strategy D: 1 Jamb Edge + Block Width Projection (when 1 side has no drawn end-cap)
            t1 = transverse.first
            p1, p2 = t1[:p1], t1[:p2]
            perp_dir = Geom::Vector3d.new(-t1[:dir].y, t1[:dir].x, 0).normalize
            proj_dir = perp_dir

            if op[:position]
              mid_jamb = Geom::Point3d.new((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0, 0)
              vec_to_block = Geom::Vector3d.new(op[:position].x - mid_jamb.x, op[:position].y - mid_jamb.y, 0)
              proj_dir = perp_dir.reverse if vec_to_block.valid? && vec_to_block.dot(perp_dir) < 0
            elsif cand_dir.valid? && cand_dir.dot(perp_dir) < 0
              proj_dir = perp_dir.reverse
            end

            w_len_in = Geometry.mm_to_inch(op[:width_mm] || 900.0)
            corner1 = p1.offset(proj_dir, w_len_in)
            corner2 = p2.offset(proj_dir, w_len_in)

            return {
              edge_left: [p1, p2],
              edge_right: [corner1, corner2],
              strategy: :single_jamb_projection
            }
          end

          nil
        end

        # Fallback to vertical face snapping if available
        def fallback_normalize(norm_op, walls_group, base_z)
          norm_op[:wall_normal] ||= calculate_normal_from_dir(norm_op[:direction])
          norm_op[:depth_mm] ||= 220.0
          norm_op[:wall_thickness] ||= norm_op[:depth_mm]
          norm_op[:wall_direction] ||= norm_op[:direction]
          norm_op
        end

        def calculate_normal_from_dir(dir_vec)
          return Geom::Vector3d.new(0, 1, 0) if dir_vec.nil? || !dir_vec.valid?

          Geom::Vector3d.new(-dir_vec.y, dir_vec.x, 0).normalize
        end

        # Validate opening against 12 criteria (Section 15)
        def validate_opening(opts)
          errors = []
          errors << 'edge_left missing' unless opts[:edge_left] && opts[:edge_left].size == 2
          errors << 'edge_right missing' unless opts[:edge_right] && opts[:edge_right].size == 2
          errors << 'wall_thickness <= 0' unless opts[:wall_thickness_mm] && opts[:wall_thickness_mm] > 10.0
          errors << 'invalid wall_direction' unless opts[:wall_dir] && opts[:wall_dir].valid?
          errors << 'open_start missing' unless opts[:open_start]
          errors << 'open_end missing' unless opts[:open_end]
          errors << 'opening_width <= tolerance' unless opts[:opening_width_mm] && opts[:opening_width_mm] > 100.0
          errors << 'opening_bottom_z >= opening_top_z' unless opts[:opening_bottom_z] < opts[:opening_top_z]
          errors
        end

        # Log detailed debug information (Section 16)
        def log_opening_debug(op, matched)
          el = op[:edge_left]
          er = op[:edge_right]

          el_str = el ? "(#{el[0].x.round(1)}, #{el[0].y.round(1)}) -> (#{el[1].x.round(1)}, #{el[1].y.round(1)})" : 'N/A'
          er_str = er ? "(#{er[0].x.round(1)}, #{er[0].y.round(1)}) -> (#{er[1].x.round(1)}, #{er[1].y.round(1)})" : 'N/A'
          os_str = op[:open_start] ? "(#{op[:open_start].x.round(1)}, #{op[:open_start].y.round(1)})" : 'N/A'
          oe_str = op[:open_end] ? "(#{op[:open_end].x.round(1)}, #{op[:open_end].y.round(1)})" : 'N/A'
          dir_str = op[:wall_direction] ? "(#{op[:wall_direction].x.round(3)}, #{op[:wall_direction].y.round(3)}, 0)" : 'N/A'

          Logger.info(
            "Opening #{op[:id]} (#{op[:type]}):\n" \
            "  Strategy: #{matched ? matched[:strategy] : 'fallback'}\n" \
            "  matched edge_left: #{el_str}\n" \
            "  matched edge_right: #{er_str}\n" \
            "  wall_thickness: #{op[:wall_thickness]&.round(1)}mm\n" \
            "  wall_direction: #{dir_str}\n" \
            "  open_start: #{os_str}\n" \
            "  open_end: #{oe_str}\n" \
            "  opening_width: #{op[:width_mm]&.round(1)}mm (raw: #{op[:raw_width_mm]&.round(1)}mm)\n" \
            "  bottom_z: #{Geometry.inch_to_mm(op[:opening_bottom_z]).round(1)}mm, top_z: #{Geometry.inch_to_mm(op[:opening_top_z]).round(1)}mm"
          )
        end
      end
    end
  end
end