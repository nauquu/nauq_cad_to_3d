# frozen_string_literal: true

require 'json'

module NAUQ
  module CadTo3D
    # Handles loading, creating, and applying materials from JSON or defaults
    module MaterialLoader
      DEFAULT_MATERIALS_DATA = {
        'materials' => {
          'kimloaidengoaithat' => {
            'name' => 'kimloaidengoaithat',
            'color' => [35, 35, 38],
            'alpha' => 1.0
          },
          'kinhh6' => {
            'name' => 'kinhh6',
            'color' => [180, 220, 240],
            'alpha' => 0.45
          }
        }
      }.freeze

      class << self
        # Load materials data from JSON file or default fallback
        # @param file_path [String, nil]
        # @return [Hash]
        def load_json(file_path = nil)
          path = file_path || default_json_path

          if path && File.exist?(path)
            begin
              data = JSON.parse(File.read(path))
              return data if data.is_a?(Hash) && data['materials'].is_a?(Hash)
            rescue StandardError => e
              Logger.warn("Không thể parse materials JSON tại #{path}: #{e.message}") if defined?(Logger)
            end
          end

          DEFAULT_MATERIALS_DATA
        end

        # Prompt user to select a materials JSON file via dialog
        # @return [Hash]
        def prompt_load_json
          if defined?(UI) && UI.respond_to?(:openpanel)
            path = UI.openpanel('Select TT_CAD_TO_3D materials.json', '', 'materials.json')
            return load_json(path) if path && File.exist?(path)
          end
          load_json(nil)
        end

        # Get or create Sketchup::Material based on material key
        # @param model [Sketchup::Model]
        # @param key [String]
        # @param data [Hash, nil]
        # @return [Sketchup::Material]
        def get_material(model, key, data = nil)
          data ||= load_json

          material_data = data.dig('materials', key.to_s)
          material_data ||= DEFAULT_MATERIALS_DATA.dig('materials', key.to_s)

          raise "Không tìm thấy material key '#{key}'." unless material_data

          material_name = material_data['name'].to_s
          raise "Material '#{key}' không có name." if material_name.empty?

          material = model.materials[material_name] || model.materials.add(material_name)

          # Set Color
          if material_data['color'].is_a?(Array) && material_data['color'].length >= 3
            rgb = material_data['color']
            material.color = Sketchup::Color.new(rgb[0].to_i, rgb[1].to_i, rgb[2].to_i)
          end

          # Set Alpha
          if material_data.key?('alpha')
            alpha = material_data['alpha'].to_f
            alpha = 0.0 if alpha < 0.0
            alpha = 1.0 if alpha > 1.0
            material.alpha = alpha
          end

          material
        end

        # Apply material to all faces within a group or directly to an entity
        # @param entity [Sketchup::Group, Sketchup::ComponentInstance, Sketchup::Face]
        # @param material [Sketchup::Material]
        def apply_material(entity, material)
          return unless material && entity && entity.valid?

          if entity.is_a?(Sketchup::Face)
            entity.material = material
            entity.back_material = material
          elsif entity.respond_to?(:entities)
            entity.entities.grep(Sketchup::Face).each do |face|
              face.material = material
              face.back_material = material
            end
          end
        end

        private

        def default_json_path
          # __FILE__ may carry the wrong encoding on Windows; force UTF-8
          # (SketchupSuggestions/FileEncoding workaround).
          lib_file = __FILE__.dup
          lib_file.force_encoding('UTF-8') if lib_file.respond_to?(:force_encoding)
          File.join(File.dirname(lib_file), 'materials.json')
        end
      end
    end
  end
end
