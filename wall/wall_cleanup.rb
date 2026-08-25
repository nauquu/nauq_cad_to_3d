# frozen_string_literal: true

require 'set'

module NAUQ
  module CadTo3D
    # Cleanup wall boundary geometry (Level C auto-repair for small gaps, misalignments & unclosed corners)
    module WallCleanup
      class << self
        # Clean up line segments safely, auto-repairing open corners without prompting errors
        # @param segments [Array<Hash>] list of segment hashes {start_pt, end_pt, ...}
        # @param tolerance_mm [Float, nil] tolerance threshold in mm
        # @return [Array<Array<Geom::Point3d>>] list of cleaned point pairs [[pt1, pt2], ...]
        def cleanup_segments(segments, tolerance_mm = nil)
          tolerance_mm ||= Config.get(:wall_tolerance) || 5.0
          return [] if segments.empty?

          tol_inch = Geometry.mm_to_inch(tolerance_mm)

          # Extract original start/end pairs, skipping zero-length lines (< 0.001mm)
          min_len_inch = Geometry.mm_to_inch(0.001)
          raw_pairs = segments.map { |s| [s[:start_pt], s[:end_pt]] }
          raw_pairs.reject! { |p1, p2| p1.distance(p2) <= min_len_inch }

          return [] if raw_pairs.empty?

          # Endpoint snapping pool: cluster nearby endpoints across DIFFERENT segments
          clustered_points = []

          find_or_add_cluster = lambda do |pt|
            match = clustered_points.find { |cp| cp.distance(pt) <= tol_inch }
            if match
              match
            else
              clustered_points << pt
              pt
            end
          end

          cleaned_pairs = []
          degree_map = Hash.new(0)

          raw_pairs.each do |p1, p2|
            s_pt = find_or_add_cluster.call(p1)
            e_pt = find_or_add_cluster.call(p2)

            # Skip degenerate zero-length lines
            next if s_pt.distance(e_pt) <= min_len_inch

            # Skip exact duplicate lines
            duplicate = cleaned_pairs.any? do |cp1, cp2|
              (cp1.distance(s_pt) <= min_len_inch && cp2.distance(e_pt) <= min_len_inch) ||
                (cp1.distance(e_pt) <= min_len_inch && cp2.distance(s_pt) <= min_len_inch)
            end

            next if duplicate

            cleaned_pairs << [s_pt, e_pt]
            degree_map[s_pt] += 1
            degree_map[e_pt] += 1
          end

          # Auto-repair dangling open ends (Degree = 1) without logging warnings
          auto_repair_dangling_ends(cleaned_pairs, degree_map, 100.0)

          Logger.info("Cleanup Level C hoàn tất: #{segments.size} nét CAD -> #{cleaned_pairs.size} nét sạch (Đã tự động xử lý hở góc).")
          cleaned_pairs
        end

        private

        # Auto-repair open dangling endpoints (Degree = 1) by bridging or extending rays
        def auto_repair_dangling_ends(cleaned_pairs, degree_map, max_gap_mm = 100.0)
          max_gap_inch = Geometry.mm_to_inch(max_gap_mm)
          dangling_pts = degree_map.select { |_, d| d == 1 }.keys
          return if dangling_pts.empty?

          used_pts = Set.new
          repaired_count = 0

          # Step 1: Connect pairs of dangling points that are close to each other
          dangling_pts.each do |p1|
            next if used_pts.include?(p1)

            closest_p2 = dangling_pts.reject { |p| p == p1 || used_pts.include?(p) }
                                    .min_by { |p| p1.distance(p) }

            if closest_p2 && p1.distance(closest_p2) <= max_gap_inch
              cleaned_pairs << [p1, closest_p2]
              used_pts.add(p1)
              used_pts.add(closest_p2)
              repaired_count += 1
            end
          end

          # Step 2: For remaining dangling points, project ray along line direction to nearest wall segment
          dangling_pts.reject { |p| used_pts.include?(p) }.each do |p_open|
            seg = cleaned_pairs.find { |p1, p2| p1 == p_open || p2 == p_open }
            next unless seg

            p_other = seg[0] == p_open ? seg[1] : seg[0]
            vector = p_open - p_other
            next unless vector.valid? && vector.length > 0.001

            dir = vector.normalize
            ray = [p_open, dir]
            best_hit = nil
            min_hit_dist = max_gap_inch

            cleaned_pairs.each do |other_s, other_e|
              next if other_s == p_open || other_e == p_open || other_s == p_other || other_e == p_other

              # Check line-line intersection
              pt_on_ray, pt_on_seg = Geom.intersect_line_line(ray, [other_s, other_e - other_s])
              next unless pt_on_ray && pt_on_seg

              dist = p_open.distance(pt_on_ray)
              if dist > 0.001 && dist <= min_hit_dist
                # Check if pt_on_seg lies within segment bounds
                seg_vec = other_e - other_s
                t_param = (pt_on_seg - other_s) % seg_vec
                if t_param >= 0 && t_param * t_param <= seg_vec.length_squared
                  best_hit = pt_on_ray
                  min_hit_dist = dist
                end
              end
            end

            if best_hit
              if seg[0] == p_open
                seg[0] = best_hit
              else
                seg[1] = best_hit
              end
              repaired_count += 1
            end
          end

          if repaired_count > 0
            Logger.debug("Tự động vá khép góc cho #{repaired_count} vị trí đầu nét tường bị hở.")
          end
        end
      end
    end
  end
end
