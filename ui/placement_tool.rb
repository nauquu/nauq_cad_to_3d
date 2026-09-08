# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Quản lý sự kiện sau khi đặt component CAD bằng lệnh native model.place_component
    module CADPlacementManager
      class CADPlacementObserver < Sketchup::ToolsObserver
        def initialize(definition, file_path, &callback)
          @definition = definition
          @file_path = file_path
          @callback = callback
          @active_count = 0
          @finished = false
        end

        def onActiveToolChanged(tools, _tool_name, _tool_id)
          return if @finished

          @active_count += 1

          # Lần 1: kích hoạt place_component -> bỏ qua
          return if @active_count <= 1

          # Lần 2: kết thúc place_component (đặt xong hoặc bấm ESC)
          @finished = true
          tools.remove_observer(self) rescue nil

          UI.start_timer(0.05, false) do
            model = Sketchup.active_model
            # Tìm instance vừa đặt trong model.entities
            # Root context lookup is intentional (paste target = root model).
            placed_inst = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.definition == @definition } # rubocop:disable SketchupSuggestions/ModelEntities

            if placed_inst && placed_inst.valid?
              DWGReader.ensure_subgroups(model)
              cad_parent = DWGReader.find_or_create_cad_original_group(model)

              # transparent = true (4th arg): observer-initiated model changes
              # must chain onto the user's previous undo step
              # (SketchupRequirements/ObserversStartOperation).
              model.start_operation('NAUQ Đặt Bản Vẽ CAD', true, false, true)
              begin
                t_world = placed_inst.transformation
                t_local = cad_parent.transformation.inverse * t_world
                final_inst = cad_parent.entities.add_instance(@definition, t_local)
                final_inst.name = @definition.name

                Attribute.tag(cad_parent, 'cad_original', file: @file_path, imported_at: Time.now.to_s)
                Attribute.tag(final_inst, 'dwg_import_item', file: @file_path, imported_at: Time.now.to_s)
                Attribute.tag(final_inst, 'dwg_import', name: @definition.name)

                placed_inst.erase!
                model.commit_operation
                model.active_view.invalidate

                # Thoát hoàn toàn chế độ đặt đối tượng, đưa con trỏ về công cụ Select bình thường
                model.select_tool(nil)

                Logger.info("Đã chuyển bản vẽ CAD '#{@definition.name}' vào NAUQ_CAD_ORIGINAL.") if defined?(Logger)

                # Mở BuildDialog ngay lập tức sau khi đặt bản vẽ xuống!
                if @callback
                  UI.start_timer(0.05, false) { @callback.call(final_inst) }
                end
              rescue StandardError => e
                model.abort_operation
                model.select_tool(nil)
                Logger.error("Lỗi khi tổ chức CAD vào thư mục: #{e.message}") if defined?(Logger)
              end
            end
          end
        end
      end

      class << self
        def start(definition, file_path, &on_placed)
          model = Sketchup.active_model
          return unless model && definition && definition.valid?

          tool_obs = CADPlacementObserver.new(definition, file_path, &on_placed)
          model.tools.add_observer(tool_obs)

          UI.start_timer(0.05, false) do
            model.place_component(definition, false)
          end
        end
      end
    end

    # Placeholder for backward compatibility
    class CADPlacementTool
    end
  end
end
