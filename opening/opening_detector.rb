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
            # Extract direction vector from rotation transformation
            dir_vec = Geometry.direction_vector_from_transform(blk[:transformation])

            # Width is typically the major XY dimension of the door block
            w_mm = [blk[:width_mm], blk[:depth_mm]].max
            w_mm = 900.0 if w_mm < 300.0 # Fallback default if bounding box is tiny

            doors << {
              id: "DOOR_#{idx + 1}",
              type: :door,
              position: blk[:position],
              direction: dir_vec,
              width_mm: w_mm,
              depth_mm: 220.0, # Initial depth, will be calculated from actual wall thickness in Normalizer
              height_mm: door_height,
              z_offset_mm: 0.0, # Doors start from floor level (Z = 0)
              transformation: blk[:transformation],
              raw_data: blk
            }
          end

          doors
        end

        # Detect window openings from lines on window_layer (supports parallel line pairs & single lines)
        def detect_window_openings(cad_group)
          win_layer = Config.get(:window_layer) || 'nho'
          door_top = Config.get(:door_height) || 2200.0
          win_offset = Config.get(:window_offset) || 900.0
          win_height = Config.get(:window_height) || [door_top - win_offset, 200.0].max

          segments = LayerParser.collect_segments_with_transform(cad_group, win_layer)
          windows = []

          return windows if segments.empty?

          # Filter out tiny noise segments (< 100mm)
          valid_segs = segments.select { |s| s[:length_mm] >= 100.0 }
          used_indices = ::Set.new

          # Step 1: Pair up parallel lines representing the 2 wall faces of a window
          valid_segs.each_with_index do |seg1, i|
            next if used_indices.include?(i)

            pt1_s = seg1[:start_pt]
            pt1_e = seg1[:end_pt]
            vec1 = pt1_e - pt1_s
            mid1 = Geom::Point3d.new((pt1_s.x + pt1_e.x) / 2.0, (pt1_s.y + pt1_e.y) / 2.0, (pt1_s.z + pt1_e.z) / 2.0)

            # Find matching parallel line
            best_j = nil
            min_dist = 400.0 # Max wall thickness threshold in mm

            valid_segs.each_with_index do |seg2, j|
              next if i == j || used_indices.include?(j)

              pt2_s = seg2[:start_pt]
              pt2_e = seg2[:end_pt]
              vec2 = pt2_e - pt2_s
              mid2 = Geom::Point3d.new((pt2_s.x + pt2_e.x) / 2.0, (pt2_s.y + pt2_e.y) / 2.0, (pt2_s.z + pt2_e.z) / 2.0)

              if Geometry.parallel_vectors?(vec1, vec2, 5.0)
                dist = mid1.distance(mid2)
                if dist <= Geometry.mm_to_inch(min_dist)
                  best_j = j
                  min_dist = Geometry.inch_to_mm(dist)
                end
              end
            end

            if best_j
              # Paired window line: average position and average width
              seg2 = valid_segs[best_j]
              used_indices.add(i)
              used_indices.add(best_j)

              pt2_s = seg2[:start_pt]
              pt2_e = seg2[:end_pt]

              win_mid = Geometry.centroid([pt1_s, pt1_e, pt2_s, pt2_e])
              avg_width = (seg1[:length_mm] + seg2[:length_mm]) / 2.0
              dir_vec = vec1.normalize

              windows << {
                id: "WIN_#{windows.size + 1}",
                type: :window,
                position: win_mid,
                direction: dir_vec,
                width_mm: avg_width,
                depth_mm: min_dist > 50.0 ? min_dist : 220.0,
                height_mm: win_height,
                z_offset_mm: win_offset,
                raw_data: [seg1, seg2]
              }
            end
          end

          # Step 2: Handle remaining un-paired single lines as window centerlines
          valid_segs.each_with_index do |seg, i|
            next if used_indices.include?(i)

            pt_s = seg[:start_pt]
            pt_e = seg[:end_pt]
            vec = pt_e - pt_s
            mid = Geom::Point3d.new((pt_s.x + pt_e.x) / 2.0, (pt_s.y + pt_e.y) / 2.0, (pt_s.z + pt_e.z) / 2.0)

            dir_vec = vec.normalize

            windows << {
              id: "WIN_#{windows.size + 1}",
              type: :window,
              position: mid,
              direction: dir_vec,
              width_mm: seg[:length_mm],
              depth_mm: 220.0,
              height_mm: win_height,
              z_offset_mm: win_offset,
              raw_data: seg
            }
          end

          windows
        end
      end
    end
  end
end
