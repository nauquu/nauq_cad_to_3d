# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Detects door and window openings in CAD geometry
    module OpeningDetector
      class << self
        # Detect all openings (doors & windows) from CAD original group
        # @param cad_group [Sketchup::Group] NAUQ_CAD_ORIGINAL group
        # @return [Array<Hash>] list of raw opening hashes
        def detect_all_openings(cad_group)
          return [] if cad_group.nil? || !cad_group.valid?

          doors = detect_door_openings(cad_group)
          windows = detect_window_openings(cad_group)
          win_blocks = detect_window_blocks(cad_group)

          # Door blocks take absolute priority over any window detection (lines or blocks)
          margin = Geometry.mm_to_inch(500.0)
          windows.reject! do |w|
            doors.any? { |d| d[:position].distance(w[:position]) <= margin }
          end

          win_blocks.reject! do |wb|
            doors.any? { |d| d[:position].distance(wb[:position]) <= margin }
          end

          # Merge window blocks avoiding double-detection if line clustering also found the window
          win_blocks.each do |wb|
            overlap = windows.find do |w|
              w[:position].distance(wb[:position]) <= margin
            end
            windows << wb unless overlap
          end

          all_openings = doors + windows
          Logger.info("Đã phát hiện #{all_openings.size} lỗ mở (#{doors.size} cửa đi, #{windows.size} cửa sổ)")
          all_openings
        end

        # Detect door openings from door blocks (e.g. CUA DI on 0-cua)
        def detect_door_openings(cad_group)
          door_layer = Config.get(:door_layer) || '0-cua'
          door_block_name = Config.get(:door_block) || 'CUA DI'
          door_height = Config.get(:door_height) || 2200.0

          blocks = BlockParser.collect_blocks(cad_group, door_block_name, door_layer)
          doors = []

          blocks.each_with_index do |blk, idx|
            dir_vec = Geometry.direction_vector_from_transform(blk[:transformation])
            w_mm = [blk[:width_mm], blk[:depth_mm]].max
            w_mm = 900.0 if w_mm < 300.0

            doors << {
              id: "DOOR_#{idx + 1}",
              type: :door,
              position: blk[:position],
              direction: dir_vec,
              width_mm: w_mm,
              depth_mm: 220.0,
              height_mm: door_height,
              z_offset_mm: 0.0,
              transformation: blk[:transformation],
              raw_data: blk
            }
          end

          doors
        end

        # Detect window openings from AutoCAD component blocks (e.g. CUA SO, WINDOW)
        def detect_window_blocks(cad_group)
          win_block = Config.get(:window_block) || 'CUA SO'
          win_layer = Config.get(:window_layer) || 'nho'
          door_top = Config.get(:door_height) || 2200.0
          win_offset = Config.get(:window_offset) || 900.0
          win_height = Config.get(:window_height) || [door_top - win_offset, 200.0].max

          blocks = BlockParser.collect_window_blocks(cad_group, win_block, win_layer)
          windows = []

          blocks.each_with_index do |blk, idx|
            dir_vec = Geometry.direction_vector_from_transform(blk[:transformation])
            w_mm = [blk[:width_mm], blk[:depth_mm]].max
            w_mm = 1200.0 if w_mm < 300.0

            windows << {
              id: "WIN_BLK_#{idx + 1}",
              type: :window,
              position: blk[:position],
              direction: dir_vec,
              width_mm: w_mm,
              depth_mm: 220.0,
              height_mm: win_height,
              z_offset_mm: win_offset,
              transformation: blk[:transformation],
              raw_data: blk
            }
          end

          windows
        end

        # Detect window openings from lines on window_layer using Window Line Clustering
        def detect_window_openings(cad_group)
          win_layer = Config.get(:window_layer) || 'nho'
          door_top = Config.get(:door_height) || 2200.0
          win_offset = Config.get(:window_offset) || 900.0
          win_height = Config.get(:window_height) || [door_top - win_offset, 200.0].max

          segments = LayerParser.collect_segments_with_transform(cad_group, win_layer)
          windows = []
          return windows if segments.empty?

          # Filter noise
          valid_segs = segments.select { |s| s[:length_mm] >= 100.0 }
          return windows if valid_segs.empty?

          # Window Line Clustering: group all parallel lines of the same window into one cluster
          clusters = []
          used = ::Set.new

          valid_segs.each_with_index do |seg, idx|
            next if used.include?(idx)

            current_cluster = [seg]
            used.add(idx)
            s_vec = (seg[:end_pt] - seg[:start_pt]).normalize
            s_mid = Geom::Point3d.new((seg[:start_pt].x + seg[:end_pt].x) / 2.0, (seg[:start_pt].y + seg[:end_pt].y) / 2.0, 0)

            valid_segs.each_with_index do |cand, c_idx|
              next if used.include?(c_idx)

              c_vec = (cand[:end_pt] - cand[:start_pt]).normalize
              next unless Geometry.parallel_vectors?(s_vec, c_vec, 10.0)

              c_mid = Geom::Point3d.new((cand[:start_pt].x + cand[:end_pt].x) / 2.0, (cand[:start_pt].y + cand[:end_pt].y) / 2.0, 0)
              perp_dist = Geometry.distance_point_to_line_2d(c_mid, s_mid, s_vec)
              next if perp_dist > Geometry.mm_to_inch(450.0)

              # Check span overlap
              proj_s1 = s_mid.vector_to(seg[:start_pt]).dot(s_vec)
              proj_s2 = s_mid.vector_to(seg[:end_pt]).dot(s_vec)
              s_min, s_max = [proj_s1, proj_s2].min, [proj_s1, proj_s2].max

              proj_c1 = s_mid.vector_to(cand[:start_pt]).dot(s_vec)
              proj_c2 = s_mid.vector_to(cand[:end_pt]).dot(s_vec)
              c_min, c_max = [proj_c1, proj_c2].min, [proj_c1, proj_c2].max

              margin_in = Geometry.mm_to_inch(100.0)
              if (c_min <= s_max + margin_in) && (c_max >= s_min - margin_in)
                current_cluster << cand
                used.add(c_idx)
              end
            end

            # Window symbol consists of at least 2 parallel lines (e.g. frame/glass lines)
            clusters << current_cluster if current_cluster.size >= 2
          end

          clusters.each_with_index do |cluster, c_idx|
            all_pts = cluster.flat_map { |s| [s[:start_pt], s[:end_pt]] }
            centroid = Geometry.centroid(all_pts)

            longest_seg = cluster.max_by { |s| s[:length_mm] }
            dir_vec = (longest_seg[:end_pt] - longest_seg[:start_pt]).normalize

            projections = all_pts.map { |pt| centroid.vector_to(pt).dot(dir_vec) }
            span_width_in = projections.max - projections.min
            span_width_mm = Geometry.inch_to_mm(span_width_in)
            span_width_mm = [span_width_mm, longest_seg[:length_mm]].max

            perp_vec = Geom::Vector3d.new(-dir_vec.y, dir_vec.x, 0).normalize
            perp_proj = all_pts.map { |pt| centroid.vector_to(pt).dot(perp_vec) }
            thick_in = perp_proj.max - perp_proj.min
            thick_mm = Geometry.inch_to_mm(thick_in)
            thick_mm = 220.0 if thick_mm < 50.0 || thick_mm > 550.0

            windows << {
              id: "WIN_#{windows.size + 1}",
              type: :window,
              position: centroid,
              direction: dir_vec,
              width_mm: span_width_mm,
              depth_mm: thick_mm,
              height_mm: win_height,
              z_offset_mm: win_offset,
              raw_data: cluster
            }
          end

          # Deduplicate windows: merge windows within 300mm of each other
          deduped = []
          windows.each do |w|
            match = deduped.find do |dw|
              dw[:position].distance(w[:position]) <= Geometry.mm_to_inch(300.0) &&
                Geometry.parallel_vectors?(dw[:direction], w[:direction], 15.0)
            end
            unless match
              deduped << w
            end
          end

          deduped
        end
      end
    end
  end
end
