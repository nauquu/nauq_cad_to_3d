# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Module to detect and hide duplicate / overlapping coplanar edges across Groups and Components
    # Pure geometric engine: no material filtering, instant 1-click execution.
    module OverlapEdgeCleaner
      TOLERANCE = 0.001 unless const_defined?(:TOLERANCE) # 0.001 inch tolerance

      class << self
        # Main entry point to hide overlapping edges in active selection or model
        def hide_overlapping_edges
          model = Sketchup.active_model
          return unless model

          selection = model.selection
          target_entities = selection.empty? ? model.active_entities : selection

          stats = {
            groups_unique: 0,
            components_unique: 0,
            splits: 0,
            hidden: 0
          }

          model.start_operation('NAUQ Ẩn Nét Trùng Lặp', true)

          begin
            # 1. Collect all edges data in selection recursively
            edges_data = []
            target_entities.each do |entity|
              if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                make_unique_safe(entity, stats)
                trans = entity.transformation
                path = [entity]
                traverse_entities(entity.definition.entities, trans, path, edges_data, stats)
              elsif entity.is_a?(Sketchup::Edge)
                faces_info = extract_faces_info(entity, Geom::Transformation.new)
                p1 = entity.start.position
                p2 = entity.end.position
                x_min, x_max = [p1.x, p2.x].minmax
                y_min, y_max = [p1.y, p2.y].minmax
                z_min, z_max = [p1.z, p2.z].minmax

                vec = p1.vector_to(p2)
                dir = vec.normalize rescue nil
                next unless dir

                dir = dir.reverse if dir.x < 0 || (dir.x.zero? && dir.y < 0) || (dir.x.zero? && dir.y.zero? && dir.z < 0)
                line = [p1, dir]
                anchor = Geom::Point3d.new(0, 0, 0).project_to_line(line) rescue p1

                edges_data << {
                  edge: entity,
                  path: [],
                  p1: p1,
                  p2: p2,
                  x_min: x_min,
                  x_max: x_max,
                  y_min: y_min,
                  y_max: y_max,
                  z_min: z_min,
                  z_max: z_max,
                  transformation: Geom::Transformation.new,
                  split_points: [],
                  overlap_intervals: [],
                  dir: dir,
                  anchor: anchor,
                  faces_info: faces_info
                }
              end
            end

            n = edges_data.length
            if n < 2
              Sketchup.status_text = '[NAUQ] Không tìm thấy đủ cạnh trong vùng quét để so sánh nét trùng.'
              model.abort_operation
              return
            end

            # 2. Direction Grouping
            dir_groups = []
            edges_data.each do |e|
              group = dir_groups.find { |g| g[:dir].dot(e[:dir]).abs > 0.9999 }
              if group
                group[:edges] << e
              else
                dir_groups << { dir: e[:dir], edges: [e] }
              end
            end

            # 3. Spatial Grid Hashing (2.0 inch cells)
            grid_size = 2.0
            dir_groups.each do |dg|
              grid = Hash.new { |h, k| h[k] = [] }

              dg[:edges].each do |e|
                ap = e[:anchor]
                cx = (ap.x / grid_size).floor
                cy = (ap.y / grid_size).floor
                cz = (ap.z / grid_size).floor
                e[:cell] = [cx, cy, cz]
                grid[e[:cell]] << e
              end

              # Scan each cell & 26 neighbors
              grid.each do |cell_key, cell_edges|
                cx, cy, cz = cell_key
                n_cell = cell_edges.length

                # Intra-cell check
                (0...n_cell).each do |i|
                  e1 = cell_edges[i]
                  ((i + 1)...n_cell).each do |j|
                    e2 = cell_edges[j]
                    check_and_mark_overlap(e1, e2)
                  end
                end

                # Inter-cell 26-neighbors check
                (-1..1).each do |dx|
                  (-1..1).each do |dy|
                    (-1..1).each do |dz|
                      next if dx.zero? && dy.zero? && dz.zero?

                      neighbor_key = [cx + dx, cy + dy, cz + dz]
                      next if (neighbor_key <=> cell_key) <= 0
                      next unless grid.key?(neighbor_key)

                      grid[neighbor_key].each do |e2|
                        cell_edges.each do |e1|
                          check_and_mark_overlap(e1, e2)
                        end
                      end
                    end
                  end
                end
              end
            end

            # 4. Split edges and hide overlapping segments
            edges_data.each do |e|
              edge = e[:edge]
              next unless edge&.valid?

              if !e[:split_points].empty?
                trans_inv = e[:transformation].inverse
                local_points = e[:split_points].map { |p| p.transform(trans_inv) }
                local_points = merge_close_points(local_points, TOLERANCE)

                start_pos = edge.start.position
                local_points.sort_by! { |p| start_pos.distance(p) }.reverse!

                sub_segments = [edge]
                current_edge = edge

                local_points.each do |p_local|
                  next unless current_edge&.valid?
                  d_start = current_edge.start.position.distance(p_local)
                  d_end = current_edge.end.position.distance(p_local)

                  if d_start > TOLERANCE && d_end > TOLERANCE
                    begin
                      new_edge = current_edge.split(p_local)
                      if new_edge&.valid?
                        sub_segments << new_edge
                        stats[:splits] += 1
                      end
                    rescue StandardError
                      nil
                    end
                  end
                end

                sub_segments.each do |piece|
                  next unless piece&.valid?

                  mid_local = Geom::Point3d.linear_combination(0.5, piece.start.position, 0.5, piece.end.position)
                  mid_global = mid_local.transform(e[:transformation])

                  overlaps = e[:overlap_intervals].any? do |seg_start, seg_end|
                    point_on_segment?(mid_global, seg_start, seg_end, TOLERANCE)
                  end

                  if overlaps && piece.visible?
                    piece.visible = false
                    stats[:hidden] += 1
                  end
                end
              elsif !e[:overlap_intervals].empty? && edge.visible?
                edge.visible = false
                stats[:hidden] += 1
              end
            end

            model.commit_operation
            Sketchup.status_text = "[NAUQ] Đã ẩn thành công #{stats[:hidden]} phân đoạn cạnh trùng lặp!"
            Logger.info("Đã ẩn #{stats[:hidden]} cạnh trùng (chia #{stats[:splits]} lần).") if defined?(Logger)
            stats[:hidden].to_i
          rescue StandardError => e
            model.abort_operation
            UI.messagebox("Lỗi khi ẩn nét trùng: #{e.message}")
            0
          end
        end

        # Unhide hidden edges strictly within the selected entities (or entire model if empty)
        def unhide_selected_edges
          model = Sketchup.active_model
          return 0 unless model

          selection = model.selection
          target_entities = selection.empty? ? model.entities : selection

          model.start_operation('NAUQ Hiện Nét Ẩn Vùng Chọn', true)
          unhidden_count = 0
          unsoftened_count = 0
          unhidden_groups = 0
          scanned_entities = 0
          visited_definitions = {}

          unhide_entity = nil
          unhide_entity = lambda do |ent|
            return unless ent&.valid?
            scanned_entities += 1

            if ent.is_a?(Sketchup::Edge)
              was_hidden = !ent.visible? || ent.hidden?
              was_soft = ent.soft? || ent.smooth?

              if was_hidden
                ent.visible = true
                ent.hidden = false
                unhidden_count += 1
              end

              if was_soft
                ent.soft = false
                ent.smooth = false
                unsoftened_count += 1
              end

            elsif ent.is_a?(Sketchup::Face)
              ent.edges.each do |edge|
                next unless edge.valid?
                scanned_entities += 1
                was_hidden = !edge.visible? || edge.hidden?
                was_soft = edge.soft? || edge.smooth?

                if was_hidden
                  edge.visible = true
                  edge.hidden = false
                  unhidden_count += 1
                end

                if was_soft
                  edge.soft = false
                  edge.smooth = false
                  unsoftened_count += 1
                end
              end

            elsif ent.is_a?(Sketchup::Group)
              if !ent.visible? || ent.hidden?
                ent.visible = true
                ent.hidden = false
                unhidden_groups += 1
              end

              # Recurse inside group entities
              if ent.respond_to?(:entities)
                ent.entities.each { |child| unhide_entity.call(child) }
              end
              if ent.respond_to?(:definition)
                def_id = ent.definition.object_id
                unless visited_definitions[def_id]
                  visited_definitions[def_id] = true
                  ent.definition.entities.each { |child| unhide_entity.call(child) }
                end
              end

            elsif ent.is_a?(Sketchup::ComponentInstance)
              if !ent.visible? || ent.hidden?
                ent.visible = true
                ent.hidden = false
                unhidden_groups += 1
              end

              def_id = ent.definition.object_id
              unless visited_definitions[def_id]
                visited_definitions[def_id] = true
                ent.definition.entities.each { |child| unhide_entity.call(child) }
              end

            elsif ent.respond_to?(:each)
              ent.each { |child| unhide_entity.call(child) }
            end
          end

          target_entities.each { |ent| unhide_entity.call(ent) }
          model.commit_operation
          model.active_view.invalidate rescue nil

          total_restored = unhidden_count + unsoftened_count + unhidden_groups

          msg = if total_restored > 0
                  details = []
                  details << "#{unhidden_count} nét ẩn (Hidden)" if unhidden_count > 0
                  details << "#{unsoftened_count} nét làm mềm (Soft/Smooth)" if unsoftened_count > 0
                  details << "#{unhidden_groups} nhóm đối tượng (Group/Component)" if unhidden_groups > 0
                  "Đã phục hồi hiển thị thành công: #{details.join(', ')} (quét #{scanned_entities} đối tượng)!"
                else
                  "Đã quét #{scanned_entities} đối tượng: Toàn bộ nét vẽ và bề mặt đang ở trạng thái hiển thị bình thường (không có nét ẩn hay nét bị làm mềm)."
                end

          Sketchup.status_text = "[NAUQ] #{msg}"
          ::UI.messagebox(msg, MB_OK) if defined?(::UI)
          Logger.info("[NAUQ] #{msg}") if defined?(Logger)
          total_restored.to_i
        rescue StandardError => e
          model.abort_operation rescue nil
          Logger.error("Lỗi khi hiện nét ẩn: #{e.message}\n#{e.backtrace ? e.backtrace.first(5).join("\n") : ''}") if defined?(Logger)
          ::UI.messagebox("Lỗi khi hiện nét ẩn: #{e.message}", MB_OK) if defined?(::UI)
          0
        end

        alias unhide_all_edges unhide_selected_edges

        private

        def check_and_mark_overlap(e1, e2)
          return if e1[:path] == e2[:path]
          return if e1[:x_min] - TOLERANCE > e2[:x_max] || e2[:x_min] - TOLERANCE > e1[:x_max]
          return if e1[:y_min] - TOLERANCE > e2[:y_max] || e2[:y_min] - TOLERANCE > e1[:y_max]
          return if e1[:z_min] - TOLERANCE > e2[:z_max] || e2[:z_min] - TOLERANCE > e1[:z_max]

          return unless segments_overlap_info?(e1[:p1], e1[:p2], e2[:p1], e2[:p2], TOLERANCE)
          return unless edges_coplanar_precalc?(e1, e2, 0.001)

          overlap_p1, overlap_p2 = get_overlap_points(e1[:p1], e1[:p2], e2[:p1], e2[:p2])

          e1[:split_points] << overlap_p1 if need_split?(e1[:p1], e1[:p2], overlap_p1, TOLERANCE)
          e1[:split_points] << overlap_p2 if need_split?(e1[:p1], e1[:p2], overlap_p2, TOLERANCE)

          e2[:split_points] << overlap_p1 if need_split?(e2[:p1], e2[:p2], overlap_p1, TOLERANCE)
          e2[:split_points] << overlap_p2 if need_split?(e2[:p1], e2[:p2], overlap_p2, TOLERANCE)

          e1[:overlap_intervals] << [overlap_p1, overlap_p2]
          e2[:overlap_intervals] << [overlap_p1, overlap_p2]
        end

        def segments_overlap_info?(a, b, c, d, tolerance = TOLERANCE)
          vec_ab = a.vector_to(b)
          len_ab = vec_ab.length
          return false if len_ab < tolerance

          v = vec_ab.normalize rescue nil
          return false unless v

          line_ab = [a, v]
          return false if c.distance_to_line(line_ab) > tolerance
          return false if d.distance_to_line(line_ab) > tolerance

          t_a = 0.0
          t_b = len_ab
          t_c = a.vector_to(c).dot(v) rescue 0.0
          t_d = a.vector_to(d).dot(v) rescue 0.0

          t2_min, t2_max = [t_c, t_d].minmax
          overlap_start = [t_a, t2_min].max
          overlap_end = [t_b, t2_max].min

          (overlap_end - overlap_start) > tolerance
        end

        def get_overlap_points(a, b, c, d)
          v = a.vector_to(b).normalize
          t_a = 0.0
          t_b = a.distance(b)
          t_c = a.vector_to(c).dot(v) rescue 0.0
          t_d = a.vector_to(d).dot(v) rescue 0.0

          t2_min, t2_max = [t_c, t_d].minmax
          overlap_start = [t_a, t2_min].max
          overlap_end = [t_b, t2_max].min

          [a.offset(v, overlap_start), a.offset(v, overlap_end)]
        end

        def point_on_segment?(p, seg_start, seg_end, tolerance = TOLERANCE)
          d_total = seg_start.distance(seg_end)
          return false if d_total < tolerance

          d1 = p.distance(seg_start)
          d2 = p.distance(seg_end)
          (d1 + d2 - d_total) < tolerance
        end

        def need_split?(a, b, p, tolerance = TOLERANCE)
          a.distance(p) > tolerance && b.distance(p) > tolerance
        end

        def merge_close_points(points, tolerance = TOLERANCE)
          merged = []
          points.each do |p|
            merged << p unless merged.any? { |mp| mp.distance(p) < tolerance }
          end
          merged
        end

        def edges_coplanar_precalc?(e1_data, e2_data, tolerance = 0.001)
          fi1 = e1_data[:faces_info]
          fi2 = e2_data[:faces_info]
          return true if fi1.empty? || fi2.empty?

          all_p1 = fi1.all? do |f1|
            n1 = f1[:normal]
            next true unless n1
            fi2.any? { |f2| f2[:normal] && n1.dot(f2[:normal]).abs > 1.0 - tolerance }
          end

          all_p2 = fi2.all? do |f2|
            n2 = f2[:normal]
            next true unless n2
            fi1.any? { |f1| f1[:normal] && n2.dot(f1[:normal]).abs > 1.0 - tolerance }
          end

          all_p1 && all_p2
        end

        def extract_faces_info(edge, trans)
          edge.faces.filter_map do |face|
            normal = face.normal.transform(trans).normalize rescue nil
            { normal: normal }
          end
        end

        def traverse_entities(entities, current_trans, current_path, edges_data, stats)
          entities.each do |child|
            if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
              make_unique_safe(child, stats)
              new_trans = current_trans * child.transformation
              new_path = current_path + [child]
              traverse_entities(child.definition.entities, new_trans, new_path, edges_data, stats)
            elsif child.is_a?(Sketchup::Edge)
              faces_info = extract_faces_info(child, current_trans)

              p1 = child.start.position.transform(current_trans)
              p2 = child.end.position.transform(current_trans)
              x_min, x_max = [p1.x, p2.x].minmax
              y_min, y_max = [p1.y, p2.y].minmax
              z_min, z_max = [p1.z, p2.z].minmax

              vec = p1.vector_to(p2)
              dir = vec.normalize rescue nil
              next unless dir

              dir = dir.reverse if dir.x < 0 || (dir.x.zero? && dir.y < 0) || (dir.x.zero? && dir.y.zero? && dir.z < 0)
              line = [p1, dir]
              anchor = Geom::Point3d.new(0, 0, 0).project_to_line(line) rescue p1

              edges_data << {
                edge: child,
                path: current_path,
                p1: p1,
                p2: p2,
                x_min: x_min,
                x_max: x_max,
                y_min: y_min,
                y_max: y_max,
                z_min: z_min,
                z_max: z_max,
                transformation: current_trans,
                split_points: [],
                overlap_intervals: [],
                dir: dir,
                anchor: anchor,
                faces_info: faces_info
              }
            end
          end
        end

        def make_unique_safe(entity, stats)
          return unless entity.respond_to?(:make_unique)
          return unless entity.definition.instances.size > 1

          entity.make_unique rescue nil
          if entity.is_a?(Sketchup::Group)
            stats[:groups_unique] += 1
          else
            stats[:components_unique] += 1
          end
        end
      end
    end
  end
end
