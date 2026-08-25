# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Handles plugin logging and accumulates reports for Phase 6
    module Logger
      LOG_LEVELS = %i[debug info warn error].freeze

      class << self
        def log_entries
          @log_entries ||= []
        end

        def clear!
          @log_entries = []
        end

        def info(msg, entity: nil, position: nil)
          add_entry(:info, msg, entity, position)
        end

        def warn(msg, entity: nil, position: nil)
          add_entry(:warn, msg, entity, position)
        end

        def error(msg, entity: nil, position: nil)
          add_entry(:error, msg, entity, position)
        end

        def debug(msg, entity: nil, position: nil)
          add_entry(:debug, msg, entity, position)
        end

        def warnings_and_errors
          log_entries.select { |e| %i[warn error].include?(e[:level]) }
        end

        def errors
          log_entries.select { |e| e[:level] == :error }
        end

        private

        def add_entry(level, message, entity, position)
          entry = {
            id: log_entries.size + 1,
            level: level,
            message: message,
            entity: entity,
            position: position,
            timestamp: Time.now
          }
          log_entries << entry

          prefix = "[NAUQ CAD23D][#{level.to_s.upcase}]"
          puts "#{prefix} #{message}"
        end
      end
    end
  end
end
