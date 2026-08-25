# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Loads template components (such as DOOR_TEMPLATE.skp)
    module TemplateLoader
      class << self
        # Return path to DOOR_TEMPLATE.skp or nil if not found
        def door_template_path
          file = File.join(File.dirname(__FILE__), 'DOOR_TEMPLATE.skp')
          File.exist?(file) ? file : nil
        end

        # Load or create door template definition
        def load_door_template(model = Sketchup.active_model)
          path = door_template_path
          if path
            model.definitions.load(path)
          else
            Logger.info('Sử dụng bộ dựng cửa procedural tự động (Frame/Leaf/Glass).')
            nil
          end
        end
      end
    end
  end
end
