# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Quản lý sự kiện sau khi đặt component CAD bằng lệnh native model.place_component
    module CADPlacementManager
      class CADPlacementObserver < Sketchup::ToolsObserver
        CAMERA_TOOL_NAMES = %w[PanTool CameraPanTool OrbitTool CameraOrbitTool ZoomTool CameraZoomTool CameraWalkTool].freeze

        def initialize(manager)
          @manager = manager
        end

        def onActiveToolChanged(tools, tool_name, _tool_id)
          return if @manager.finished?

          # Skip camera navigation tools (Shift+drag pan, orbit, zoom)
          t_name = tool_name.to_s
          return if CAMERA_TOOL_NAMES.include?(t_name) || t_name =~ /pan|orbit|zoom|camera|walk/i

          @manager.on_tool_changed(tools)
        end
      end

      class CADPlacementEntitiesObserver < Sketchup::EntitiesObserver
        def initialize(manager)
          @manager = manager
        end

        def onElementAdded(_entities, entity)
          return if @manager.finished?

          if entity.is_a?(Sketchup::ComponentInstance) && entity.definition == @manager.definition
            @manager.handle_placed_instance(entity)
          end
        end
      end

      class PlacementSession
        attr_reader :definition

        def initialize(definition, file_path, &callback)
          @definition = definition
          @file_path = file_path
          @callback = callback
          @finished = false
          @active_count = 0
          @tool_obs = nil
          @entities_obs = nil
        end

        def finished?
          @finished
        end

        def attach(model)
          @tool_obs = CADPlacementObserver.new(self)
          @entities_obs = CADPlacementEntitiesObserver.new(self)

          model.tools.add_observer(@tool_obs)
          model.entities.add_observer(@entities_obs)
        end

        def detach
          model = Sketchup.active_model
          return unless model

          model.tools.remove_observer(@tool_obs) if @tool_obs rescue nil
          model.entities.remove_observer(@entities_obs) if @entities_obs rescue nil
          @tool_obs = nil
          @entities_obs = nil
        end

        def on_tool_changed(_tools)
          @active_count += 1
          return if @active_count <= 1

          # Tool switched after initial place_component
          UI.start_timer(0.05, false) do
            next if @finished

            model = Sketchup.active_model
            placed_inst = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.definition == @definition }
            if placed_inst && placed_inst.valid?
              handle_placed_instance(placed_inst)
            else
              # User cancelled via ESC or selected another tool
              @finished = true
              detach
              model.select_tool(nil) rescue nil
            end
          end
        end

        def handle_placed_instance(placed_inst)
          return if @finished
          @finished = true

          detach

          UI.start_timer(0.05, false) do
            model = Sketchup.active_model
            return unless placed_inst && placed_inst.valid? && model

            DWGReader.ensure_subgroups(model)

            model.start_operation('NAUQ Đặt Bản Vẽ CAD', true, false, true)
            begin
              # Giữ bản vẽ CAD độc lập tại model.entities, không gom vào một group chung gây ẩn/đè bản vẽ khác
              placed_inst.name = @definition.name
              placed_inst.visible = true if placed_inst.respond_to?(:visible=)
              placed_inst.hidden = false if placed_inst.respond_to?(:hidden=)

              Attribute.tag(placed_inst, 'cad_original', file: @file_path, imported_at: Time.now.to_s)
              Attribute.tag(placed_inst, 'dwg_import_item', file: @file_path, imported_at: Time.now.to_s)
              Attribute.tag(placed_inst, 'dwg_import', name: @definition.name)

              model.commit_operation
              model.active_view.invalidate

              model.select_tool(nil) rescue nil
              Logger.info("Đã đặt bản vẽ CAD '#{@definition.name}' độc lập vào mô hình.") if defined?(Logger)

              if @callback
                UI.start_timer(0.05, false) { @callback.call(placed_inst) }
              end
            rescue StandardError => e
              model.abort_operation
              model.select_tool(nil) rescue nil
              Logger.error("Lỗi khi hoàn tất đặt bản vẽ CAD: #{e.message}") if defined?(Logger)
            end
          end
        end
      end

      class << self
        def start(definition, file_path, &on_placed)
          model = Sketchup.active_model
          return unless model && definition && definition.valid?

          session = PlacementSession.new(definition, file_path, &on_placed)
          session.attach(model)

          UI.start_timer(0.05, false) do
            DWGReader.restore_camera(model) rescue nil
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
