# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Lightweight progress reporting through SketchUp's status bar.
    # Native model.import is synchronous, so its internal progress cannot be
    # updated by Ruby while SketchUp is parsing the DWG.
    module Progress
      class << self
        def start(label)
          update(0, label)
        end

        def update(percent, label)
          value = [[percent.to_i, 0].max, 100].min
          text = "NAUQ CAD TO 3D | #{value}% | #{label}"
          Sketchup.status_text = text if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
          Logger.debug(text) if defined?(Logger) && (value == 0 || value == 100)
        end

        def finish(label = 'Hoàn tất')
          update(100, label)
        end
      end
    end
  end
end
