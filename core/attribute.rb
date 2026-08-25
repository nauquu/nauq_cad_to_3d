# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Manages SketchUp Attribute Dictionaries for created entities
    module Attribute
      DICTIONARY_NAME = 'NAUQ_CAD_TO_3D'

      class << self
        # Set attribute on a SketchUp entity
        # @param entity [Sketchup::Entity]
        # @param key [String, Symbol]
        # @param value [Object]
        # @param dict_name [String] optional custom dictionary name
        def set(entity, key, value, dict_name = DICTIONARY_NAME)
          return unless entity.respond_to?(:set_attribute)

          entity.set_attribute(dict_name.to_s, key.to_s, value)
        end

        # Get attribute from a SketchUp entity
        # @param entity [Sketchup::Entity]
        # @param key [String, Symbol]
        # @param default_value [Object]
        # @param dict_name [String] optional custom dictionary name
        def get(entity, key, default_value = nil, dict_name = DICTIONARY_NAME)
          return default_value unless entity.respond_to?(:get_attribute)

          entity.get_attribute(dict_name.to_s, key.to_s, default_value)
        end

        # Read all key-values in a dictionary as a Hash
        def all(entity, dict_name = DICTIONARY_NAME)
          return {} unless entity.respond_to?(:attribute_dictionary)

          dict = entity.attribute_dictionary(dict_name.to_s)
          return {} unless dict

          hash = {}
          dict.each_pair { |k, v| hash[k] = v }
          hash
        end

        # Tag entity with a type identifier (e.g. 'wall', 'door', 'window', 'opening')
        def tag(entity, type, extra_data = {})
          set(entity, :type, type.to_s)
          extra_data.each { |k, v| set(entity, k, v) }
        end

        # Check if entity is tagged with a specific type
        def tagged_as?(entity, type, dict_name = DICTIONARY_NAME)
          get(entity, :type, nil, dict_name).to_s == type.to_s
        end

        # Search entities within container (model/group/component) matching attribute key/val
        def find_by_attribute(container, key, value, dict_name = DICTIONARY_NAME)
          results = []
          entities = container.respond_to?(:entities) ? container.entities : container
          entities.each do |ent|
            results << ent if get(ent, key, nil, dict_name).to_s == value.to_s
            if ent.respond_to?(:definition)
              results.concat(find_by_attribute(ent.definition, key, value, dict_name))
            elsif ent.respond_to?(:entities)
              results.concat(find_by_attribute(ent, key, value, dict_name))
            end
          end
          results.uniq
        end
      end
    end
  end
end
