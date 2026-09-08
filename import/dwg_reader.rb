# frozen_string_literal: true

require 'set'

# DWG import must read the ROOT model context and regroup imported CAD
# geometry into the NAUQ_CAD_ORIGINAL container by design.
# rubocop:disable SketchupSuggestions/ModelEntities, SketchupSuggestions/AddGroup
module NAUQ
  module CadTo3D
    # Handles importing DWG files and managing top-level group architecture
    module DWGReader
      CAD_ORIGINAL_GROUP_NAME = 'NAUQ_CAD_ORIGINAL'
      WALLS_GROUP_NAME = 'NAUQ_WALLS'
      DOORS_GROUP_NAME = 'NAUQ_DOORS'
      WINDOWS_GROUP_NAME = 'NAUQ_WINDOWS'
      SLAB_GROUP_NAME = 'NAUQ_SLAB'

      ALL_CONTAINER_NAMES = [
        CAD_ORIGINAL_GROUP_NAME,
        WALLS_GROUP_NAME,
        DOORS_GROUP_NAME,
        WINDOWS_GROUP_NAME,
        SLAB_GROUP_NAME
      ].freeze

      class << self
        # Import DWG directly into ComponentDefinition and return definition for native model.place_component
        # @param file_path [String] absolute path to .dwg file
        # @return [Sketchup::ComponentDefinition, nil] definition ready for placement
        def import_dwg_for_placement(file_path)
          model = Sketchup.active_model
          return nil unless model && file_path && File.exist?(file_path)

          ext = File.extname(file_path).downcase
          unless ext == '.dwg' || ext == '.dxf'
            Logger.error("Chỉ chấp nhận file định dạng DWG/DXF! Path: #{file_path}")
            return nil
          end

          # Ensure we are at model root level
          model.close_active while model.active_path

          pre_entities = Set.new(model.entities.to_a)

          options = {
            units: 'mm',
            show_summary: false,
            merge_coplanar: false,
            orient_faces: false
          }

          Progress.update(10, "Đang đọc DWG: #{File.basename(file_path)}...") if defined?(Progress)
          success = model.import(file_path, options)
          return nil unless success

          # Collect all entities imported by DWG
          new_entities = model.entities.to_a.reject { |e| pre_entities.include?(e) }.select(&:valid?)
          return nil if new_entities.empty?

          name = File.basename(file_path, '.*')

          # Group all CAD entities
          if new_entities.size == 1 && (new_entities.first.is_a?(Sketchup::Group) || new_entities.first.is_a?(Sketchup::ComponentInstance))
            cad_group = new_entities.first
          else
            cad_group = model.entities.add_group(new_entities)
          end

          # Convert to Component
          comp_inst = cad_group.is_a?(Sketchup::Group) ? cad_group.to_component : cad_group
          definition = comp_inst.definition
          definition.name = "CAD_#{name}"

          # Tìm điểm góc bắt đầu (Begin Point) chính xác tại góc nét layer tường (Wall Layer Corner)
          wall_layer_setting = (Config.get(:wall_layer) || '0-netcat').to_s.strip
          wall_segments = LayerParser.collect_segments_with_transform(comp_inst, wall_layer_setting)

          if wall_segments.empty?
            # Thử các tên layer tường thông dụng khác: 'tuong', 'wall', 'netcat', 'a-wall'
            ['tuong', 'wall', 'netcat', 'a-wall'].each do |alt_lyr|
              wall_segments = LayerParser.collect_segments_with_transform(comp_inst, alt_lyr)
              break if wall_segments.any?
            end
          end

          if wall_segments.any?
            pts = wall_segments.flat_map { |s| [s[:start_pt], s[:end_pt]] }
            min_x = pts.map(&:x).min
            min_y = pts.map(&:y).min
            min_z = pts.map(&:z).min
            ideal_corner = Geom::Point3d.new(min_x, min_y, min_z)
            # Chọn chính xác điểm đỉnh (Vertex) trên nét tường gần góc dưới-trái nhất
            min_pt = pts.min_by { |p| p.distance(ideal_corner) }
          else
            # Fallback nếu không phát hiện nét tường: lấy góc dưới-trái của toàn bộ bản vẽ
            bb = comp_inst.bounds
            min_pt = Geom::Point3d.new(bb.min.x, bb.min.y, bb.min.z)
          end

          # Dời điểm góc nét tường về gốc tọa độ (0,0,0) để chuột neo chuẩn xác vào góc nét tường
          tr = Geom::Transformation.translation(Geom::Vector3d.new(-min_pt.x, -min_pt.y, -min_pt.z))
          definition.entities.transform_entities(tr, definition.entities.to_a)

          # Erase the initial temporary instance
          comp_inst.erase!

          Logger.info("Đã nạp bản vẽ '#{definition.name}' vào ComponentDefinition — chuyển sang chế độ đặt theo chuột.")
          definition
        end

        # Import DWG file into model inside top-level NAUQ_CAD_ORIGINAL
        # @param file_path [String, nil] absolute path to .dwg file
        # @param force_new [Boolean] whether to clear previous CAD entities and force new import
        # @return [Sketchup::Group, nil] NAUQ_CAD_ORIGINAL group
        def import_dwg(file_path = nil, force_new: false)
          model = Sketchup.active_model
          return nil unless model

          file_path ||= select_dwg_file
          return nil if file_path.nil? || !File.exist?(file_path)

          unless file_path.downcase.end_with?('.dwg')
            Logger.error("Chỉ chấp nhận file định dạng DWG! Path: #{file_path}")
            return nil
          end

          # Step 1: Capture pre-import entities
          pre_entities_set = Set.new(model.active_entities)

          # Fast import options (Disable expensive coplanar merging & face orienting on 2D DWG)
          options = {
            units: 'mm',
            show_summary: false,
            merge_coplanar: false,
            orient_faces: false
          }

          # Step 2: Perform native DWG import BEFORE creating groups or operations
          Progress.update(10, "Đang đọc DWG: #{File.basename(file_path)}...") if defined?(Progress)
          success = model.import(file_path, options)

          unless success
            Logger.error("Import DWG thất bại từ file: #{file_path}")
            return nil
          end

          # Step 3: Find newly imported DWG entities
          Progress.update(25, 'Đang gom các đối tượng DWG vừa import...') if defined?(Progress)
          new_entities = model.active_entities.reject { |e| pre_entities_set.include?(e) }

          if new_entities.empty?
            Logger.warn('Không tìm thấy đối tượng nào được import từ file DWG.')
            return nil
          end

          # Step 4: Now wrap architectural group organization in a single operation
          model.start_operation('NAUQ Organize CAD', true)

          begin
            Progress.update(30, 'Đang tổ chức CAD vào NAUQ_CAD_ORIGINAL...') if defined?(Progress)
            unwrap_legacy_root_group(model)
            ensure_subgroups(model)
            cad_group = find_or_create_cad_original_group(model)

            # Move newly imported DWG entities into cad_group
            cad_item = move_entities_into_group(model, new_entities, cad_group, File.basename(file_path, '.*'))

            Attribute.tag(cad_group, 'cad_original', file: file_path, imported_at: Time.now.to_s)
            Attribute.tag(cad_item, 'dwg_import_item', file: file_path, imported_at: Time.now.to_s) if cad_item

            model.commit_operation
            model.active_view.invalidate
            Progress.update(35, 'Đã tổ chức xong CAD gốc.') if defined?(Progress)
            Logger.info("Import thành công CAD gốc vào 'NAUQ_CAD_ORIGINAL': #{File.basename(file_path)}")

            cad_item || cad_group
          rescue StandardError => e
            model.abort_operation
            Logger.error("Lỗi tổ chức thư mục CAD: #{e.message}")
            nil
          end
        end

        # Safely clear group entities while retaining cpoint anchor so SketchUp never purges it
        def clear_group_safely(group)
          return unless group && group.valid?

          group.entities.clear!
          group.entities.add_cpoint(Geom::Point3d.new(0, 0, 0)) # Prevents SketchUp purge
        end

        # Move loose top-level entities into destination group cleanly using component conversion
        def move_entities_into_group(model, entities, destination_group, name = 'DWG_Import')
          return if entities.empty? || destination_group.nil? || !destination_group.valid?

          # Filter out any container groups just in case
          valid_entities = entities.select(&:valid?).reject do |e|
            e == destination_group || ALL_CONTAINER_NAMES.include?(e.name) || Attribute.tagged_as?(e, 'root_architecture')
          end

          return if valid_entities.empty?

          if valid_entities.size == 1 && (valid_entities.first.is_a?(Sketchup::Group) || valid_entities.first.is_a?(Sketchup::ComponentInstance))
            single_ent = valid_entities.first
            comp_inst = single_ent.is_a?(Sketchup::Group) ? single_ent.to_component : single_ent
            comp_def = comp_inst.definition
            comp_def.name = name unless name.empty?

            inst = destination_group.entities.add_instance(comp_def, comp_inst.transformation)
            inst.name = name
            comp_inst.erase!
            Attribute.tag(inst, 'dwg_import', name: name)
            return inst
          end

          temp_grp = model.active_entities.add_group(valid_entities)
          comp_inst = temp_grp.to_component
          comp_def = comp_inst.definition
          comp_def.name = name

          inst = destination_group.entities.add_instance(comp_def, comp_inst.transformation)
          inst.name = name
          comp_inst.erase!

          Attribute.tag(inst, 'dwg_import', name: name)
          inst
        end

        # Safely return cad_group without modifying any existing user models
        def adopt_loose_cad_imports(cad_group = nil)
          model = Sketchup.active_model
          return cad_group unless model

          cad_group = find_or_create_cad_original_group(model) unless cad_group && cad_group.valid?
          cad_group
        end

        # Check if cad_group has any geometry / edges inside it
        def has_cad_geometry?(cad_group)
          return false if cad_group.nil? || !cad_group.valid?

          count_edges(cad_group.entities) > 0
        end

        # Helper to count edges recursively
        def count_edges(entities)
          count = 0
          entities.each do |ent|
            if ent.is_a?(Sketchup::Edge)
              count += 1
            elsif ent.is_a?(Sketchup::Group)
              count += count_edges(ent.entities)
            elsif ent.is_a?(Sketchup::ComponentInstance)
              count += count_edges(ent.definition.entities)
            end
          end
          count
        end

        # Helper to find or create top-level container group in model.entities
        def find_or_create_subgroup(model, name, tag_name)
          group = model.entities.grep(Sketchup::Group).find do |g|
            g.valid? && (g.name == name || Attribute.tagged_as?(g, tag_name))
          end

          unless group && group.valid?
            model.selection.clear rescue nil
            group = model.entities.add_group
            group.name = name
            group.entities.add_cpoint(Geom::Point3d.new(0, 0, 0)) # Prevents SketchUp purge
            Attribute.tag(group, tag_name)
          end

          group
        end

        def find_or_create_cad_original_group(model = Sketchup.active_model)
          find_or_create_subgroup(model, CAD_ORIGINAL_GROUP_NAME, 'cad_original')
        end

        def find_or_create_walls_group(model = Sketchup.active_model)
          find_or_create_subgroup(model, WALLS_GROUP_NAME, 'walls_container')
        end

        def find_or_create_doors_group(model = Sketchup.active_model)
          find_or_create_subgroup(model, DOORS_GROUP_NAME, 'doors_container')
        end

        def find_or_create_windows_group(model = Sketchup.active_model)
          find_or_create_subgroup(model, WINDOWS_GROUP_NAME, 'windows_container')
        end

        def find_or_create_slab_group(model = Sketchup.active_model)
          find_or_create_subgroup(model, SLAB_GROUP_NAME, 'slab_container')
        end

        # Create top-level 4 container groups structure directly in model.entities
        def ensure_subgroups(model = Sketchup.active_model)
          return [] unless model

          unwrap_legacy_root_group(model)

          [
            find_or_create_cad_original_group(model),
            find_or_create_walls_group(model),
            find_or_create_doors_group(model),
            find_or_create_windows_group(model)
          ]
        end

        # Unwrap legacy NAUQ_Architecture parent group if present in model
        def unwrap_legacy_root_group(model = Sketchup.active_model)
          return unless model

          legacy_root = model.entities.grep(Sketchup::Group).find do |g|
            g.valid? && (g.name == 'NAUQ_Architecture' || Attribute.tagged_as?(g, 'root_architecture'))
          end
          return unless legacy_root && legacy_root.valid?

          legacy_root.entities.grep(Sketchup::Group).each do |sub|
            next unless sub.valid?

            # Move subgroup out to model level
            comp_inst = sub.to_component
            inst = model.entities.add_instance(comp_inst.definition, comp_inst.transformation)
            inst.name = sub.name
          end

          legacy_root.erase!
        end

        private

        def select_dwg_file
          return nil unless defined?(UI)

          UI.openpanel('Chọn file CAD DWG (mm)', '', 'Bản vẽ AutoCAD (*.dwg)|*.dwg;*.DWG||')
        end
      end
    end
  end
end
