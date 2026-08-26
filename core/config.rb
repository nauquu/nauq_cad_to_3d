# frozen_string_literal: true

require 'json'
require 'base64'

module NAUQ
  module CadTo3D
    # Manages user settings, presets and plugin configuration with persistence
    module Config
      # Geometric constants (in mm) - used by geometric algorithms
      MIN_WALL_HEIGHT = 1000.0        # Minimum wall height after beam deduction
      OPENING_SEARCH_MARGIN = 300.0   # Margin for opening-to-wall matching
      EDGE_VALIDATION_TOLERANCE = 100.0  # Max difference between left/right edges for opening validation
      RAYCAST_MAX_DISTANCE = 5000.0   # Maximum raycast distance for opening detection (in mm)
      MIN_GEOMETRY_THRESHOLD = 1.0    # Minimum valid geometry size in mm (e.g., face area, edge length)

      DEFAULT_SETTINGS = {
        # Wall settings
        wall_layer: '0-netcat',
        wall_height: 3000.0, # mm
        wall_tolerance: 5.0, # mm

        # Door settings
        door_layer: '0-cua',
        door_block: 'CUA DI',
        door_height: 2200.0, # mm
        door_max_width: 900.0, # mm

        # Window settings
        window_layer: 'nho',
        window_height: 1200.0, # mm
        window_offset: 900.0,  # mm (bottom offset / sill height)
        window_max_width: 900.0, # mm

        # Global settings
        frame_size: 50.0,     # mm
        glass_height: 350.0,  # mm
        door_grouping: 2,      # 2: separate doors/windows groups, 1: single group, 0: no group
        deduct_beam: false,    # boolean: trừ dầm 400mm và tạo sàn trên
        beam_depth: 400.0      # mm: chiều cao dầm/sàn
      }.freeze

      DEFAULT_PRESETS = {
        'Tiêu chuẩn NAUQ (0-netcat / 0-cua)' => {
          wall_layer: '0-netcat',
          wall_height: 3000.0,
          wall_tolerance: 5.0,
          door_layer: '0-cua',
          door_block: 'CUA DI',
          door_height: 2200.0,
          door_max_width: 900.0,
          window_layer: 'nho',
          window_height: 1200.0,
          window_offset: 900.0,
          window_max_width: 900.0,
          frame_size: 50.0,
          glass_height: 350.0,
          door_grouping: 2,
          deduct_beam: false,
          beam_depth: 400.0
        },
        'Nhà Phố (Trừ Dầm Sàn 400mm)' => {
          wall_layer: '0-netcat',
          wall_height: 3400.0,
          wall_tolerance: 5.0,
          door_layer: '0-cua',
          door_block: 'CUA DI',
          door_height: 2400.0,
          door_max_width: 900.0,
          window_layer: 'nho',
          window_height: 1400.0,
          window_offset: 800.0,
          window_max_width: 900.0,
          frame_size: 50.0,
          glass_height: 400.0,
          door_grouping: 2,
          deduct_beam: true,
          beam_depth: 400.0
        },
        'Chung Cư / Căn Hộ (2.8m)' => {
          wall_layer: '0-netcat',
          wall_height: 2800.0,
          wall_tolerance: 5.0,
          door_layer: '0-cua',
          door_block: 'CUA DI',
          door_height: 2150.0,
          door_max_width: 900.0,
          window_layer: 'nho',
          window_height: 1200.0,
          window_offset: 900.0,
          window_max_width: 900.0,
          frame_size: 45.0,
          glass_height: 0.0,
          door_grouping: 2,
          deduct_beam: false,
          beam_depth: 400.0
        },
        'Bản vẽ Tiếng Anh (WALL / DOOR / WINDOW)' => {
          wall_layer: 'WALL',
          wall_height: 3000.0,
          wall_tolerance: 5.0,
          door_layer: 'DOOR',
          door_block: 'DOOR',
          door_height: 2200.0,
          door_max_width: 900.0,
          window_layer: 'WINDOW',
          window_height: 1200.0,
          window_offset: 900.0,
          window_max_width: 900.0,
          frame_size: 50.0,
          glass_height: 350.0,
          door_grouping: 2,
          deduct_beam: false,
          beam_depth: 400.0
        },
        'Bản vẽ Tiếng Việt (TUONG / CUA / CUASO)' => {
          wall_layer: 'TUONG',
          wall_height: 3000.0,
          wall_tolerance: 5.0,
          door_layer: 'CUA',
          door_block: 'CUA',
          door_height: 2200.0,
          door_max_width: 900.0,
          window_layer: 'CUASO',
          window_height: 1200.0,
          window_offset: 900.0,
          window_max_width: 900.0,
          frame_size: 50.0,
          glass_height: 350.0,
          door_grouping: 2,
          deduct_beam: false,
          beam_depth: 400.0
        }
      }.freeze

      PREF_KEY = 'NAUQ_CAD_TO_3D_Settings'
      PREF_CUSTOM_PRESETS_KEY = 'custom_presets_json_b64'
      PREF_DELETED_PRESETS_KEY = 'deleted_presets_json_b64'
      PREF_ACTIVE_PRESET_KEY = 'active_preset'

      class << self
        # Return current settings hash (combining defaults with saved defaults)
        def settings
          @settings ||= load_settings
        end

        def get(key)
          settings[key.to_sym]
        end

        def set(key, value)
          settings[key.to_sym] = value
          save_settings
        end

        def update(hash)
          hash.each do |k, v|
            settings[k.to_sym] = v
          end
          save_settings
        end

        def reset!
          @settings = DEFAULT_SETTINGS.dup
          save_settings
        end

        # Get all presets (filters out any presets deleted by user)
        def presets
          all_presets = {}
          deleted_names = load_deleted_presets

          DEFAULT_PRESETS.each do |name, vals|
            utf8_name = name.to_s.dup.force_encoding('UTF-8')
            next if deleted_names.include?(utf8_name)

            all_presets[utf8_name] = { data: vals.dup, is_custom: false }
          end

          custom = load_custom_presets
          custom.each do |name, vals|
            utf8_name = name.to_s.dup.force_encoding('UTF-8')
            next if deleted_names.include?(utf8_name)

            all_presets[utf8_name] = { data: vals, is_custom: true }
          end

          if all_presets.empty?
            all_presets['Mặc định'] = { data: DEFAULT_SETTINGS.dup, is_custom: false }
          end

          all_presets
        end

        # Save a new custom preset or update existing preset
        def save_preset(name, data_hash)
          name = name.to_s.dup.force_encoding('UTF-8').strip
          return false if name.empty?

          # If user saves with a name that was previously deleted, un-delete it
          deleted_names = load_deleted_presets
          if deleted_names.include?(name)
            deleted_names.delete(name)
            save_deleted_presets(deleted_names)
          end

          custom = load_custom_presets
          clean_data = {}
          DEFAULT_SETTINGS.each_key do |key|
            val = data_hash[key.to_s] || data_hash[key.to_sym]
            next if val.nil?

            if DEFAULT_SETTINGS[key].is_a?(Float)
              clean_data[key] = val.to_f
            elsif DEFAULT_SETTINGS[key].is_a?(Integer)
              clean_data[key] = val.to_i
            elsif DEFAULT_SETTINGS[key].is_a?(TrueClass) || DEFAULT_SETTINGS[key].is_a?(FalseClass)
              clean_data[key] = (val == 'true' || val == true || val == 1 || val == '1')
            else
              clean_data[key] = val.to_s
            end
          end

          custom[name] = clean_data
          save_custom_presets(custom)
          set_active_preset(name)
          true
        end

        # Delete ANY preset (both default and custom)
        def delete_preset(name)
          name = name.to_s.dup.force_encoding('UTF-8').strip
          return false if name.empty?

          deleted_names = load_deleted_presets
          custom = load_custom_presets

          deleted = false

          # Match keys using UTF-8 normalized strings
          custom_match_key = custom.keys.find { |k| k.to_s.dup.force_encoding('UTF-8') == name }
          if custom_match_key
            custom.delete(custom_match_key)
            save_custom_presets(custom)
            deleted = true
          end

          builtin_match_key = DEFAULT_PRESETS.keys.find { |k| k.to_s.dup.force_encoding('UTF-8') == name }
          if builtin_match_key
            deleted_names << builtin_match_key unless deleted_names.include?(builtin_match_key)
            save_deleted_presets(deleted_names)
            deleted = true
          end

          if deleted
            remaining = presets.keys
            new_active = remaining.first || 'Mặc định'
            set_active_preset(new_active) if active_preset.to_s.dup.force_encoding('UTF-8') == name
            true
          else
            false
          end
        end

        # Restore all built-in default presets
        def restore_default_presets!
          save_deleted_presets([])
          set_active_preset(DEFAULT_PRESETS.keys.first)
        end

        def active_preset
          available = presets.keys
          return 'Mặc định' if available.empty?

          val = Sketchup.read_default(PREF_KEY, PREF_ACTIVE_PRESET_KEY, nil) rescue nil
          if val
            utf8_val = val.to_s.dup.force_encoding('UTF-8')
            available.include?(utf8_val) ? utf8_val : available.first
          else
            available.first
          end
        end

        def set_active_preset(name)
          return unless defined?(Sketchup)

          Sketchup.write_default(PREF_KEY, PREF_ACTIVE_PRESET_KEY, name.to_s.dup.force_encoding('UTF-8'))
        end

        private

        def load_settings
          loaded = DEFAULT_SETTINGS.dup
          DEFAULT_SETTINGS.each_key do |key|
            val = Sketchup.read_default(PREF_KEY, key.to_s, nil) rescue nil
            next if val.nil?

            # Cast types if appropriate
            if DEFAULT_SETTINGS[key].is_a?(Float)
              loaded[key] = val.to_f
            elsif DEFAULT_SETTINGS[key].is_a?(Integer)
              loaded[key] = val.to_i
            elsif DEFAULT_SETTINGS[key].is_a?(TrueClass) || DEFAULT_SETTINGS[key].is_a?(FalseClass)
              loaded[key] = (val == 'true' || val == true || val == 1 || val == '1')
            else
              loaded[key] = val.to_s
            end
          end
          loaded
        end

        def save_settings
          return unless defined?(Sketchup)

          @settings.each do |key, val|
            Sketchup.write_default(PREF_KEY, key.to_s, val.to_s)
          end
        end

        def load_custom_presets
          return {} unless defined?(Sketchup)

          raw = Sketchup.read_default(PREF_KEY, PREF_CUSTOM_PRESETS_KEY, nil) rescue nil
          if raw.nil? || raw.empty?
            # Fallback to check old non-base64 key in registry if any
            raw = Sketchup.read_default(PREF_KEY, 'custom_presets_json', nil) rescue nil
            return {} if raw.nil? || raw.empty?
          end

          parsed = nil
          begin
            if raw.to_s.strip.start_with?('{')
              parsed = JSON.parse(raw)
            else
              parsed = JSON.parse(Base64.decode64(raw))
            end
          rescue
            parsed = {}
          end

          parsed ||= {}
          utf8_hash = {}
          parsed.each do |k, v|
            utf8_hash[k.to_s.dup.force_encoding('UTF-8')] = v
          end
          utf8_hash
        end

        def save_custom_presets(custom_hash)
          return unless defined?(Sketchup)

          encoded = Base64.strict_encode64(custom_hash.to_json)
          Sketchup.write_default(PREF_KEY, PREF_CUSTOM_PRESETS_KEY, encoded)
        end

        def load_deleted_presets
          return [] unless defined?(Sketchup)

          raw = Sketchup.read_default(PREF_KEY, PREF_DELETED_PRESETS_KEY, nil) rescue nil
          if raw.nil? || raw.empty?
            # Fallback to check old non-base64 key in registry if any
            raw = Sketchup.read_default(PREF_KEY, 'deleted_presets_json', nil) rescue nil
            return [] if raw.nil? || raw.empty?
          end

          parsed = nil
          begin
            if raw.to_s.strip.start_with?('[')
              parsed = JSON.parse(raw)
            else
              parsed = JSON.parse(Base64.decode64(raw))
            end
          rescue
            parsed = []
          end

          parsed ||= []
          parsed.map { |name| name.to_s.dup.force_encoding('UTF-8') }
        end

        def save_deleted_presets(deleted_array)
          return unless defined?(Sketchup)

          encoded = Base64.strict_encode64(deleted_array.to_json)
          Sketchup.write_default(PREF_KEY, PREF_DELETED_PRESETS_KEY, encoded)
        end
      end
    end
  end
end
