# frozen_string_literal: true

require_relative 'railing_builder'

module NAUQ
  module CadTo3D
    # Construction-Accurate 3D Monolithic Concrete Stair Generator
    # Powered by SketchUp Solid Boolean Union Engine
    # Supports Flat Landings, 2-Step Winders, and 3-Step Radial Winders
    module StairBuilder
      DEFAULT_SLAB_THICKNESS = 100.0 unless defined?(DEFAULT_SLAB_THICKNESS)
      BEAM_EXTENSION_MM = 100.0 unless defined?(BEAM_EXTENSION_MM)

      class << self
        # Builds complete monolithic 3D concrete stair assembly
        # @param params [Hash] stair specifications
        # @param parent_entities [Sketchup::Entities]
        # @return [Sketchup::Group] stair assembly group
        def build(params, parent_entities = nil)
          model = Sketchup.active_model
          parent_entities ||= model.active_entities

          # 1. Extract & normalize parameters
          type = (params[:type] || params['type'] || 'u_shape_3').to_sym
          floor_height = (params[:floor_height] || params['floor_height'] || 3600.0).to_f.mm
          total_steps = (params[:total_steps] || params['total_steps'] || 21).to_i
          total_steps = 21 if total_steps < 3

          stair_width = (params[:stair_width] || params['stair_width'] || 1000.0).to_f.mm
          tread_run = (params[:tread_run] || params['tread_run'] || 270.0).to_f.mm
          slab_thickness = (params[:slab_thickness] || params['slab_thickness'] || DEFAULT_SLAB_THICKNESS).to_f.mm

          # Sub-divisions (Total steps = N1 + N2 + N3)
          flight1_steps = (params[:flight1_steps] || params['flight1_steps'] || 8).to_i
          flight2_steps = (params[:flight2_steps] || params['flight2_steps'] || 5).to_i
          flight3_steps = (params[:flight3_steps] || params['flight3_steps'] || (total_steps - flight1_steps - flight2_steps)).to_i

          riser_height = floor_height / total_steps.to_f

          # Winder mode: 0 (flat), 2 (2-step winder), 3 (3-step winder)
          raw_winder = params[:winder_landing] || params['winder_landing']
          winder_mode = if raw_winder.to_s == '3' || raw_winder == 3
                          3
                        elsif raw_winder == true || raw_winder == 'true' || raw_winder == 1 || raw_winder.to_s == '2' || raw_winder == 2
                          2
                        else
                          0
                        end

          # Create Master Stair Assembly Group with Identity Origin (0,0,0)
          master_group = parent_entities.add_group
          master_group.name = "NAUQ_STAIR_#{type.upcase}"

          # 2. Build Solid Groups for each segment inside master_group
          solid_pieces = []

          case type
          when :straight
            solid_pieces << create_flight_solid(
              master_group.entities,
              Geom::Point3d.new(0, 0, 0),
              Geom::Vector3d.new(1, 0, 0),
              Geom::Vector3d.new(0, -1, 0),
              total_steps, riser_height, tread_run, stair_width, slab_thickness,
              false, # has_top_ext = false -> Bậc cuối cùng chỉ để 1 face đứng phẳng
              true   # is_bottom_floor -> Chân thang cắt phẳng tại cốt sàn Z=0
            )
          when :l_shape
            f1 = flight1_steps
            landing_extra = winder_mode == 3 ? 2 : (winder_mode == 2 ? 1 : 0)
            f2 = [1, total_steps - f1 - landing_extra].max
            solid_pieces.concat(build_l_shape_solids(master_group.entities, f1, f2, riser_height, tread_run, stair_width, slab_thickness, winder_mode))
          else # :u_shape_3 (Default: Thang chữ U 3 vế)
            f1 = flight1_steps
            f2 = flight2_steps
            landing_extra = winder_mode == 3 ? 4 : (winder_mode == 2 ? 2 : 0)
            f3 = [1, total_steps - f1 - f2 - landing_extra].max
            solid_pieces.concat(build_u_shape_3_solids(master_group.entities, f1, f2, f3, riser_height, tread_run, stair_width, slab_thickness, winder_mode))
          end

          # 3. Boolean Union all solid pieces into monolithic concrete body
          concrete_body = union_all_solids(master_group.entities, solid_pieces)
          concrete_body.name = 'CONCRETE_BODY' if concrete_body && concrete_body.valid?

          # 4. Clean coplanar seam edges across concrete body
          clean_coplanar_edges(concrete_body.entities) if concrete_body && concrete_body.valid?

          # 5. Build 3D Railing Assembly inside master_group (perfectly aligned with Identity Origin)
          if defined?(RailingBuilder)
            RailingBuilder.build(params, master_group)
          end

          # 6. Tag metadata
          Attribute.tag(master_group, 'stair_assembly', {
            'floor_height_mm' => floor_height.to_mm,
            'total_steps' => total_steps,
            'riser_height_mm' => riser_height.to_mm,
            'type' => type.to_s,
            'winder_landing' => winder_mode
          })

          Logger.info("Đã tạo thành công Cầu Thang Boolean #{type} (#{total_steps} bậc, cao #{floor_height.to_mm.round(0)}mm, cổ bậc #{riser_height.to_mm.round(1)}mm, chiếu nghỉ: mode #{winder_mode}).") if defined?(Logger)
          master_group
        end

        private

        # Dựng 1 vế thang Solid độc lập bằng PushPull biên dạng 2D
        def create_flight_solid(parent_entities, start_pt, fwd_vec, right_vec, num_steps, h, b, w, slab_t, has_top_ext = true, is_bottom_floor = false)
          return nil if num_steps <= 0

          grp = parent_entities.add_group
          fwd = fwd_vec.normalize
          right = right_vec.normalize
          up = Geom::Vector3d.new(0, 0, 1)

          slope_angle = Math.atan2(h, b)
          cos_a = Math.cos(slope_angle)
          d_z = slab_t / cos_a
          ext_len = has_top_ext ? BEAM_EXTENSION_MM.mm : 0.mm

          pts = []
          pts << start_pt.clone

          (0...(num_steps - 1)).each do |i|
            pts << start_pt.offset(fwd, i * b).offset(up, (i + 1) * h)
            pts << start_pt.offset(fwd, (i + 1) * b).offset(up, (i + 1) * h)
          end

          f1_end_dist = (num_steps - 1) * b
          pts << start_pt.offset(fwd, f1_end_dist).offset(up, num_steps * h)

          z_waist_top = ((num_steps - 1) * h) - d_z
          if has_top_ext
            pts << start_pt.offset(fwd, f1_end_dist + ext_len).offset(up, num_steps * h)
            pts << start_pt.offset(fwd, f1_end_dist + ext_len).offset(up, z_waist_top)
          end
          pts << start_pt.offset(fwd, f1_end_dist).offset(up, z_waist_top)

          if is_bottom_floor
            x_floor_cut = (d_z * b) / h
            pts << start_pt.offset(fwd, x_floor_cut)
          else
            x_landing_cut = [0.0, ((d_z - slab_t) * b) / h].max
            pts << start_pt.offset(fwd, x_landing_cut).offset(up, -slab_t)
            pts << start_pt.offset(up, -slab_t)
          end

          face = grp.entities.add_face(pts)
          if face
            if face.normal.samedirection?(right)
              face.pushpull(w)
            else
              face.pushpull(-w)
            end
          end
          grp
        end

        # Dựng 1 tấm Chiếu nghỉ phẳng Solid W x W bằng PushPull
        def create_landing_box_solid(parent_entities, p_min, p_max, z_top, thickness)
          grp = parent_entities.add_group
          x1 = [p_min.x, p_max.x].min
          x2 = [p_min.x, p_max.x].max
          y1 = [p_min.y, p_max.y].min
          y2 = [p_min.y, p_max.y].max

          pts = [
            Geom::Point3d.new(x1, y1, z_top),
            Geom::Point3d.new(x2, y1, z_top),
            Geom::Point3d.new(x2, y2, z_top),
            Geom::Point3d.new(x1, y2, z_top)
          ]
          face = grp.entities.add_face(pts)
          if face
            face.normal.z > 0 ? face.pushpull(-thickness) : face.pushpull(thickness)
          end
          grp
        end

        # Dựng Chiếu nghỉ Chia 2 Bậc Chéo 1 Solid (Landing 1 - Corner Left)
        def create_winder_2_landing_1_solid(parent_entities, x1, x2, y1, y2, z_top, h, slab_t)
          grp_a = parent_entities.add_group
          pts_a = [
            Geom::Point3d.new(x1, y1, z_top),
            Geom::Point3d.new(x2, y2, z_top),
            Geom::Point3d.new(x1, y2, z_top)
          ]
          face_a = grp_a.entities.add_face(pts_a)
          face_a.pushpull(-slab_t) if face_a

          grp_b = parent_entities.add_group
          z_upper = z_top + h
          pts_b = [
            Geom::Point3d.new(x1, y1, z_upper),
            Geom::Point3d.new(x2, y1, z_upper),
            Geom::Point3d.new(x2, y2, z_upper)
          ]
          face_b = grp_b.entities.add_face(pts_b)
          face_b.pushpull(-(slab_t + h)) if face_b

          union_all_solids(parent_entities, [grp_a, grp_b])
        end

        # Dựng Chiếu nghỉ Chia 2 Bậc Chéo 2 Solid (Landing 2 - Corner Right)
        def create_winder_2_landing_2_solid(parent_entities, x1, x2, y1, y2, z_top, h, slab_t)
          grp_a = parent_entities.add_group
          pts_a = [
            Geom::Point3d.new(x1, y2, z_top),
            Geom::Point3d.new(x2, y1, z_top),
            Geom::Point3d.new(x2, y2, z_top)
          ]
          face_a = grp_a.entities.add_face(pts_a)
          face_a.pushpull(-slab_t) if face_a

          grp_b = parent_entities.add_group
          z_upper = z_top + h
          pts_b = [
            Geom::Point3d.new(x1, y2, z_upper),
            Geom::Point3d.new(x1, y1, z_upper),
            Geom::Point3d.new(x2, y1, z_upper)
          ]
          face_b = grp_b.entities.add_face(pts_b)
          face_b.pushpull(-(slab_t + h)) if face_b

          union_all_solids(parent_entities, [grp_a, grp_b])
        end

        # Dựng Chiếu nghỉ Chia 3 Bậc Chéo 1 Solid (Landing 1 - Corner Left)
        def create_winder_3_landing_1_solid(parent_entities, x1, x2, y1, y2, z_top, h, slab_t)
          w = (x2 - x1).abs
          # Step 1 at z_top
          grp_1 = parent_entities.add_group
          pts_1 = [
            Geom::Point3d.new(x1, y1, z_top),
            Geom::Point3d.new(x1 + w / 2.0, y2, z_top),
            Geom::Point3d.new(x1, y2, z_top)
          ]
          face_1 = grp_1.entities.add_face(pts_1)
          face_1.pushpull(-slab_t) if face_1

          # Step 2 at z_top + h
          grp_2 = parent_entities.add_group
          pts_2 = [
            Geom::Point3d.new(x1, y1, z_top + h),
            Geom::Point3d.new(x2, y1 + w / 2.0, z_top + h),
            Geom::Point3d.new(x2, y2, z_top + h),
            Geom::Point3d.new(x1 + w / 2.0, y2, z_top + h)
          ]
          face_2 = grp_2.entities.add_face(pts_2)
          face_2.pushpull(-(slab_t + h)) if face_2

          # Step 3 at z_top + 2*h
          grp_3 = parent_entities.add_group
          pts_3 = [
            Geom::Point3d.new(x1, y1, z_top + 2 * h),
            Geom::Point3d.new(x2, y1, z_top + 2 * h),
            Geom::Point3d.new(x2, y1 + w / 2.0, z_top + 2 * h)
          ]
          face_3 = grp_3.entities.add_face(pts_3)
          face_3.pushpull(-(slab_t + 2 * h)) if face_3

          union_all_solids(parent_entities, [grp_1, grp_2, grp_3])
        end

        # Dựng Chiếu nghỉ Chia 3 Bậc Chéo 2 Solid (Landing 2 - Corner Right)
        def create_winder_3_landing_2_solid(parent_entities, x1, x2, y1, y2, z_top, h, slab_t)
          w = (x2 - x1).abs
          # Step 1 at z_top
          grp_1 = parent_entities.add_group
          pts_1 = [
            Geom::Point3d.new(x1, y2, z_top),
            Geom::Point3d.new(x2, y2 - w / 2.0, z_top),
            Geom::Point3d.new(x2, y2, z_top)
          ]
          face_1 = grp_1.entities.add_face(pts_1)
          face_1.pushpull(-slab_t) if face_1

          # Step 2 at z_top + h
          grp_2 = parent_entities.add_group
          pts_2 = [
            Geom::Point3d.new(x1, y2, z_top + h),
            Geom::Point3d.new(x1 + w / 2.0, y1, z_top + h),
            Geom::Point3d.new(x2, y1, z_top + h),
            Geom::Point3d.new(x2, y2 - w / 2.0, z_top + h)
          ]
          face_2 = grp_2.entities.add_face(pts_2)
          face_2.pushpull(-(slab_t + h)) if face_2

          # Step 3 at z_top + 2*h
          grp_3 = parent_entities.add_group
          pts_3 = [
            Geom::Point3d.new(x1, y2, z_top + 2 * h),
            Geom::Point3d.new(x1, y1, z_top + 2 * h),
            Geom::Point3d.new(x1 + w / 2.0, y1, z_top + 2 * h)
          ]
          face_3 = grp_3.entities.add_face(pts_3)
          face_3.pushpull(-(slab_t + 2 * h)) if face_3

          union_all_solids(parent_entities, [grp_1, grp_2, grp_3])
        end

        # Dựng danh sách các khối Solid của Thang Chữ U 3 Vế
        def build_u_shape_3_solids(parent_entities, n1, n2, n3, h, b, w, slab_t, winder_mode = 0)
          solids = []
          f1_len = (n1 - 1) * b

          # Flight 1: có dầm 100mm gối vào Chiếu nghỉ 1
          solids << create_flight_solid(
            parent_entities,
            Geom::Point3d.new(0, 0, 0),
            Geom::Vector3d.new(1, 0, 0),
            Geom::Vector3d.new(0, -1, 0),
            n1, h, b, w, slab_t,
            true, # has_top_ext
            true  # is_bottom_floor
          )

          # Landing 1
          z1 = n1 * h
          x1 = f1_len
          x2 = f1_len + w
          y1 = -w
          y2 = 0.0

          if winder_mode == 3
            solids << create_winder_3_landing_1_solid(parent_entities, x1, x2, y1, y2, z1, h, slab_t)
            f2_start_z = z1 + 2 * h
          elsif winder_mode == 2
            solids << create_winder_2_landing_1_solid(parent_entities, x1, x2, y1, y2, z1, h, slab_t)
            f2_start_z = z1 + h
          else
            solids << create_landing_box_solid(parent_entities, Geom::Point3d.new(x1, y2, 0), Geom::Point3d.new(x2, y1, 0), z1, slab_t)
            f2_start_z = z1
          end

          # Flight 2: Vế ngang giữa đi theo -Y, có dầm 100mm gối vào Chiếu nghỉ 2
          f2_len = (n2 - 1) * b
          f2_start = Geom::Point3d.new(f1_len, -w, f2_start_z)
          solids << create_flight_solid(
            parent_entities,
            f2_start,
            Geom::Vector3d.new(0, -1, 0),
            Geom::Vector3d.new(1, 0, 0),
            n2, h, b, w, slab_t,
            true, # has_top_ext
            false # is_bottom_floor
          )

          # Landing 2
          z2 = f2_start_z + n2 * h
          l2_y2 = -w - f2_len
          l2_y1 = -2 * w - f2_len

          if winder_mode == 3
            solids << create_winder_3_landing_2_solid(parent_entities, x1, x2, l2_y1, l2_y2, z2, h, slab_t)
            f3_start_z = z2 + 2 * h
          elsif winder_mode == 2
            solids << create_winder_2_landing_2_solid(parent_entities, x1, x2, l2_y1, l2_y2, z2, h, slab_t)
            f3_start_z = z2 + h
          else
            solids << create_landing_box_solid(parent_entities, Geom::Point3d.new(x1, l2_y2, 0), Geom::Point3d.new(x2, l2_y1, 0), z2, slab_t)
            f3_start_z = z2
          end

          # Flight 3: Vế quay về đi theo -X, bậc cuối lên sàn tầng trên (has_top_ext = false)
          f3_start = Geom::Point3d.new(f1_len, l2_y2, f3_start_z)
          solids << create_flight_solid(
            parent_entities,
            f3_start,
            Geom::Vector3d.new(-1, 0, 0),
            Geom::Vector3d.new(0, -1, 0),
            n3, h, b, w, slab_t,
            false, # has_top_ext = false -> Bậc cuối chỉ để 1 face đứng phẳng
            false  # is_bottom_floor
          )

          solids
        end

        # Dựng danh sách các khối Solid của Thang Chữ L (90 độ)
        def build_l_shape_solids(parent_entities, n1, n2, h, b, w, slab_t, winder_mode = 0)
          solids = []
          f1_len = (n1 - 1) * b

          # Flight 1
          solids << create_flight_solid(
            parent_entities,
            Geom::Point3d.new(0, 0, 0),
            Geom::Vector3d.new(1, 0, 0),
            Geom::Vector3d.new(0, -1, 0),
            n1, h, b, w, slab_t,
            true, # has_top_ext
            true  # is_bottom_floor
          )

          # Landing
          z1 = n1 * h
          x1 = f1_len
          x2 = f1_len + w
          y1 = -w
          y2 = 0.0

          if winder_mode == 3
            solids << create_winder_3_landing_1_solid(parent_entities, x1, x2, y1, y2, z1, h, slab_t)
            f2_start_z = z1 + 2 * h
          elsif winder_mode == 2
            solids << create_winder_2_landing_1_solid(parent_entities, x1, x2, y1, y2, z1, h, slab_t)
            f2_start_z = z1 + h
          else
            solids << create_landing_box_solid(parent_entities, Geom::Point3d.new(x1, y2, 0), Geom::Point3d.new(x2, y1, 0), z1, slab_t)
            f2_start_z = z1
          end

          # Flight 2
          f2_start = Geom::Point3d.new(f1_len, -w, f2_start_z)
          solids << create_flight_solid(
            parent_entities,
            f2_start,
            Geom::Vector3d.new(0, -1, 0),
            Geom::Vector3d.new(1, 0, 0),
            n2, h, b, w, slab_t,
            false, # has_top_ext = false -> Bậc cuối lên sàn tầng trên
            false  # is_bottom_floor
          )

          solids
        end

        # Hợp nhất tất cả các khối Solid thành 1 Solid duy nhất bằng Boolean Union
        def union_all_solids(parent_entities, pieces)
          valid_pieces = pieces.compact.select { |p| p && p.valid? }
          return parent_entities.add_group if valid_pieces.empty?
          return valid_pieces.first if valid_pieces.length == 1

          result_group = valid_pieces.shift
          valid_pieces.each do |piece|
            next unless piece && piece.valid?
            if result_group.respond_to?(:union) && result_group.manifold? && piece.manifold?
              union_res = result_group.union(piece)
              if union_res && union_res.valid?
                result_group = union_res
                next
              end
            end
            # Fallback: Chuyển toàn bộ hình học của piece vào bên trong result_group theo tọa độ chuẩn World
            t_source = piece.transformation
            t_target_inv = result_group.transformation.inverse
            piece.entities.to_a.each do |e|
              if e.is_a?(Sketchup::Face)
                world_pts = e.vertices.map { |v| v.position.transform(t_source) }
                local_pts = world_pts.map { |pt| pt.transform(t_target_inv) }
                result_group.entities.add_face(local_pts) rescue nil
              end
            end
            piece.erase! rescue nil
          end
          result_group
        end

        # S4U Edge Cleaner: Xoá sạch toàn bộ nét thừa trên mặt phẳng và giữ sắc nét các góc cạnh 90°
        def clean_coplanar_edges(ents)
          return unless ents

          # 1. Xoá cạnh rác không thuộc mặt nào
          ents.grep(Sketchup::Edge).each do |e|
            e.erase! if e && e.valid? && e.faces.empty?
          end

          # 2. Xoá nét giáp ranh giữa các mặt đồng phẳng
          4.times do
            deleted_any = false
            ents.grep(Sketchup::Edge).each do |e|
              next unless e && e.valid?

              if e.faces.length == 2
                f1 = e.faces[0]
                f2 = e.faces[1]
                if f1.normal.parallel?(f2.normal)
                  e.erase! rescue nil
                  deleted_any = true
                end
              end
            end
            break unless deleted_any
          end

          # 3. Với các cạnh giáp ranh đồng phẳng còn lại (kẹp giữa các mặt song song), ẩn đi
          ents.grep(Sketchup::Edge).each do |e|
            next unless e && e.valid?
            next if e.faces.length < 2

            faces = e.faces
            (0...faces.length).each do |i|
              ((i + 1)...faces.length).each do |j|
                if faces[i].normal.parallel?(faces[j].normal)
                  e.hidden = true
                  e.soft = true
                  e.smooth = true
                  break
                end
              end
              break if e.hidden?
            end
          end
        end
      end
    end
  end
end
