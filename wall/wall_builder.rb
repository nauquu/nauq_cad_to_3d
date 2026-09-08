# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Builds the single NAUQ_WALLS group from Wall Face 2D source of truth.
    #
    # WallBuilder has two explicit phases:
    #   1. build_wall_reference  — creates cleaned edges + find_faces to produce
    #      Wall Face 2D (horizontal) and vertical reference faces for snapping.
    #   2. build_walls           — assigns openings to wall faces, delegates to
    #      WallFillBuilder, then creates + extrudes all geometry in one pass.
    #
    # Wall Face 2D from CAD is the source of truth.  At opening positions the
    # CAD has no wall lines, so the faces already have the correct gaps.
    # WallFillBuilder only adds material above doors and above/below windows.
    module WallBuilder
      @reference_data = {}

      class << self
        # Build the final wall geometry inside one NAUQ_WALLS group.
        #
        # @param cad_group [Sketchup::Group] NAUQ_CAD_ORIGINAL group
        # @param walls_group [Sketchup::Group, nil] group container
        # @param normalized_openings [Array<Hash>] normalized opening data
        # @return [Sketchup::Group, nil] updated walls_group
        def build_walls(cad_group, walls_group = nil, normalized_openings = nil)
          model = Sketchup.active_model
          return nil unless model

          walls_group ||= DWGReader.find_or_create_walls_group(model)
          unless walls_group && walls_group.valid?
            Logger.error('Unable to find or create NAUQ_WALLS.')
            return nil
          end

          reference = reference_data_for(cad_group, walls_group)
          return walls_group unless reference

          rebuild_walls_with_openings(reference, walls_group, normalized_openings)
        end

        # Rebuild walls from reference data and normalized openings
        def rebuild_walls_with_openings(reference, walls_group, normalized_openings = nil)
          model = Sketchup.active_model
          return nil unless model && walls_group && walls_group.valid? && reference

          normalized_openings ||= []
          raw_height_mm = Config.get(:wall_height) || 3000.0
          deduct_beam = Config.get(:deduct_beam) || false
          beam_depth_mm = (Config.get(:beam_depth) || 400.0).to_f

          if deduct_beam
            height_mm = [raw_height_mm - beam_depth_mm, Config::MIN_WALL_HEIGHT].max
            Logger.info("Bật trừ dầm #{beam_depth_mm}mm: Chiều cao tường thực tế dựng là #{height_mm}mm (Tổng chiều cao: #{raw_height_mm}mm)")
          else
            height_mm = raw_height_mm
          end

          wall_faces_data = reference[:wall_faces] || []

          if wall_faces_data.empty?
            Logger.warn('No Wall Face 2D data found. Nothing to build.')
            return walls_group
          end

          Logger.info("Wall faces detected: #{wall_faces_data.size}")

          # ---------------------------------------------------------------
          # Assign each opening to a wall face
          # ---------------------------------------------------------------
          assign_openings_to_faces(normalized_openings, wall_faces_data)

          # Log opening assignments
          normalized_openings.each do |opening|
            face_idx = opening[:wall_face_index]
            expected = opening[:type] == :window ? 2 : 1
            if face_idx
              Logger.info(
                "Opening #{opening[:id] || opening[:type]}:\n" \
                "  wall_face = #{face_idx}\n" \
                "  width = #{opening[:width_mm].to_f.round(1)}\n" \
                "  bottom = #{opening[:z_offset_mm].to_f.round(1)}\n" \
                "  top = #{(opening[:z_offset_mm].to_f + opening[:height_mm].to_f).round(1)}\n" \
                "  fill_profiles = #{expected}"
              )
            else
              Logger.warn(
                "Opening #{opening[:id] || opening[:type]}: " \
                "could not be assigned to any wall face — skipped"
              )
            end
          end

          # ---------------------------------------------------------------
          # Compute fill profiles via WallFillBuilder
          # ---------------------------------------------------------------
          fills = WallFillBuilder.build(
            wall_faces: wall_faces_data,
            normalized_openings: normalized_openings,
            wall_height_mm: height_mm
          )

          # ---------------------------------------------------------------
          # Create final geometry in a single operation
          # ---------------------------------------------------------------
          model.start_operation('Create NAUQ Walls', true)
          base_extruded = 0
          fill_created = 0
          fill_extruded = 0

          begin
            # Clear temporary reference geometry
            temp_ref = reference[:temp_ref_group]
            temp_ref.erase! if temp_ref && temp_ref.valid?

            cad_group = reference[:cad_group]
            cad_id = cad_group ? (cad_group.respond_to?(:persistent_id) ? cad_group.persistent_id.to_s : cad_group.object_id.to_s) : nil
            floor_name = cad_group && cad_group.respond_to?(:name) && !cad_group.name.empty? ? cad_group.name : "Floor_#{cad_id || Time.now.to_i}"

            # Remove previous walls built from this specific CAD drawing if any
            if cad_id
              existing_model = model.entities.grep(Sketchup::Group).select do |g|
                g.valid? && (g.name == "WALLS_#{floor_name}" || (Attribute.get(g, 'source_cad_id') == cad_id && g.name.start_with?('WALLS_')))
              end
              existing_model.each { |g| g.erase! if g.valid? }

              if walls_group && walls_group.valid?
                existing_sub = walls_group.entities.grep(Sketchup::Group).select do |g|
                  g.valid? && Attribute.get(g, 'source_cad_id') == cad_id
                end
                existing_sub.each { |g| g.erase! if g.valid? }
              end
            end

            # Create independent top-level group for this floor's walls directly at model root
            model.selection.clear rescue nil
            floor_walls = model.entities.add_group
            floor_walls.name = "WALLS_#{floor_name}"
            Attribute.tag(floor_walls, 'wall_floor', source_cad_id: cad_id)

            fills.each do |fill|
              points = fill[:points]
              next unless points && points.length >= 3

              extrude_h = fill[:extrude_height].to_f
              next if extrude_h <= Geometry.mm_to_inch(1.0)

              # Geometry validation
              unless valid_profile_for_creation?(points, fill)
                next
              end

              face = floor_walls.entities.add_face(points)
              unless face && face.valid?
                log_face_creation_failure(fill, points, 'add_face returned nil')
                next
              end

              if fill[:type] == :wall_fill
                fill_created += 1
              end

              # Ensure face normal points up (Z+) so pushpull goes upward
              face.reverse! if face.normal.z < 0

              face.pushpull(extrude_h)

              if fill[:type] == :base_wall
                base_extruded += 1
              else
                fill_extruded += 1
              end
            end

            # Clean up internal divider faces and coplanar seam edges inside group
            begin
              cleanup_wall_geometry(floor_walls)
            rescue StandardError => e
              Logger.warn("Warning during cleanup_wall_geometry: #{e.message}")
            end

            Logger.info("Base wall faces extruded: #{base_extruded}")
            Logger.info("WallFill faces created: #{fill_created}")
            Logger.info("WallFill faces extruded: #{fill_extruded}")

            Attribute.tag(
              floor_walls,
              'wall',
              source_cad_id: cad_id,
              wall_face_count: wall_faces_data.size,
              base_wall_count: base_extruded,
              wall_fill_count: fill_extruded,
              opening_count: normalized_openings.size,
              height_mm: height_mm,
              layer_used: Config.get(:wall_layer),
              created_at: Time.now.to_s
            )

            # Build top slab covering the outer boundary of finished walls
            if deduct_beam
              build_slab(model, floor_walls, height_mm, beam_depth_mm, cad_id, floor_name)
            end

            model.commit_operation
            Logger.info(
              "Created #{base_extruded} base walls + #{fill_extruded} WallFill regions " \
              "from #{wall_faces_data.size} wall faces " \
              "(height: #{height_mm}mm) in '#{floor_walls.name}'."
            )
          rescue StandardError => e
            model.abort_operation
            if defined?(CadTo3D) && CadTo3D.respond_to?(:debug_puts)
              CadTo3D.debug_puts("[NAUQ ERROR] Exception in rebuild_walls_with_openings: #{e.class}: #{e.message}")
              CadTo3D.debug_puts(e.backtrace.first(10).join("\n")) if e.backtrace
            end
            Logger.error("Error creating wall geometry: #{e.message}")
            raise e
          ensure
            @reference_data.delete(walls_group.object_id) if walls_group && walls_group.valid?
          end

          walls_group
        end

        # Create temporary wall reference geometry.  The horizontal faces
        # produced by find_faces are Wall Face 2D — the source of truth.
        # Vertical faces are created for OpeningNormalizer to snap against.
        #
        # @return [Sketchup::Group, nil] reference group
        def build_wall_reference(cad_group, walls_group = nil)
          model = Sketchup.active_model
          return nil unless model

          walls_group ||= DWGReader.find_or_create_walls_group(model)
          unless walls_group && walls_group.valid?
            Logger.error('Unable to find or create NAUQ_WALLS for wall reference.')
            return nil
          end

          segments = WallDetector.detect_wall_segments(cad_group)
          if segments.empty?
            Logger.warn('No valid wall segments found for wall reference.')
            @reference_data[walls_group.object_id] = empty_reference
            return walls_group
          end

          cleaned_pairs = WallCleanup.cleanup_segments(segments)
          if cleaned_pairs.empty?
            Logger.warn('Wall cleanup produced no segments for wall reference.')
            @reference_data[walls_group.object_id] = empty_reference
            return walls_group
          end

          raw_height_mm = Config.get(:wall_height) || 3000.0
          deduct_beam = Config.get(:deduct_beam) || false
          beam_depth_mm = (Config.get(:beam_depth) || 400.0).to_f
          height_mm = deduct_beam ? [raw_height_mm - beam_depth_mm, 1000.0].max : raw_height_mm

          height_in = Geometry.mm_to_inch(height_mm)
          base_z = cleaned_pairs.flatten.map(&:z).min
          wall_top = base_z + height_in

          model.start_operation('Prepare NAUQ Wall Reference', true)

          begin
            # Create isolated temporary group for reference faces so existing walls are preserved
            temp_ref_group = walls_group.entities.add_group
            temp_ref_group.name = 'NAUQ_TEMP_WALL_REF'
            Attribute.tag(temp_ref_group, 'temp_wall_ref')

            # ---------------------------------------------------------------
            # Add cleaned edges and let SketchUp find faces (Wall Face 2D)
            # ---------------------------------------------------------------
            added_edges = []
            cleaned_pairs.each do |first, second|
              edges = temp_ref_group.entities.add_edges(
                reference_point(first, base_z),
                reference_point(second, base_z)
              )
              added_edges.concat(edges) if edges
            end

            added_edges.uniq!
            added_edges.each { |edge| edge.find_faces if edge.valid? }

            # ---------------------------------------------------------------
            # Collect Wall Face 2D — horizontal faces are source of truth
            # ---------------------------------------------------------------
            wall_faces_data = temp_ref_group.entities.grep(Sketchup::Face).filter_map do |face|
              next unless face.valid? && face.normal.z.abs > 0.9

              points = face.outer_loop.vertices.map do |vertex|
                reference_point(vertex.position, base_z)
              end
              next if points.length < 3

              # Compute local coordinate basis
              basis = compute_face_basis(points)
              next unless basis

              {
                face_entity_id: face.entityID,
                points: points,
                origin: basis[:origin],
                u_vector: basis[:u_vector],
                n_vector: basis[:n_vector],
                n_min: basis[:n_min],
                n_max: basis[:n_max],
                base_z: base_z,
                wall_top: wall_top
              }
            end

            Logger.info("Wall Face 2D collected: #{wall_faces_data.size} faces from #{cleaned_pairs.size} cleaned edges.")

            reference = {
              wall_faces: wall_faces_data,
              cleaned_pairs: cleaned_pairs,
              base_z: base_z,
              wall_top: wall_top,
              height_mm: height_mm,
              temp_ref_group: temp_ref_group,
              cad_group: cad_group
            }
            @reference_data[walls_group.object_id] = reference
            @reference_data[walls_group.entityID] = reference if walls_group.respond_to?(:entityID)

            Attribute.tag(
              walls_group,
              'wall_reference',
              wall_face_count: wall_faces_data.size,
              height_mm: height_mm,
              reference_only: true
            )

            model.commit_operation
            Logger.info("Prepared #{wall_faces_data.size} Wall Face 2D references (no wall solid created).")
          rescue StandardError => e
            model.abort_operation
            @reference_data.delete(walls_group.object_id)
            Logger.error("Error preparing wall reference: #{e.message}")
            raise e
          end

          walls_group
        end

        private

        # -------------------------------------------------------------------
        # Local coordinate basis for a wall face
        # -------------------------------------------------------------------

        def compute_face_basis(points)
          return nil if points.length < 3

          # Origin = first point
          origin = Geom::Point3d.new(points.first.x, points.first.y, points.first.z)

          # U = the polygon's natural long axis
          u_vector = principal_axis_vector(points)
          return nil unless u_vector

          # N = perpendicular to U in the horizontal plane
          n_vector = Geom::Vector3d.new(-u_vector.y, u_vector.x, 0)
          return nil unless n_vector.valid?

          n_vector.normalize!

          # Compute N-extent (wall thickness) from polygon
          n_coords = points.map { |pt| origin.vector_to(pt).dot(n_vector) }
          n_min = n_coords.min
          n_max = n_coords.max

          # Ensure non-degenerate thickness
          return nil if (n_max - n_min).abs <= Geometry.mm_to_inch(1.0)

          {
            origin: origin,
            u_vector: u_vector,
            n_vector: n_vector,
            n_min: n_min,
            n_max: n_max
          }
        end

        # Find the polygon's natural long axis using a rotating-calipers
        # style search: try EVERY edge direction of the polygon as a
        # candidate axis, and keep whichever gives the tightest (minimum
        # area) axis-aligned bounding box around all the vertices.
        #
        # This is the standard technique for finding the true orientation
        # of a roughly-rectangular shape and is robust against merged wall
        # footprints that are not clean 4-corner rectangles — e.g. long
        # wall runs subdivided into many collinear vertices by intersecting
        # cross walls, or slightly L-shaped merges. Neither "longest single
        # edge" nor "farthest vertex pair" (diameter, which can land on a
        # corner-to-corner diagonal) held up reliably for those cases.
        def principal_axis_vector(points)
          return farthest_pair_vector(points) if points.length < 3

          n = points.length
          best_axis = nil
          best_area = Float::INFINITY

          n.times do |i|
            p1 = points[i]
            p2 = points[(i + 1) % n]
            edge = Geom::Vector3d.new(p2.x - p1.x, p2.y - p1.y, 0)
            next unless edge.valid? && edge.length > Geometry.mm_to_inch(1.0)

            axis = edge.normalize
            perp = Geom::Vector3d.new(-axis.y, axis.x, 0)
            next unless perp.valid?

            perp.normalize!

            u_coords = points.map { |pt| p1.vector_to(pt).dot(axis) }
            v_coords = points.map { |pt| p1.vector_to(pt).dot(perp) }
            area = (u_coords.max - u_coords.min) * (v_coords.max - v_coords.min)

            if area < best_area
              best_area = area
              best_axis = axis
            end
          end

          best_axis || farthest_pair_vector(points)
        end

        def farthest_pair_vector(points)
          return nil if points.length < 2

          best_pair = points.combination(2).max_by { |a, b| a.distance(b) }
          return nil unless best_pair

          p1, p2 = best_pair
          vector = Geom::Vector3d.new(p2.x - p1.x, p2.y - p1.y, 0)
          return nil unless vector.valid? && vector.length > Geometry.mm_to_inch(1.0)

          vector.normalize
        end

        # -------------------------------------------------------------------
        # Opening-to-Face assignment
        # -------------------------------------------------------------------

        def assign_openings_to_faces(openings, wall_faces_data)
          openings.each do |opening|
            best_face_idx = nil
            best_dist = Float::INFINITY

            # An opening connects wall faces at open_start and open_end (the jambs),
            # with its center in the gap between wall segments.
            # We measure distance to polygon from open_start, open_end, and center.
            w_mm = opening[:width_mm].to_f
            max_allowed = [Geometry.mm_to_inch(w_mm + 300.0), Geometry.mm_to_inch(2000.0)].max

            wall_faces_data.each_with_index do |wf, idx|
              next unless wf[:points] && wf[:points].length >= 3

              d_center = opening[:position] ? point_to_polygon_distance(opening[:position], wf[:points]) : Float::INFINITY
              d_start = opening[:open_start] ? point_to_polygon_distance(opening[:open_start], wf[:points]) : Float::INFINITY
              d_end = opening[:open_end] ? point_to_polygon_distance(opening[:open_end], wf[:points]) : Float::INFINITY

              dist = [d_center, d_start, d_end].min
              next if dist > max_allowed

              if dist < best_dist
                best_face_idx = idx
                best_dist = dist
              end
            end

            opening[:wall_face_index] = best_face_idx

            log_assignment_failure(opening, wall_faces_data) if best_face_idx.nil?
          end
        end

        # Distance from `point` (opening position, XY plan) to a wall
        # footprint polygon: 0 if the point lies inside the polygon,
        # otherwise the distance to its nearest edge. Deliberately
        # independent of any global U/N axis — a merged Wall Face 2D
        # polygon from find_faces can have many vertices (T-junctions,
        # collinear points from subdivided CAD lines) for which no single
        # rectangular basis reliably describes "wall direction". Point-in-
        # polygon works for any shape.
        def point_to_polygon_distance(point, polygon_points)
          return Float::INFINITY if polygon_points.length < 3
          return 0.0 if point_inside_polygon_2d?(point, polygon_points)

          polygon_points.each_index.map do |i|
            a = polygon_points[i]
            b = polygon_points[(i + 1) % polygon_points.length]
            Geometry.distance_point_to_segment(point, a, b)
          end.min
        end

        # Standard ray-casting point-in-polygon test (2D, XY plan only).
        def point_inside_polygon_2d?(point, polygon_points)
          x = point.x
          y = point.y
          inside = false
          n = polygon_points.length
          j = n - 1

          n.times do |i|
            xi = polygon_points[i].x
            yi = polygon_points[i].y
            xj = polygon_points[j].x
            yj = polygon_points[j].y

            if (yi > y) != (yj > y)
              x_intersect = ((xj - xi) * (y - yi) / (yj - yi)) + xi
              inside = !inside if x < x_intersect
            end
            j = i
          end

          inside
        end

        # Diagnostic: when an opening matches no wall face, report the
        # nearest polygon by point-to-boundary distance so we can see how
        # far off it is (and whether 300mm is too tight for this project's
        # data).
        def log_assignment_failure(opening, wall_faces_data)
          return unless defined?(Logger) && Logger.respond_to?(:warn)
          return if wall_faces_data.empty?

          rows = wall_faces_data.each_with_index.map do |wf, idx|
            dist = wf[:points] && wf[:points].length >= 3 ? point_to_polygon_distance(opening[:position], wf[:points]) : Float::INFINITY
            { idx: idx, dist_mm: Geometry.inch_to_mm(dist).round(1) }
          end

          nearest = rows.min_by { |r| r[:dist_mm] }
          Logger.warn(
            "Opening #{opening[:id]}: KHÔNG khớp face nào (point-in-polygon). Face gần nhất (idx=#{nearest[:idx]}): " \
            "khoảng cách tới biên đa giác=#{nearest[:dist_mm]}mm (giới hạn 300mm)."
          )
        end

        # -------------------------------------------------------------------
        # Geometry validation before face creation
        # -------------------------------------------------------------------

        def valid_profile_for_creation?(points, fill)
          return false unless points && points.length >= 3

          unless points.all? { |pt| pt.respond_to?(:x) && pt.respond_to?(:y) && pt.respond_to?(:z) }
            log_face_creation_failure(fill, points, 'invalid point objects')
            return false
          end

          # Check for degenerate (all points coincident)
          if points.length >= 2
            max_dist = points.combination(2).map { |a, b| a.distance(b) }.max
            if max_dist <= Geometry.mm_to_inch(1.0)
              log_face_creation_failure(fill, points, 'all points nearly coincident')
              return false
            end
          end

          true
        end

        def log_face_creation_failure(fill, points, reason)
          return unless defined?(Logger) && Logger.respond_to?(:warn)

          points_str = Array(points).map { |pt| "(#{pt.x.round(3)}, #{pt.y.round(3)}, #{pt.z.round(3)})" }.join(', ')
          label = fill[:label] || fill[:type]
          Logger.warn(
            "WallFill #{label}:\n" \
            "  FAILED add_face\n" \
            "  reason = #{reason}\n" \
            "  points = [#{points_str}]\n" \
            "  extrude_height = #{fill[:extrude_height].to_f.round(3)}"
          )
        end

        # -------------------------------------------------------------------
        # Reference helpers
        # -------------------------------------------------------------------

        def reference_data_for(cad_group, walls_group)
          key = walls_group.respond_to?(:entityID) ? walls_group.entityID : walls_group.object_id
          reference = @reference_data[key] || @reference_data[walls_group.object_id]
          return reference if reference

          build_wall_reference(cad_group, walls_group)
          @reference_data[key] || @reference_data[walls_group.object_id]
        end

        def empty_reference
          {
            wall_faces: [],
            cleaned_pairs: [],
            base_z: 0.0,
            wall_top: Geometry.mm_to_inch(Config.get(:wall_height) || 3000.0),
            height_mm: Config.get(:wall_height) || 3000.0
          }
        end

        def reference_point(point, z)
          Geom::Point3d.new(point.x, point.y, z)
        end

        # Clean up internal divider faces and coplanar seam edges applying ams_FixIt.rb algorithms
        def cleanup_wall_geometry(group)
          return unless group && group.valid?

          # Step 1: Remove internal divider faces (those with all edges meeting >= 3 faces)
          to_remove = []
          group.entities.grep(Sketchup::Face).each do |face|
            next unless face.valid?
            remove = true
            face.edges.each do |edge|
              if edge.faces.size <= 2
                remove = false
                break
              end
            end
            to_remove << face if remove
          end

          if to_remove.any?
            to_remove.each { |f| f.erase! if f.valid? }
            Logger.info("Đã xóa #{to_remove.size} mặt vách ngăn trong tường.")
          end

          # Step 2: Remove coplanar edges to merge faces smoothly
          2.times do
            coplanar_edges = []
            group.entities.grep(Sketchup::Edge).each do |edge|
              next unless edge.valid?
              next if edge.faces.size != 2

              f1, f2 = edge.faces
              if f1.normal.parallel?(f2.normal)
                vertices = f1.vertices + f2.vertices
                plane = Geom.fit_plane_to_points(vertices)
                safe = vertices.all? { |v| v.position.on_plane?(plane) }
                if safe
                  coplanar_edges << edge
                end
              end
            end
            break if coplanar_edges.empty?

            group.entities.erase_entities(coplanar_edges)
            Logger.info("Đã xóa #{coplanar_edges.size} nét thừa giáp ranh giữa WallFill và Tường.")
          end
        end

        # Build concrete slab covering the exact boundary of the finished top wall faces and enclosed rooms
        # Build concrete slab covering the exact boundary of the finished top wall faces and enclosed rooms
        def build_slab(model, floor_walls, wall_h_mm, slab_thick_mm, cad_id = nil, floor_name = 'Floor')
          # Erase previous slab for this specific CAD drawing if any
          if cad_id
            existing = model.entities.grep(Sketchup::Group).select do |g|
              g.valid? && (g.name == "SLAB_#{floor_name}" || (Attribute.get(g, 'source_cad_id') == cad_id && g.name.start_with?('SLAB_')))
            end
            existing.each { |g| g.erase! if g.valid? }
          end

          model.selection.clear rescue nil
          floor_slab = model.entities.add_group
          floor_slab.name = "SLAB_#{floor_name}"
          Attribute.tag(floor_slab, 'slab_floor', source_cad_id: cad_id, thickness_mm: slab_thick_mm, elevation_mm: wall_h_mm)

          z_top_in = Geometry.mm_to_inch(wall_h_mm)
          thick_in = Geometry.mm_to_inch(slab_thick_mm)

          # 1. Collect top horizontal faces from the finished floor_walls
          top_faces = floor_walls.entities.grep(Sketchup::Face).select do |f|
            f.valid? && f.normal.z > 0.9 && f.vertices.all? { |v| (v.position.z - z_top_in).abs < 0.1 }
          end

          return if top_faces.empty?

          # 2. Draw all outer perimeter edges of top faces into floor_slab
          top_faces.each do |face|
            next unless face.valid?

            face.outer_loop.edges.each do |edge|
              p1 = edge.start.position
              p2 = edge.end.position
              pt1_3d = Geom::Point3d.new(p1.x, p1.y, z_top_in)
              pt2_3d = Geom::Point3d.new(p2.x, p2.y, z_top_in)
              next if pt1_3d == pt2_3d

              floor_slab.entities.add_line(pt1_3d, pt2_3d) rescue nil
            end
          end

          # 3. Find all faces formed by the boundary loops (walls + enclosed rooms)
          floor_slab.entities.grep(Sketchup::Edge).each do |edge|
            edge.find_faces if edge.valid?
          end

          faces = floor_slab.entities.grep(Sketchup::Face)
          if faces.empty?
            # Fallback: copy top face polygons directly
            top_faces.each do |face|
              pts = face.outer_loop.vertices.map { |v| Geom::Point3d.new(v.position.x, v.position.y, z_top_in) }
              floor_slab.entities.add_face(pts) rescue nil
            end
            faces = floor_slab.entities.grep(Sketchup::Face)
          end

          return if faces.empty?

          # 4. Extrude all slab faces upward
          faces.each do |face|
            next unless face.valid?

            face.reverse! if face.normal.z < 0
            face.pushpull(thick_in)
          end

          # 5. Clean up internal divider faces to merge into a single solid boundary slab
          cleanup_wall_geometry(floor_slab)

          # 6. Apply concrete material
          slab_mat = MaterialLoader.get_material(model, 'betong') rescue nil
          floor_slab.material = slab_mat if slab_mat

          Attribute.tag(floor_slab, 'slab', thickness_mm: slab_thick_mm, elevation_mm: wall_h_mm)
          Logger.info("Đã tạo Sàn bê tông #{floor_slab.name} dày #{slab_thick_mm}mm trong 'NAUQ_SLAB'.")
        end
      end
    end
  end
end