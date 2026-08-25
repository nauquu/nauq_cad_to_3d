# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Handles finding and retrieving clipboard DWG files copied from AutoCAD (Ctrl+C / COPYCLIP)
    module CADClipboard
      # Default maximum allowed clipboard file age in seconds (30s)
      MAX_CLIPBOARD_AGE_SECONDS = 30.0

      class << self
        # Find the latest temporary DWG/DXF exported by AutoCAD on Ctrl+C (COPYCLIP)
        # @param max_age_seconds [Float] maximum allowed age in seconds (default: 30s)
        # @return [String, nil] path to newest temp CAD file created within max_age_seconds, or nil
        def find_latest_cad_copy(max_age_seconds = MAX_CLIPBOARD_AGE_SECONDS)
          temp_dirs = [
            defined?(Sketchup) && Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : nil,
            ENV['TEMP'],
            ENV['TMP'],
            File.expand_path('~/AppData/Local/Temp')
          ].compact.uniq.select { |d| File.directory?(d) }

          patterns = ['*.dwg', '*.DWG', '*.dxf', '*.DXF']
          all_files = []

          temp_dirs.each do |dir|
            patterns.each do |pat|
              all_files.concat(Dir.glob(File.join(dir, pat)))
            end
          end

          return nil if all_files.empty?

          # Filter out any files that are not readable or deleted
          valid_files = all_files.select do |f|
            File.file?(f) && File.size?(f) rescue false
          end

          return nil if valid_files.empty?

          # Pick the file with newest modification time
          newest_file = valid_files.max_by { |f| File.mtime(f) rescue Time.at(0) }
          return nil unless newest_file

          # Strictly filter only files copied within max_age_seconds (30s - 1 min)
          file_age = Time.now - (File.mtime(newest_file) rescue Time.at(0))
          return nil if file_age > max_age_seconds

          newest_file
        end
      end
    end
  end
end
