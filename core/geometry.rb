# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Geometry and math helper functions for mm <-> SketchUp inches conversion and spatial math
    module Geometry
      MM_PER_INCH = 25.4

      class << self
        # Convert millimeters to SketchUp internal inches
        def mm_to_inch(mm)
          mm.to_f / MM_PER_INCH
        end

        # Convert SketchUp internal inches to millimeters
        def inch_to_mm(inch)
          inch.to_f * MM_PER_INCH
        end

        # Check if two numeric values are equal within tolerance (in mm)
        def almost_equal?(val1, val2, tolerance_mm = 0.1)
          (val1.to_f - val2.to_f).abs <= tolerance_mm
        end

        # Check if two 3D points are equal within tolerance (in mm)
        def points_equal?(pt1, pt2, tolerance_mm = 1.0)
          tol_inch = mm_to_inch(tolerance_mm)
          pt1.distance(pt2) <= tol_inch
        end

        # Round length (in mm) to nearest step (e.g., 10mm, fallback 5mm) according to Spec section 12
        def round_to_grid(length_mm, primary_step = 10.0, secondary_step = 5.0)
          rem_primary = length_mm % primary_step
          if rem_primary.abs < 0.001 || (primary_step - rem_primary).abs < 0.001
            length_mm.round
          else
            # Try secondary step (5mm)
            (length_mm / secondary_step).round * secondary_step
          end
        end

        # Calculate bounding box dimensions [width, depth, height] in mm
        def bbox_size_mm(bounds)
          [
            inch_to_mm(bounds.width),
            inch_to_mm(bounds.height),
            inch_to_mm(bounds.depth)
          ]
        end

        # Find 2D centroid of a set of Geom::Point3d points
        def centroid(points)
          return nil if points.empty?

          sum_x = points.sum(&:x)
          sum_y = points.sum(&:y)
          sum_z = points.sum(&:z)
          count = points.size.to_f

          Geom::Point3d.new(sum_x / count, sum_y / count, sum_z / count)
        end

        # Project 3D point onto a line defined by a point and direction vector
        def project_point_to_line(pt, line_pt, line_vec)
          return pt unless line_vec.valid?

          v = line_vec.normalize
          w = pt - line_pt
          proj_length = w % v
          line_pt.offset(v, proj_length)
        end

        # Calculate perpendicular distance from point to segment
        def distance_point_to_segment(pt, seg_start, seg_end)
          vec = seg_end - seg_start
          return pt.distance(seg_start) unless vec.valid? && vec.length > 0.0001

          proj_pt = project_point_to_line(pt, seg_start, vec)
          # Clamp projection point within segment bounds
          t = ((proj_pt - seg_start) % vec.normalize) / vec.length
          if t < 0
            pt.distance(seg_start)
          elsif t > 1
            pt.distance(seg_end)
          else
            pt.distance(proj_pt)
          end
        end

        # Calculate perpendicular distance from point to plane
        def distance_point_to_plane(pt, plane)
          return Float::INFINITY unless pt && plane

          if plane.is_a?(Array) && plane.length == 4
            a, b, c, d = plane
            denom = Math.sqrt((a * a) + (b * b) + (c * c))
            return Float::INFINITY if denom.zero?

            ((a * pt.x) + (b * pt.y) + (c * pt.z) + d).abs / denom
          elsif plane.is_a?(Array) && plane.length == 2 && plane[0].respond_to?(:x) && plane[1].respond_to?(:x)
            plane_pt, normal = plane
            return Float::INFINITY unless normal.valid?

            (pt - plane_pt).dot(normal.normalize).abs
          else
            Float::INFINITY
          end
        end

        # Check if two 2D vectors are parallel within tolerance angle
        def parallel_vectors?(vec1, vec2, tol_degrees = 3.0)
          v1 = Geom::Vector3d.new(vec1.x, vec1.y, 0)
          v2 = Geom::Vector3d.new(vec2.x, vec2.y, 0)
          return false unless v1.valid? && v2.valid?

          angle = v1.angle_between(v2)
          angle_deg = angle * 180.0 / Math::PI
          angle_deg < tol_degrees || (180.0 - angle_deg).abs < tol_degrees
        end

        # Extract X direction vector from SketchUp transformation matrix
        def direction_vector_from_transform(transformation)
          xaxis = transformation.xaxis
          v = Geom::Vector3d.new(xaxis.x, xaxis.y, 0)
          v.valid? ? v.normalize : Geom::Vector3d.new(1, 0, 0)
        end

        # Find intersection point of two 2D lines in XY plane
        # @param p1 [Geom::Point3d] point on line 1
        # @param v1 [Geom::Vector3d] direction of line 1
        # @param p2 [Geom::Point3d] point on line 2
        # @param v2 [Geom::Vector3d] direction of line 2
        # @return [Geom::Point3d, nil] intersection point
        def intersect_line_line_2d(p1, v1, p2, v2)
          det = (v1.x * v2.y) - (v1.y * v2.x)
          return nil if det.abs < 1.0e-9

          dx = p2.x - p1.x
          dy = p2.y - p1.y
          t = ((dx * v2.y) - (dy * v2.x)) / det
          Geom::Point3d.new(p1.x + (v1.x * t), p1.y + (v1.y * t), (p1.z + p2.z) / 2.0)
        end

        # Intersect infinite line (line_pt, line_dir) with segment [seg_p1, seg_p2] in 2D
        def line_segment_intersection_2d(line_pt, line_dir, seg_p1, seg_p2)
          seg_vec = Geom::Vector3d.new(seg_p2.x - seg_p1.x, seg_p2.y - seg_p1.y, 0)
          return nil unless seg_vec.valid?

          pt = intersect_line_line_2d(line_pt, line_dir, seg_p1, seg_vec)
          return nil unless pt

          # Check if pt lies on segment [seg_p1, seg_p2]
          seg_len = seg_vec.length
          return nil if seg_len < 1.0e-6

          u = seg_vec.normalize
          t = ((pt.x - seg_p1.x) * u.x) + ((pt.y - seg_p1.y) * u.y)
          tol = mm_to_inch(1.0)
          return pt if t >= -tol && t <= seg_len + tol

          nil
        end

        # Perpendicular distance from 2D point to infinite line
        def distance_point_to_line_2d(pt, line_pt, line_dir)
          dir = Geom::Vector3d.new(line_dir.x, line_dir.y, 0)
          return pt.distance(line_pt) unless dir.valid?

          u = dir.normalize
          dx = pt.x - line_pt.x
          dy = pt.y - line_pt.y
          # 2D cross product length
          ((dx * u.y) - (dy * u.x)).abs
        end

        # 2D projection of point onto infinite line
        def project_point_to_line_2d(pt, line_pt, line_dir)
          dir = Geom::Vector3d.new(line_dir.x, line_dir.y, 0)
          return pt unless dir.valid?

          u = dir.normalize
          proj_len = ((pt.x - line_pt.x) * u.x) + ((pt.y - line_pt.y) * u.y)
          Geom::Point3d.new(line_pt.x + (u.x * proj_len), line_pt.y + (u.y * proj_len), pt.z)
        end
      end
    end
  end
end
