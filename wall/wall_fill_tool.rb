# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Interactive Tool to create WallFill (Lintels & Window Sills) by clicking wall jamb faces
    class WallFillTool
      GEOMETRY_TOLERANCE = 0.001 unless const_defined?(:GEOMETRY_TOLERANCE)
      MIN_BRIDGE_OVERLAP_MM = 20.0 unless const_defined?(:MIN_BRIDGE_OVERLAP_MM)

      PREVIEW_FILL_RGBA = [59, 130, 246, 120].freeze unless const_defined?(:PREVIEW_FILL_RGBA)
      PREVIEW_EDGE_RGBA = [37, 99, 235, 255].freeze unless const_defined?(:PREVIEW_EDGE_RGBA)

      def initialize(mode = :door)
        @mode = mode # :door or :window
        @door_height = (Config.get(:door_height) || 2200.0).to_f.mm
        @sill_height = (Config.get(:window_offset) || 800.0).to_f.mm
        @window_top  = (Config.get(:door_height) || 2200.0).to_f.mm

        @input_point = Sketchup::InputPoint.new
        @preview_points = nil
        @preview_fill_color = Sketchup::Color.new(*PREVIEW_FILL_RGBA)
        @preview_edge_color = Sketchup::Color.new(*PREVIEW_EDGE_RGBA)
      end

      def activate
        update_status_text
      end

      def resume(view)
        update_status_text
        view.invalidate
      end

      def deactivate(view)
        @preview_points = nil
        view.invalidate
      end

      def suspend(view)
        view.invalidate
      end

      # Lintel/sill preview is drawn to the viewport; provide extents so the
      # preview is never clipped (SketchupSuggestions/ToolDrawingBounds).
      def getExtents
        bb = Geom::BoundingBox.new
        (@preview_points || []).each do |pts|
          pts.each { |pt| bb.add(pt) }
        end
        bb
      end

      # The VCB accepts typed wallfill heights (see onUserText).
      def enableVCB?
        true
      end

      def update_status_text
        h_mm = @mode == :door ? @door_height.to_mm.round(0) : "#{@sill_height.to_mm.round(0)},#{@window_top.to_mm.round(0)}"
        mode_str = @mode == :door ? "CỬA ĐI (Lanh-tô: #{h_mm}mm)" : "CỬA SỔ (Bậu/Lanh-tô: #{h_mm}mm)"
        Sketchup.status_text = "[NAUQ WALLFILL - #{mode_str}] Click vào mặt hốc tường để tạo | Nhấn [TAB] để đổi Cửa đi / Cửa sổ | Gõ chiều cao vào ô kích thước"
      end

      def onMouseMove(_flags, x, y, view)
        @input_point.pick(view, x, y)
        context = pick_context(@input_point)

        @preview_points = nil
        if context
          bridge = bridge_hit(context[:face], context[:transformation], context[:instance_path])
          if bridge
            local_profiles = if @mode == :door
                               door_preview_profiles(context[:face], @door_height)
                             else
                               window_preview_profiles(context[:face], @sill_height, @window_top)
                             end

            if local_profiles && local_profiles.any?
              @preview_points = local_profiles.map do |pts|
                pts.map { |pt| pt.transform(context[:transformation]) }
              end
            end
          end
        end

        view.invalidate
      rescue StandardError => e
        @preview_points = nil
        view.invalidate
      end

      def draw(view)
        return unless @preview_points && @preview_points.any?

        @preview_points.each do |pts|
          screen_pts = pts.map { |pt| view.screen_coords(pt) }
          view.drawing_color = @preview_fill_color
          view.draw2d(GL_QUADS, screen_pts)
          view.drawing_color = @preview_edge_color
          view.line_width = 2
          view.draw2d(GL_LINE_LOOP, screen_pts)
        end
      end

      def onLButtonDown(_flags, x, y, view)
        @input_point.pick(view, x, y)
        context = pick_context(@input_point)
        unless context
          UI.messagebox('Vui lòng click vào mặt phẳng hốc tường đứng hợp lệ.')
          return
        end

        model = Sketchup.active_model
        model.start_operation('NAUQ Tạo Lanh Tô', true)

        begin
          success = if @mode == :door
                      create_door_wallfill(context, @door_height)
                    else
                      create_window_wallfill(context, @sill_height, @window_top)
                    end

          if success
            model.commit_operation
            Logger.info("Đã tạo WallFill thành công cho #{@mode == :door ? 'Cửa đi' : 'Cửa sổ'}.") if defined?(Logger)
          else
            model.abort_operation
          end
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Lỗi khi tạo WallFill: #{e.message}")
        end

        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        # TAB or CTRL toggles between Door and Window modes
        if key == 9 || key == 17 # VK_TAB or VK_CONTROL
          @mode = (@mode == :door ? :window : :door)
          update_status_text
          view.invalidate
          return true
        end
        false
      end

      def onUserText(text, view)
        parts = text.to_s.split(',').map(&:strip).map(&:to_f)
        if parts.size == 1 && parts[0] > 0
          if @mode == :door
            @door_height = parts[0].mm
          else
            @window_top = parts[0].mm
          end
        elsif parts.size >= 2 && parts[0] >= 0 && parts[1] > parts[0]
          @mode = :window
          @sill_height = parts[0].mm
          @window_top = parts[1].mm
        end

        update_status_text
        view.invalidate
      end

      # =========================================================================
      # Geometric Algorithms (Engineered from LU_SmartWall & NAUQ WallFill)
      # =========================================================================

      private

      def pick_context(input_point)
        face = input_point.face
        return nil unless face && face.valid?
        # Only vertical faces (wall jambs)
        return nil if face.normal.z.abs > 0.1

        transformation = input_point.transformation || Geom::Transformation.new
        {
          face: face,
          transformation: transformation,
          instance_path: input_point.instance_path
        }
      end

      def door_preview_profiles(face, door_height)
        frame = wall_frame(face)
        return nil unless frame && door_height > 0
        return nil if frame[:base_z] + door_height >= frame[:wall_top] - GEOMETRY_TOLERANCE

        opening_top = frame[:base_z] + door_height
        [profile_between(frame[:top_points], opening_top, frame[:wall_top])]
      end

      def window_preview_profiles(face, sill_height, window_top)
        frame = wall_frame(face)
        return nil unless frame
        return nil if sill_height < 0 || window_top <= sill_height
        return nil if frame[:base_z] + window_top >= frame[:wall_top] - GEOMETRY_TOLERANCE

        sill_z = frame[:base_z] + sill_height
        win_top_z = frame[:base_z] + window_top

        profiles = []
        profiles << profile_between(frame[:top_points], frame[:base_z], sill_z) if sill_height > GEOMETRY_TOLERANCE
        profiles << profile_between(frame[:top_points], win_top_z, frame[:wall_top])
        profiles
      end

      def create_door_wallfill(context, door_height)
        face = context[:face]
        bridge = bridge_hit(face, context[:transformation], context[:instance_path])
        return false unless bridge

        profiles = door_preview_profiles(face, door_height)
        return false unless profiles && profiles.any?

        add_and_extrude_profiles(profiles, bridge[:distance], face, bridge[:face])
        true
      end

      def create_window_wallfill(context, sill_height, window_top)
        face = context[:face]
        bridge = bridge_hit(face, context[:transformation], context[:instance_path])
        return false unless bridge

        profiles = window_preview_profiles(face, sill_height, window_top)
        return false unless profiles && profiles.any?

        add_and_extrude_profiles(profiles, bridge[:distance], face, bridge[:face])
        true
      end

      def wall_frame(face)
        return nil unless face&.valid?

        vertices = face.outer_loop.vertices.map(&:position)
        return nil if vertices.length < 4

        sorted = vertices.sort_by(&:z)
        top_points = sorted.last(2)
        return nil unless top_points.length == 2
        return nil if (top_points[0].z - top_points[1].z).abs > 1.0 # mm tolerance
        return nil if top_points[0].distance(top_points[1]) <= 1.0

        base_z = sorted.first.z
        wall_top = top_points.map(&:z).max
        return nil unless wall_top > base_z + 1.0

        {
          base_z: base_z,
          wall_top: wall_top,
          top_points: top_points
        }
      end

      def profile_between(top_points, bottom_z, top_z)
        return nil unless top_z > bottom_z + GEOMETRY_TOLERANCE

        p1 = top_points[0]
        p2 = top_points[1]
        [
          Geom::Point3d.new(p1.x, p1.y, bottom_z),
          Geom::Point3d.new(p2.x, p2.y, bottom_z),
          Geom::Point3d.new(p2.x, p2.y, top_z),
          Geom::Point3d.new(p1.x, p1.y, top_z)
        ]
      end

      def bridge_hit(face, transformation = Geom::Transformation.new, instance_path = nil)
        source_frame = wall_frame(face)
        return nil unless source_frame

        entities = entities_for_face(face)
        return nil unless entities&.respond_to?(:grep)

        hits = entities.grep(Sketchup::Face).filter_map do |target_face|
          next if target_face == face || !target_face.valid?
          next unless target_face.normal.parallel?(face.normal)

          target_frame = wall_frame(target_face)
          next unless target_frame

          dist = source_frame[:top_points][0].vector_to(target_frame[:top_points][0]).dot(face.normal)
          next unless dist > GEOMETRY_TOLERANCE

          overlap = bridge_overlap(source_frame, target_frame)
          next unless overlap

          {
            distance: dist,
            face: target_face,
            overlap: overlap
          }
        end

        hits.min_by { |h| h[:distance] }
      end

      def bridge_overlap(source_frame, target_frame)
        source_start, source_end = source_frame[:top_points]
        lateral = source_start.vector_to(source_end)
        source_width = lateral.length
        return nil if source_width <= GEOMETRY_TOLERANCE

        lateral.normalize!
        target_positions = target_frame[:top_points].map do |point|
          source_start.vector_to(point).dot(lateral)
        end
        overlap_start = [0.0, target_positions.min].max
        overlap_end = [source_width, target_positions.max].min
        overlap_length = overlap_end - overlap_start
        return nil if overlap_length < MIN_BRIDGE_OVERLAP_MM.mm

        {
          lateral: lateral,
          start: overlap_start,
          end: overlap_end,
          midpoint: (overlap_start + overlap_end) * 0.5,
          length: overlap_length
        }
      end

      def add_and_extrude_profiles(profiles, distance, target_face, opposite_face = nil)
        entities = entities_for_face(target_face)
        return unless entities

        target_normal = target_face.normal
        front_mat = target_face.material
        back_mat = target_face.back_material

        existing_edge_ids = entities.grep(Sketchup::Edge).each_with_object({}) { |e, h| h[e.persistent_id] = true }

        profiles.each do |points|
          pf = entities.add_face(points)
          next unless pf && pf.valid?

          pf.material = front_mat
          pf.back_material = back_mat
          pf.reverse! if pf.normal.dot(target_normal).negative?
          pf.pushpull(distance)
        end

        # Erase coplanar seam edges
        erase_internal_bridge_faces(entities, profiles, distance, target_normal)
        erase_coplanar_edges(entities)
      end

      def erase_internal_bridge_faces(entities, profiles, distance, normal)
        tolerance = 1.mm
        profile_frames = profiles.filter_map do |points|
          next unless points.length >= 2
          lateral = points[0].vector_to(points[1])
          width = lateral.length
          next if width <= GEOMETRY_TOLERANCE
          lateral.normalize!
          {
            origin: points[0],
            lateral: lateral,
            width: width,
            min_z: points.map(&:z).min,
            max_z: points.map(&:z).max
          }
        end

        internal_faces = entities.grep(Sketchup::Face).select do |face|
          next false unless face.valid?
          next false unless face.normal.parallel?(normal)
          next false unless face.normal.dot(normal).negative?

          profile_frames.any? do |frame|
            face.vertices.all? do |vertex|
              point = vertex.position
              relative = frame[:origin].vector_to(point)
              along = relative.dot(normal)
              across = relative.dot(frame[:lateral])

              (along - distance).abs <= tolerance &&
                across >= -tolerance &&
                across <= frame[:width] + tolerance &&
                point.z >= frame[:min_z] - tolerance &&
                point.z <= frame[:max_z] + tolerance
            end
          end
        end

        entities.erase_entities(internal_faces) unless internal_faces.empty?
      end

      def erase_coplanar_edges(entities)
        edges = entities.grep(Sketchup::Edge).select do |edge|
          next false unless edge.valid?
          next false if edge.soft? || edge.smooth?

          faces = edge.faces
          next false unless faces.length == 2
          faces[0].normal.parallel?(faces[1].normal) &&
            faces[0].vertices.first.position.distance_to_plane(faces[1].plane) < GEOMETRY_TOLERANCE
        end

        entities.erase_entities(edges) unless edges.empty?
      end

      def entities_for_face(face)
        return nil unless face
        parent = face.parent
        return parent if parent.respond_to?(:add_face)
        return parent.entities if parent.respond_to?(:entities)
        nil
      end
    end
  end
end
