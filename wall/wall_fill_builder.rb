# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Calculates the material regions that make up a wall.
    #
    # Architecture:
    #   1. Base Wall: All Wall Face 2D from CAD (0-netcat find_faces) are the
    #      source of truth for existing walls and are extruded to full height.
    #   2. WallFill: Supplemental geometry created at opening locations where
    #      CAD has no wall lines:
    #      - Door: 1 profile above door (opening_top -> wall_top)
    #      - Window: 2 profiles:
    #          * bottom fill (wall_base -> opening_bottom)
    #          * top fill (opening_top -> wall_top)
    #
    # This class creates NO SketchUp entities directly. It returns pure data hashes
    # containing 2D profile points and extrusion heights for WallBuilder to extrude.
    module WallFillBuilder
      DEFAULT_TOLERANCE_MM = 1.0 unless const_defined?(:DEFAULT_TOLERANCE_MM)

      class << self
        # Build all base wall profiles and opening wall-fill profiles.
        #
        # @param wall_faces [Array<Hash>] Wall Face 2D data from WallBuilder:
        #   :points, :u_vector, :n_vector, :base_z, :wall_top, :n_min, :n_max
        # @param normalized_openings [Array<Hash>] normalized openings
        # @param wall_height_mm [Numeric] wall height in mm
        # @return [Array<Hash>] list of profile hashes
        def build(wall_faces:, normalized_openings: [], wall_height_mm: nil)
          return [] if wall_faces.nil? || wall_faces.empty?

          height_mm = (wall_height_mm || 3000.0).to_f
          height_in = Geometry.mm_to_inch(height_mm)
          return [] unless height_in > tolerance_in

          profiles = []

          # -----------------------------------------------------------------
          # 1. Base Wall Profiles from Wall Face 2D (Source of Truth)
          # -----------------------------------------------------------------
          wall_faces.each_with_index do |wf, idx|
            profile = build_base_wall_profile(wf, height_in, idx)
            profiles << profile if profile
          end

          # -----------------------------------------------------------------
          # 2. WallFill Profiles for each Opening
          # -----------------------------------------------------------------
          Array(normalized_openings).each do |opening|
            face_idx = opening[:wall_face_index]
            wf = face_idx ? wall_faces[face_idx] : nil

            opening_fills = build_opening_fills(opening, wf, wall_faces, height_in)
            profiles.concat(opening_fills)
          end

          log_summary(wall_faces.size, normalized_openings.size, profiles)
          profiles
        end

        private

        # -------------------------------------------------------------------
        # Base Wall Profile: 2D face from CAD, extruded full height
        # -------------------------------------------------------------------

        def build_base_wall_profile(wf, height_in, face_index)
          points = wf[:points]
          return nil unless points && points.length >= 3

          base_z = wf[:base_z].to_f
          extrude_h = height_in
          return nil if extrude_h <= tolerance_in

          flat_points = points.map { |pt| Geom::Point3d.new(pt.x, pt.y, base_z) }

          {
            face_index: face_index,
            type: :base_wall,
            points: flat_points,
            extrude_height: extrude_h,
            label: "base_wall_face_#{face_index + 1}"
          }
        end

        # -------------------------------------------------------------------
        # Opening WallFill: Generate rectangular profiles above/below opening
        # -------------------------------------------------------------------

        def build_opening_fills(opening, wf, all_wall_faces, height_in)
          fills = []

          pos = opening[:position]
          unless pos && pos.respond_to?(:x)
            warn_opening(opening, 'no valid position')
            return []
          end

          base_z = wf ? wf[:base_z].to_f : (all_wall_faces.map { |f| f[:base_z] }.min || 0.0)
          wall_top = base_z + height_in

          # Local coordinate orientation + center point for the fill
          # rectangle. Use the opening's OWN direction/normal/position —
          # these come from OpeningNormalizer matching against individual
          # (un-merged) CAD wall segments, which stays reliable even when
          # the merged Wall Face 2D polygon (wf) is irregular (T-junctions,
          # multiple collinear vertices) and has no single trustworthy
          # global U/N axis. wf is only used for the base_z/wall_top
          # extrusion bounds above, not for orientation or thickness.
          u_vec = opening[:direction]
          u_vec = u_vec && u_vec.valid? ? u_vec.normalize : Geom::Vector3d.new(1, 0, 0)

          n_vec = opening[:wall_normal]
          n_vec = n_vec && n_vec.valid? ? n_vec.normalize : Geom::Vector3d.new(-u_vec.y, u_vec.x, 0).normalize

          depth_in = Geometry.mm_to_inch(opening[:depth_mm].to_f)
          depth_in = Geometry.mm_to_inch(220.0) if depth_in <= tolerance_in
          center = pos

          width_in = Geometry.mm_to_inch(opening[:width_mm].to_f)

          if width_in <= tolerance_in
            warn_opening(opening, 'width is <= tolerance')
            return []
          end

          half_w = width_in / 2.0
          half_d = depth_in / 2.0

          # Elevations
          opening_h_in = Geometry.mm_to_inch(opening[:height_mm].to_f)
          z_offset_in = Geometry.mm_to_inch(opening[:z_offset_mm].to_f)

          opening_bottom = opening[:opening_bottom_z] || (base_z + z_offset_in)
          opening_top = opening[:opening_top_z] || (opening_bottom + opening_h_in)

          type = opening[:type] # :door or :window

          # -----------------------------------------------------------------
          # Window: Bottom fill (base_z -> opening_bottom)
          # -----------------------------------------------------------------
          if type == :window && opening_bottom > base_z + tolerance_in
            bottom_h = opening_bottom - base_z
            pts = if opening[:edge_left] && opening[:edge_right]
                    build_profile_from_edges(opening[:edge_left], opening[:edge_right], base_z)
                  elsif opening[:open_start] && opening[:open_end]
                    build_profile_from_endpoints(opening[:open_start], opening[:open_end], n_vec, half_d, base_z)
                  else
                    build_rect_points(center, u_vec, n_vec, half_w, half_d, base_z)
                  end

            if validate_profile(pts, opening[:id], 'window_bottom')
              fills << {
                face_index: opening[:wall_face_index],
                type: :wall_fill,
                opening_id: opening[:id],
                points: pts,
                extrude_height: bottom_h,
                v_bottom: base_z,
                v_top: opening_bottom,
                label: "fill_bottom[#{opening[:id]}]"
              }
            end
          end

          # -----------------------------------------------------------------
          # Door & Window: Top fill (opening_top -> wall_top)
          # -----------------------------------------------------------------
          if wall_top > opening_top + tolerance_in
            top_h = wall_top - opening_top
            pts = if opening[:edge_left] && opening[:edge_right]
                    build_profile_from_edges(opening[:edge_left], opening[:edge_right], opening_top)
                  elsif opening[:open_start] && opening[:open_end]
                    build_profile_from_endpoints(opening[:open_start], opening[:open_end], n_vec, half_d, opening_top)
                  else
                    build_rect_points(center, u_vec, n_vec, half_w, half_d, opening_top)
                  end

            if validate_profile(pts, opening[:id], 'top_fill')
              fills << {
                face_index: opening[:wall_face_index],
                type: :wall_fill,
                opening_id: opening[:id],
                points: pts,
                extrude_height: top_h,
                v_bottom: opening_top,
                v_top: wall_top,
                label: "fill_top[#{opening[:id]}]"
              }
            end
          end

          fills
        end

        # -------------------------------------------------------------------
        # Build exact 4-point polygon connecting edge_left and edge_right
        # -------------------------------------------------------------------

        def build_profile_from_edges(edge_left, edge_right, z)
          l1, l2 = edge_left
          r1, r2 = edge_right

          # Align corresponding corners across the wall opening
          if (l1.distance(r1) + l2.distance(r2)) > (l1.distance(r2) + l2.distance(r1))
            r1, r2 = r2, r1
          end

          [
            Geom::Point3d.new(l1.x, l1.y, z),
            Geom::Point3d.new(r1.x, r1.y, z),
            Geom::Point3d.new(r2.x, r2.y, z),
            Geom::Point3d.new(l2.x, l2.y, z)
          ]
        end

        # -------------------------------------------------------------------
        # Build 4 rectangular points from open_start and open_end
        # -------------------------------------------------------------------

        def build_profile_from_endpoints(open_start, open_end, n_vec, half_d, z)
          p1 = open_start.offset(n_vec, -half_d)
          p2 = open_end.offset(n_vec, -half_d)
          p3 = open_end.offset(n_vec, half_d)
          p4 = open_start.offset(n_vec, half_d)

          [
            Geom::Point3d.new(p1.x, p1.y, z),
            Geom::Point3d.new(p2.x, p2.y, z),
            Geom::Point3d.new(p3.x, p3.y, z),
            Geom::Point3d.new(p4.x, p4.y, z)
          ]
        end

        # -------------------------------------------------------------------
        # Build 4 rectangular points in horizontal plane at elevation z
        # -------------------------------------------------------------------

        def build_rect_points(center, u_vec, n_vec, half_w, half_d, z)
          p1 = center.offset(u_vec, -half_w).offset(n_vec, -half_d)
          p2 = center.offset(u_vec, half_w).offset(n_vec, -half_d)
          p3 = center.offset(u_vec, half_w).offset(n_vec, half_d)
          p4 = center.offset(u_vec, -half_w).offset(n_vec, half_d)

          [
            Geom::Point3d.new(p1.x, p1.y, z),
            Geom::Point3d.new(p2.x, p2.y, z),
            Geom::Point3d.new(p3.x, p3.y, z),
            Geom::Point3d.new(p4.x, p4.y, z)
          ]
        end

        # -------------------------------------------------------------------
        # Geometry validation
        # -------------------------------------------------------------------

        def validate_profile(points, opening_id, label)
          unless points && points.length == 4
            log_validation_failure(opening_id, label, points, "expected 4 points, got #{points&.length}")
            return false
          end

          unless points.all? { |pt| pt.respond_to?(:x) && pt.respond_to?(:y) && pt.respond_to?(:z) }
            log_validation_failure(opening_id, label, points, 'invalid point coordinates')
            return false
          end

          v1 = points[0].vector_to(points[1])
          v2 = points[0].vector_to(points[3])
          unless v1.valid? && v2.valid?
            log_validation_failure(opening_id, label, points, 'degenerate edge vectors')
            return false
          end

          cross = v1.cross(v2)
          area = cross.length
          if area <= tolerance_in * tolerance_in
            log_validation_failure(opening_id, label, points, "near-zero area: #{area}")
            return false
          end

          true
        end

        def log_validation_failure(opening_id, label, points, reason)
          return unless defined?(Logger) && Logger.respond_to?(:warn)

          points_str = Array(points).map { |pt| "(#{pt.x.round(2)}, #{pt.y.round(2)}, #{pt.z.round(2)})" }.join(', ')
          Logger.warn("WallFill #{label} (#{opening_id}): FAILED validation — reason=#{reason}, points=[#{points_str}]")
        end

        # -------------------------------------------------------------------
        # Helpers
        # -------------------------------------------------------------------

        def tolerance_in
          Geometry.mm_to_inch(
            if defined?(Config) && Config.respond_to?(:get)
              Config.get(:wall_tolerance) || DEFAULT_TOLERANCE_MM
            else
              DEFAULT_TOLERANCE_MM
            end
          )
        end

        def warn_opening(opening, reason)
          return unless defined?(Logger) && Logger.respond_to?(:warn)

          Logger.warn("WallFill skipped opening #{opening[:id] || '(unknown)'}: #{reason}")
        end

        def log_summary(face_count, opening_count, profiles)
          return unless defined?(Logger) && Logger.respond_to?(:info)

          base_count = profiles.count { |p| p[:type] == :base_wall }
          fill_count = profiles.count { |p| p[:type] == :wall_fill }
          Logger.info(
            "WallFillBuilder: #{face_count} wall faces + #{opening_count} openings → " \
            "#{base_count} base wall faces + #{fill_count} WallFill profiles."
          )
        end
      end
    end
  end
end