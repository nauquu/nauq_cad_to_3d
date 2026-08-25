# frozen_string_literal: true

# NAUQ CAD TO 3D - SketchUp Plugin
# Automatic 2D DWG Architectural Drawing to 3D SketchUp Model Converter

require 'sketchup'
require 'extensions'
require 'base64'

module NAUQ
  module CadTo3D
    PLUGIN_ID = 'NAUQ_CAD_TO_3D' unless defined?(PLUGIN_ID)
    PLUGIN_NAME = 'NAUQ CAD to 3D' unless defined?(PLUGIN_NAME)
    PLUGIN_VERSION = '1.9.4' unless defined?(PLUGIN_VERSION)

    # Function to load / reload all internal submodules
    class << self
      def reload!
        root_dir = File.dirname(__FILE__)

        submodules = [
          'core/config.rb',
          'core/logger.rb',
          'core/attribute.rb',
          'core/geometry.rb',
          'core/progress.rb',
          'import/dwg_reader.rb',
          'import/cad_clipboard.rb',
          'import/layer_parser.rb',
          'import/block_parser.rb',
          'wall/wall_detector.rb',
          'wall/wall_cleanup.rb',
          'wall/wall_fill_builder.rb',
          'wall/wall_fill_tool.rb',
          'wall/overlap_edge_cleaner.rb',
          'wall/wall_builder.rb',
          'opening/opening_detector.rb',
          'opening/opening_normalizer.rb',
          'door/door_builder.rb',
          'door/door_generator.rb',
          'door/frame_builder.rb',
          'door/leaf_builder.rb',
          'door/glass_builder.rb',
          'door/opening_door_tool.rb',
          'window/window_builder.rb',
          'stair/railing_builder.rb',
          'stair/stair_builder.rb',
          'library/template_loader.rb',
          'library/material_loader.rb',
          'ui/settings_dialog.rb',
          'ui/build_dialog.rb',
          'ui/stair_dialog.rb',
          'ui/report_dialog.rb',
          'ui/replace_dialog.rb',
          'ui/resize_tool_dialog.rb',
          'ui/placement_tool.rb',
          'ui/manual_door_tool.rb',
          'ui/snapshot_crop_tool.rb'
        ]

        submodules.each do |mod|
          f_path = File.join(root_dir, mod)
          begin
            if File.exist?(f_path)
              load(f_path)
            elsif defined?(Sketchup) && Sketchup.respond_to?(:require)
              Sketchup.require(f_path)
            else
              require_relative(mod)
            end
            # puts "[NAUQ CAD TO 3D] ✓ Loaded: #{mod}"  # Uncomment for debug
          rescue StandardError, ScriptError => e
            error_msg = "[NAUQ CAD TO 3D] ✗ Error loading #{mod}: #{e.message}"
            puts error_msg
            puts "  Location: #{e.backtrace.first}" if e.backtrace && !e.backtrace.empty?
            
            # Log to Logger module if available
            if defined?(Logger) && Logger.respond_to?(:error)
              Logger.error("Module load failed: #{mod}", position: e.backtrace&.first)
            end
            
            # Re-raise if critical core modules fail to load
            raise e if mod.start_with?('core/')
          end
        end

        puts '[NAUQ CAD TO 3D] Đã nạp lại toàn bộ module thành công!'
        true
      end
    end

    # NOTE: reload! is called at the end of this file, after all methods are defined.

    SETTINGS_ICON_SVG = <<~SVG unless defined?(SETTINGS_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#2563eb" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.38a2 2 0 0 0-.73-.22.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/>
        <circle cx="12" cy="12" r="3"/>
      </svg>
    SVG

    IMPORT_DWG_ICON_SVG = <<~SVG unless defined?(IMPORT_DWG_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="24 0 212 212">
        <defs>
          <linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="#FFFFFF"/>
            <stop offset="1" stop-color="#E8F0F7"/>
          </linearGradient>
        </defs>
        <path d="M42 34 Q42 25 51 25 H133 L164 56 V177 Q164 187 154 187 H51 Q42 187 42 177 Z" fill="url(#paper)" stroke="#168FD6" stroke-width="7" stroke-linejoin="round"/>
        <path d="M133 25 V60 H164" fill="#D8EAF8" stroke="#168FD6" stroke-width="7" stroke-linejoin="round"/>
        <g fill="none" stroke="#168FD6" stroke-width="6" stroke-linecap="round">
          <path d="M96 70 V131"/>
          <path d="M65 101 H127"/>
        </g>
        <rect x="84" y="89" width="24" height="24" fill="#FFFFFF" stroke="#14578F" stroke-width="5"/>
        <path d="M101 70 A35 35 0 0 1 132 101" fill="none" stroke="#168FD6" stroke-width="6" stroke-dasharray="8 8" stroke-linecap="round"/>
        <rect x="42" y="143" width="122" height="44" fill="#075A9E"/>
        <text x="103" y="174" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="29" font-weight="700" fill="#FFFFFF">DWG</text>
        <path d="M143 94 H184 V76 L220 110 L184 144 V126 H143 Z" fill="#F3262E" stroke="#FFFFFF" stroke-width="7" stroke-linejoin="round"/>
      </svg>
    SVG

    WALLFILL_ICON_SVG = <<~SVG unless defined?(WALLFILL_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
        <!-- Front-Facing Architectural Portal / Lintel Frame -->
        <g stroke="#222B38" stroke-width="12" stroke-linecap="round" stroke-linejoin="round">
          <!-- Right Pillar Inner Shadow Face -->
          <polygon points="351.3,424.3 314.3,397.4 314.3,130.6 351.3,157.5" fill="#E1E5EC" />

          <!-- Left Pillar Left Shadow Face -->
          <polygon points="126.8,472.0 89.8,445.1 89.8,102.8 126.8,129.7" fill="#DCE0E8" />

          <!-- Left Pillar Front Face -->
          <polygon points="126.8,472.0 197.7,456.9 197.7,114.6 126.8,129.7" fill="#F4F6F9" />

          <!-- Left Pillar Top Face -->
          <polygon points="126.8,129.7 197.7,114.6 160.7,87.7 89.8,102.8" fill="#FFFFFF" />

          <!-- Blue Lintel Beam Front Face -->
          <polygon points="197.7,190.1 351.3,157.5 351.3,82.0 197.7,114.6" fill="#3B82F6" />

          <!-- Blue Lintel Beam Top Face -->
          <polygon points="197.7,114.6 351.3,82.0 314.3,55.1 160.7,87.7" fill="#5B96F8" />

          <!-- Right Pillar Front Face -->
          <polygon points="351.3,424.3 422.2,409.2 422.2,66.9 351.3,82.0" fill="#F4F6F9" />

          <!-- Right Pillar Top Face -->
          <polygon points="351.3,82.0 422.2,66.9 385.2,40.0 314.3,55.1" fill="#FFFFFF" />
        </g>
      </svg>
    SVG

    INSERT_DOOR_ICON_SVG = <<~SVG unless defined?(INSERT_DOOR_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
        <!-- Insert Door into Opening Icon -->
        <g stroke="#1E293B" stroke-width="12" stroke-linecap="round" stroke-linejoin="round">
          <!-- Left Pillar -->
          <polygon points="110,460 70,430 70,110 110,140" fill="#CBD5E1"/>
          <polygon points="110,460 170,440 170,120 110,140" fill="#F1F5F9"/>
          <polygon points="110,140 170,120 130,90 70,110" fill="#FFFFFF"/>
          
          <!-- Lintel Top (White wall finish matching pillars) -->
          <polygon points="170,180 340,125 340,65 170,120" fill="#F1F5F9"/>
          <polygon points="170,120 340,65 300,35 130,90" fill="#FFFFFF"/>
          
          <!-- Right Pillar -->
          <polygon points="340,405 300,375 300,125 340,155" fill="#CBD5E1"/>
          <polygon points="340,405 400,385 400,65 340,85" fill="#F1F5F9"/>
          <polygon points="340,85 400,65 360,35 300,55" fill="#FFFFFF"/>

          <!-- 3D Door Leaf Fitted Inside Opening -->
          <polygon points="170,440 250,470 250,180 170,150" fill="#3B82F6" stroke="#1D4ED8" stroke-width="8"/>
          <polygon points="170,150 250,180 230,170 150,140" fill="#93C5FD" stroke="#1D4ED8" stroke-width="6"/>
          <!-- Glass Panel on Door Leaf -->
          <polygon points="185,400 235,420 235,220 185,200" fill="#BAE6FD" stroke="#0284C7" stroke-width="6"/>
          
          <!-- Door Swing Arc -->
          <path d="M 340 385 A 170 60 0 0 1 250 470" fill="none" stroke="#2563EB" stroke-width="6" stroke-dasharray="10 10"/>
          
          <!-- Plus Badge -->
          <circle cx="410" cy="410" r="60" fill="#10B981" stroke="#065F46" stroke-width="10"/>
          <line x1="410" y1="380" x2="410" y2="440" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round"/>
          <line x1="380" y1="410" x2="440" y2="410" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round"/>
        </g>
      </svg>
    SVG

    DOOR_SETTINGS_ICON_SVG = <<~SVG unless defined?(DOOR_SETTINGS_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
        <defs>
          <linearGradient id="doorFill" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="#F9FBFD"/>
            <stop offset="1" stop-color="#DDE9F5"/>
          </linearGradient>
          <linearGradient id="gearFill" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="#F0F8FF"/>
            <stop offset="1" stop-color="#C9DDF0"/>
          </linearGradient>
        </defs>
        <path d="M42 35 L157 27 L157 215 L42 223 Z" fill="url(#doorFill)" stroke="#168FD6" stroke-width="6" stroke-linejoin="round"/>
        <path d="M42 35 L157 27 L169 36 L54 44 Z" fill="#EEF7FD" stroke="#168FD6" stroke-width="5" stroke-linejoin="round"/>
        <path d="M157 27 L169 36 L169 206 L157 215" fill="#D5E7F6" stroke="#14578F" stroke-width="5" stroke-linejoin="round"/>
        <path d="M69 62 L139 57 L139 119 L69 124 Z" fill="#E5F0FA" stroke="#14578F" stroke-width="4"/>
        <path d="M69 143 L139 138 L139 196 L69 201 Z" fill="#E8F2FA" stroke="#7A99B6" stroke-width="4"/>
        <circle cx="83" cy="133" r="7" fill="#14578F"/>
        <path d="M83 133 H103" stroke="#14578F" stroke-width="5" stroke-linecap="round"/>
        <g stroke="#FFFFFF" stroke-width="3">
          <circle cx="42" cy="35" r="8" fill="#F3262E"/>
          <circle cx="157" cy="27" r="8" fill="#F3262E"/>
          <circle cx="42" cy="223" r="7" fill="#14578F"/>
        </g>
        <path d="M161.3,102.9 L164.8,88.3 L177.2,88.3 L180.7,102.9 L188.1,104.9 L198.5,94.0 L209.2,100.2 L205.0,114.6 L210.4,120.0 L224.8,115.8 L231.0,126.5 L220.1,136.9 L222.1,144.3 L236.7,147.8 L236.7,160.2 L222.1,163.7 L220.1,171.1 L231.0,181.5 L224.8,192.2 L210.4,188.0 L205.0,193.4 L209.2,207.8 L198.5,214.0 L188.1,203.1 L180.7,205.1 L177.2,219.7 L164.8,219.7 L161.3,205.1 L153.9,203.1 L143.5,214.0 L132.8,207.8 L137.0,193.4 L131.6,188.0 L117.2,192.2 L111.0,181.5 L121.9,171.1 L119.9,163.7 L105.3,160.2 L105.3,147.8 L119.9,144.3 L121.9,136.9 L111.0,126.5 L117.2,115.8 L131.6,120.0 L137.0,114.6 L132.8,100.2 L143.5,94.0 L153.9,104.9 Z" fill="url(#gearFill)" stroke="#168FD6" stroke-width="6" stroke-linejoin="round"/>
        <circle cx="171" cy="154" r="27" fill="#FFFFFF" stroke="#14578F" stroke-width="6"/>
      </svg>
    SVG

    HIDE_OVERLAP_ICON_SVG = <<~SVG unless defined?(HIDE_OVERLAP_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
        <!-- NAUQ Hide Overlap Edge Icon (SketchUp Blue Outline & Palette) -->
        <defs>
          <linearGradient id="suWallFront" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#FFFFFF"/>
            <stop offset="100%" stop-color="#E8EEF5"/>
          </linearGradient>
          <linearGradient id="suWallSide" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#DCE0E8"/>
            <stop offset="100%" stop-color="#C2CAD6"/>
          </linearGradient>
          <linearGradient id="suWallTop" x1="0" y1="1" x2="0" y2="0">
            <stop offset="0%" stop-color="#F4F6F9"/>
            <stop offset="100%" stop-color="#FFFFFF"/>
          </linearGradient>
        </defs>

        <g stroke="#14578F" stroke-width="12" stroke-linecap="round" stroke-linejoin="round">
          <!-- 1. Left Side Face (Wall Thickness - Shadow) -->
          <polygon points="86,398 146,443 146,203 86,158" fill="url(#suWallSide)"/>

          <!-- 2. Front Face (Smooth Front Surface - SketchUp White/Light Blue) -->
          <polygon points="146,443 426,353 426,113 146,203" fill="url(#suWallFront)"/>

          <!-- 3. Top Face (Top Surface - SketchUp Pure White) -->
          <polygon points="146,203 426,113 366,68 86,158" fill="url(#suWallTop)"/>

          <!-- 4. Crisp Outer Border Profile in SketchUp Blue (#14578F) -->
          <line x1="86" y1="398" x2="146" y2="443"/>
          <line x1="146" y1="443" x2="426" y2="353"/>
          <line x1="86" y1="398" x2="86" y2="158"/>
          <line x1="86" y1="158" x2="366" y2="68"/>
          <line x1="366" y1="68" x2="426" y2="113"/>
          <line x1="426" y1="113" x2="426" y2="353"/>
          <line x1="146" y1="203" x2="426" y2="113"/>
          <line x1="146" y1="443" x2="146" y2="203"/>
          <line x1="86" y1="158" x2="146" y2="203"/>

          <!-- 5. BOLD DASHED SEAM LINE (SketchUp Red Accent: #F3262E) -->
          <!-- Front Face Dashed Seam -->
          <line x1="286" y1="172" x2="286" y2="384" stroke="#F3262E" stroke-width="16" stroke-dasharray="22 30" stroke-linecap="round"/>
          <!-- Top Face Dashed Seam -->
          <line x1="278" y1="152" x2="234" y2="119" stroke="#F3262E" stroke-width="16" stroke-dasharray="16 24" stroke-linecap="round"/>
        </g>
      </svg>
    SVG

    RESIZE_DOOR_ICON_SVG = <<~SVG unless defined?(RESIZE_DOOR_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="55 24 140 195"><g fill="#DDEAF7" stroke="#14578F" stroke-width="1.8" stroke-linejoin="round"><path d="M 64.51,206.80 65.33,207.62 78.39,207.62 78.80,205.37 65.33,205.17 Z" fill-rule="evenodd"/><path d="M 71.66,190.88 70.84,191.69 70.63,193.94 67.37,193.94 66.76,194.76 70.63,201.90 70.84,201.49 71.66,202.51 72.47,202.51 76.15,197.41 75.74,197.21 77.37,194.14 73.29,193.74 74.11,193.53 73.08,191.49 Z" fill-rule="evenodd"/><path d="M 71.66,183.53 71.04,184.14 71.04,189.24 72.27,189.86 73.49,188.43 73.29,189.24 73.08,184.34 Z" fill-rule="evenodd"/><path d="M 72.47,173.12 71.04,173.93 71.45,180.06 72.88,179.85 73.08,179.24 73.29,179.65 73.08,174.34 72.06,173.32 Z" fill-rule="evenodd"/><path d="M 72.06,162.70 71.04,163.32 71.04,169.03 71.66,169.65 73.08,168.83 73.08,163.73 Z" fill-rule="evenodd"/><path d="M 71.66,152.09 71.04,152.70 71.04,158.42 72.27,159.03 73.08,158.21 73.08,152.91 Z" fill-rule="evenodd"/><path d="M 166.58,149.23 165.15,148.82 113.30,156.78 112.69,157.40 112.69,200.68 115.96,200.88 166.18,191.69 166.79,190.88 Z M 164.95,151.07 164.75,188.22 164.54,151.89 162.91,151.27 Z" fill-rule="evenodd"/><path d="M 108.40,150.66 111.06,153.52 115.14,153.31 114.73,153.52 117.38,150.05 129.43,148.21 130.25,146.37 129.63,145.56 128.20,145.35 118.61,146.78 117.38,146.58 118.00,146.37 117.38,146.37 115.55,144.13 112.08,143.52 108.40,146.37 Z M 114.12,145.76 115.14,146.78 112.28,148.01 112.28,149.64 113.30,150.46 112.69,150.86 113.71,151.07 112.28,151.27 110.44,149.03 110.65,147.39 112.28,145.76 Z" fill-rule="evenodd"/><path d="M 71.66,141.07 71.04,141.88 71.04,147.60 72.47,148.21 73.08,147.60 73.29,141.88 Z" fill-rule="evenodd"/><path d="M 71.66,130.65 71.04,131.27 71.04,136.78 72.27,137.59 73.08,136.78 73.29,131.27 73.49,132.08 73.29,131.06 Z" fill-rule="evenodd"/><path d="M 71.66,119.63 71.04,120.24 71.04,125.96 72.47,126.57 73.08,125.75 73.08,120.45 Z" fill-rule="evenodd"/><path d="M 72.27,108.61 71.04,109.42 71.04,114.93 72.68,115.75 71.66,115.96 72.06,116.16 73.08,114.93 73.08,109.42 Z" fill-rule="evenodd"/><path d="M 72.47,97.99 71.04,98.60 71.04,104.11 72.06,104.93 73.08,104.11 73.08,98.60 Z" fill-rule="evenodd"/><path d="M 71.66,87.17 71.04,87.78 71.04,93.30 72.27,94.11 73.08,93.30 73.08,87.99 Z" fill-rule="evenodd"/><path d="M 166.18,68.19 115.14,73.90 112.89,74.92 113.10,139.84 137.39,136.98 166.58,132.49 166.79,68.80 Z" fill-rule="evenodd"/><path d="M 71.86,63.69 69.21,67.57 69.00,67.16 66.96,72.06 70.84,72.68 70.84,75.53 71.45,76.35 71.04,82.68 72.68,83.50 73.49,81.86 73.29,82.88 73.08,77.78 72.47,76.96 73.29,75.53 73.49,72.47 76.76,72.47 77.58,71.66 73.49,64.71 Z" fill-rule="evenodd"/><path d="M 65.12,60.84 78.39,60.84 78.80,58.79 65.74,58.39 64.51,59.20 Z" fill-rule="evenodd"/><path d="M 169.65,51.24 167.40,51.04 168.22,51.24 161.07,52.06 160.66,51.65 160.05,51.85 160.87,52.06 154.33,52.47 155.15,52.67 141.88,54.30 138.82,54.10 140.04,54.30 113.71,57.37 106.36,57.57 107.99,57.77 96.36,59.00 94.32,60.22 93.91,209.05 96.15,210.88 95.95,211.29 96.97,211.29 98.19,212.11 97.79,212.52 98.60,212.31 101.87,214.35 128.82,209.05 130.86,209.25 131.88,208.43 146.17,205.58 147.19,205.78 146.78,205.98 148.21,205.17 152.50,204.76 152.09,204.56 156.38,203.53 157.19,203.94 158.42,203.13 165.15,202.31 164.34,202.11 167.60,201.29 169.03,201.49 168.42,201.29 172.71,200.27 173.73,200.68 177.20,198.63 177.20,56.55 176.38,55.12 175.97,55.53 174.55,54.51 174.75,54.10 173.73,54.10 173.73,53.08 172.91,53.49 Z M 174.55,58.39 174.55,197.41 103.71,211.29 104.52,66.35 104.73,68.80 105.34,66.14 Z" fill-rule="evenodd"/><path d="M 116.16,43.48 114.93,42.26 109.22,42.67 108.61,44.10 109.22,44.71 115.34,44.30 115.96,42.87 Z" fill-rule="evenodd"/><path d="M 118.81,43.69 125.14,43.89 125.96,42.26 119.43,42.05 Z" fill-rule="evenodd"/><path d="M 135.96,42.05 135.35,41.24 129.43,41.44 128.82,42.87 131.06,43.89 135.35,43.28 Z" fill-rule="evenodd"/><path d="M 145.76,41.24 145.15,40.63 139.64,40.83 138.82,42.26 145.15,42.67 Z" fill-rule="evenodd"/><path d="M 155.56,40.42 149.44,40.22 148.62,41.44 149.44,42.46 154.33,42.26 155.56,41.65 Z" fill-rule="evenodd"/><path d="M 158.62,40.42 159.23,41.85 164.54,41.65 165.36,41.03 164.75,39.40 159.44,39.60 Z" fill-rule="evenodd"/><path d="M 88.80,43.89 89.01,45.12 93.91,47.97 93.91,48.59 96.97,49.40 97.58,48.79 97.79,45.32 97.99,46.55 98.40,45.32 104.93,45.12 105.54,44.50 105.54,43.48 104.73,42.67 100.44,43.28 97.99,42.05 98.40,42.67 97.58,42.67 97.58,39.40 96.77,38.58 92.07,41.03 92.07,41.65 Z" fill-rule="evenodd"/><path d="M 84.93,35.52 83.90,35.52 83.29,36.34 83.29,51.85 85.74,51.65 85.74,36.54 Z" fill-rule="evenodd"/><path d="M 172.30,34.50 171.69,38.79 168.63,39.20 168.22,40.63 168.83,41.24 171.07,41.24 171.48,42.05 171.69,41.24 171.89,44.71 173.12,45.12 176.38,42.67 178.42,42.05 177.81,41.85 180.47,39.40 174.75,35.11 Z" fill-rule="evenodd"/><path d="M 184.34,30.62 183.12,31.64 183.12,44.50 185.57,44.50 185.57,31.64 Z" fill-rule="evenodd"/></g><g fill="#14578F" stroke="#14578F" stroke-width="2" stroke-linejoin="round"><path d="M 64.71,205.98 64.71,206.80 65.33,207.41 78.39,207.41 78.39,205.37 65.33,205.37 Z" fill-rule="evenodd"/><path d="M 72.47,191.08 71.66,191.08 71.04,191.69 70.84,194.14 67.37,194.14 66.96,194.55 67.16,195.37 71.25,201.90 72.06,202.51 72.88,201.90 77.17,194.76 76.96,194.35 73.08,193.94 73.08,191.69 Z" fill-rule="evenodd"/><path d="M 71.66,183.73 71.25,184.14 71.25,189.24 71.66,189.65 72.27,189.65 72.88,189.04 72.88,184.14 72.47,183.73 Z" fill-rule="evenodd"/><path d="M 71.45,173.73 71.25,179.44 71.66,179.85 72.47,179.85 72.88,179.44 72.88,174.14 72.27,173.52 Z" fill-rule="evenodd"/><path d="M 72.06,162.91 71.25,163.52 71.25,169.03 71.66,169.44 72.47,169.44 72.88,169.03 72.88,163.52 Z" fill-rule="evenodd"/><path d="M 71.66,152.29 71.25,152.70 71.25,158.42 71.66,158.83 72.47,158.83 72.88,158.42 72.68,152.50 Z" fill-rule="evenodd"/><path d="M 166.58,149.64 165.97,149.03 120.85,155.97 113.91,156.78 113.10,157.19 112.69,200.06 113.10,200.88 114.73,200.88 116.98,200.27 123.92,199.25 144.13,195.57 145.15,195.16 165.36,191.69 166.38,191.29 Z M 165.15,150.86 164.95,190.26 114.53,199.45 114.12,199.04 114.53,158.21 148.01,153.31 158.62,151.48 160.05,151.48 163.93,150.66 Z" fill-rule="evenodd"/><path d="M 108.61,149.84 110.04,152.29 111.46,153.11 113.71,153.31 115.55,152.50 116.57,151.48 117.59,149.64 129.43,148.01 130.04,147.19 130.04,146.37 129.22,145.56 128.00,145.56 117.59,146.99 115.96,144.54 114.93,143.92 112.89,143.52 110.65,144.33 109.42,145.56 108.61,147.39 Z M 112.28,145.56 114.12,145.56 115.14,146.37 115.14,147.19 113.30,147.39 112.48,148.01 112.28,148.62 112.48,149.64 112.89,150.05 114.93,150.46 113.51,151.48 111.87,151.27 110.65,150.05 110.24,148.82 110.85,146.78 Z" fill-rule="evenodd"/><path d="M 71.86,141.47 71.25,142.09 71.25,147.60 71.66,148.01 72.47,148.01 72.88,147.60 72.88,142.09 72.68,141.68 Z" fill-rule="evenodd"/><path d="M 71.86,130.65 71.25,131.27 71.45,137.19 72.27,137.39 72.68,137.19 72.88,131.27 72.27,130.65 Z" fill-rule="evenodd"/><path d="M 72.47,119.83 71.66,119.83 71.25,120.24 71.25,125.96 72.06,126.57 72.88,125.96 72.88,120.24 Z" fill-rule="evenodd"/><path d="M 71.86,108.81 71.25,109.42 71.25,114.93 71.86,115.55 72.68,115.34 72.88,109.42 72.68,109.01 Z" fill-rule="evenodd"/><path d="M 71.86,97.99 71.25,98.60 71.25,104.11 71.45,104.52 72.27,104.73 72.88,104.11 72.88,98.60 72.27,97.99 Z" fill-rule="evenodd"/><path d="M 71.66,87.37 71.25,87.78 71.25,93.30 71.45,93.70 72.47,93.91 72.88,93.50 72.88,87.78 72.47,87.37 Z" fill-rule="evenodd"/><path d="M 71.86,77.17 71.25,77.78 71.25,82.68 71.66,83.09 72.47,83.09 72.88,82.68 72.68,77.37 Z" fill-rule="evenodd"/><path d="M 166.18,68.39 113.71,74.31 113.10,74.92 112.89,139.23 113.51,139.84 166.18,132.70 166.58,132.29 166.79,69.00 Z M 165.15,70.23 164.95,131.27 121.26,137.19 116.98,138.00 114.53,138.00 114.53,76.15 114.93,75.74 122.28,75.13 162.91,70.23 Z" fill-rule="evenodd"/><path d="M 71.45,64.10 66.96,71.86 67.37,72.27 71.04,72.47 71.04,75.53 71.66,76.35 72.47,76.35 73.08,75.74 73.29,72.27 76.76,72.27 77.17,71.45 72.47,63.90 Z" fill-rule="evenodd"/><path d="M 64.71,59.20 64.71,60.22 65.12,60.63 78.39,60.63 78.39,58.59 65.33,58.59 Z" fill-rule="evenodd"/><path d="M 169.65,51.44 167.40,51.44 101.87,58.79 95.74,59.20 95.13,59.41 94.52,60.22 93.91,208.64 94.93,210.07 101.67,214.15 103.30,214.15 135.15,207.62 175.97,199.66 177.00,198.63 177.00,56.55 176.59,55.94 Z M 97.17,62.88 101.87,66.14 101.67,179.04 101.26,211.29 96.15,208.03 96.56,63.90 Z M 174.95,58.59 174.95,182.30 174.55,197.61 104.32,211.70 103.50,211.50 103.91,84.11 104.32,66.14 133.51,63.08 172.91,58.39 Z M 172.71,56.14 168.01,56.96 164.34,57.16 159.23,57.98 104.52,64.10 102.89,64.10 98.81,61.24 168.83,53.49 Z" fill-rule="evenodd"/><path d="M 115.55,43.89 115.34,42.67 114.93,42.46 109.63,42.67 108.81,43.28 108.81,44.10 109.63,44.71 115.14,44.30 Z" fill-rule="evenodd"/><path d="M 125.75,42.87 124.94,41.85 119.43,42.26 119.02,42.67 119.22,43.89 119.63,44.10 125.14,43.69 Z" fill-rule="evenodd"/><path d="M 129.02,42.05 129.22,43.28 129.63,43.48 134.74,43.28 135.35,43.07 135.76,42.26 135.35,41.44 130.86,41.44 129.43,41.65 Z" fill-rule="evenodd"/><path d="M 139.02,41.44 139.23,42.67 139.64,42.87 144.74,42.67 145.56,42.05 145.56,41.24 145.15,40.83 139.43,41.03 Z" fill-rule="evenodd"/><path d="M 148.82,41.03 148.82,41.65 149.44,42.26 154.95,42.05 155.56,41.44 155.36,40.42 151.48,40.22 149.44,40.42 Z" fill-rule="evenodd"/><path d="M 158.83,40.42 158.83,41.24 159.23,41.65 164.75,41.44 165.36,40.83 165.15,39.81 159.44,39.81 Z" fill-rule="evenodd"/><path d="M 88.80,44.50 89.62,45.32 96.77,49.40 97.38,48.79 97.58,45.12 104.93,44.91 105.34,44.50 105.34,43.48 104.93,43.07 100.24,43.28 97.38,42.87 97.38,39.40 97.17,38.99 96.36,38.79 89.42,43.48 Z" fill-rule="evenodd"/><path d="M 84.52,35.52 83.50,36.13 83.50,51.65 85.54,51.65 85.54,36.34 Z" fill-rule="evenodd"/><path d="M 173.12,34.70 172.30,34.70 171.89,35.11 171.69,38.99 168.83,39.20 168.42,39.60 168.42,40.83 169.03,41.24 171.89,41.24 171.89,44.50 172.71,45.12 180.06,40.01 179.85,38.79 Z" fill-rule="evenodd"/><path d="M 184.34,30.83 183.32,31.44 183.32,44.30 185.37,44.30 185.37,31.64 Z" fill-rule="evenodd"/></g><g fill="#F3262E" stroke="#FFFFFF" stroke-width="2.5"><path d="M 81.66,203.13 81.05,203.94 81.25,210.68 81.86,211.29 88.60,211.09 89.01,210.68 88.80,203.33 87.99,202.92 Z" fill-rule="evenodd"/><path d="M 81.86,54.51 81.05,55.73 81.25,62.26 82.07,62.88 88.80,62.67 89.21,62.06 89.21,55.12 88.60,54.51 Z" fill-rule="evenodd"/><path d="M 181.28,47.16 180.67,47.97 180.87,54.71 181.49,55.12 187.81,55.12 188.63,54.10 188.43,47.57 187.61,46.95 Z" fill-rule="evenodd"/></g></svg>
    SVG

    STAIR_ICON_SVG = <<~SVG unless defined?(STAIR_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
        <defs>
          <linearGradient id="stairTread" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color="#3B82F6" />
            <stop offset="100%" stop-color="#1D4ED8" />
          </linearGradient>
          <linearGradient id="stairLanding" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color="#60A5FA" />
            <stop offset="100%" stop-color="#2563EB" />
          </linearGradient>
          <linearGradient id="stairRiser" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stop-color="#FFFFFF" />
            <stop offset="100%" stop-color="#F1F5F9" />
          </linearGradient>
          <linearGradient id="stairSide" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color="#CBD5E1" />
            <stop offset="100%" stop-color="#94A3B8" />
          </linearGradient>
        </defs>
        <g stroke="#1E293B" stroke-width="14" stroke-linecap="round" stroke-linejoin="round">
          <polygon points="210,440 450,260 450,35 370,95 370,170 290,230 290,305 210,365" fill="url(#stairSide)" />
          <polygon points="70,440 210,440 210,365 70,365" fill="url(#stairRiser)" />
          <polygon points="70,365 210,365 290,305 150,305" fill="url(#stairTread)" />
          <polygon points="150,305 290,305 290,230 150,230" fill="url(#stairRiser)" />
          <polygon points="150,230 290,230 370,170 230,170" fill="url(#stairTread)" />
          <polygon points="230,170 370,170 370,95 230,95" fill="url(#stairRiser)" />
          <polygon points="230,95 370,95 450,35 310,35" fill="url(#stairLanding)" />
          <line x1="72" y1="365" x2="208" y2="365" stroke="#93C5FD" stroke-width="5" />
          <line x1="152" y1="305" x2="288" y2="305" stroke="#93C5FD" stroke-width="5" />
          <line x1="232" y1="170" x2="368" y2="170" stroke="#BFDBFE" stroke-width="5" />
        </g>
      </svg>
    SVG

    SNAPSHOT_ICON_SVG = <<~SVG unless defined?(SNAPSHOT_ICON_SVG)
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
        <defs>
          <linearGradient id="camBody" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stop-color="#FFFFFF" />
            <stop offset="100%" stop-color="#E2E8F0" />
          </linearGradient>
          <linearGradient id="camLens" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color="#3B82F6" />
            <stop offset="100%" stop-color="#0E3D6B" />
          </linearGradient>
          <linearGradient id="camRed" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stop-color="#EA4335" />
            <stop offset="100%" stop-color="#C5221F" />
          </linearGradient>
        </defs>
        <rect x="76" y="160" width="360" height="250" rx="36" fill="url(#camBody)" stroke="#0E3D6B" stroke-width="24" />
        <path d="M 176,160 L 206,105 L 306,105 L 336,160 Z" fill="#D2D7DF" stroke="#0E3D6B" stroke-width="24" stroke-linejoin="round" />
        <rect x="110" y="125" width="50" height="35" rx="8" fill="url(#camRed)" stroke="#0E3D6B" stroke-width="16" />
        <circle cx="256" cy="285" r="75" fill="#CBD5E1" stroke="#0E3D6B" stroke-width="20" />
        <circle cx="256" cy="285" r="50" fill="url(#camLens)" stroke="#0E3D6B" stroke-width="14" />
        <circle cx="240" cy="268" r="14" fill="#FFFFFF" opacity="0.8" />
        <circle cx="268" cy="298" r="6" fill="#FFFFFF" opacity="0.6" />
        <circle cx="375" cy="205" r="14" fill="#FDE047" stroke="#0E3D6B" stroke-width="10" />
      </svg>
    SVG

    class << self
      # Option 1: Browse and import DWG/DXF file
      def run_pipeline_from_file(file_path = nil)
        unless file_path && File.exist?(file_path)
          last_dir = Config.get(:last_cad_dir).to_s
          last_dir = '' unless File.directory?(last_dir)
          file_path = ::UI.openpanel('Chọn file CAD DWG', last_dir, 'AutoCAD Files|*.dwg;*.DWG;*.dxf;*.DXF|All Files (*.*)|*.*||')
        end

        return unless file_path && File.exist?(file_path)

        run_pipeline(file_path)
      end

      # Main Execution Flow (Section 3 of SPEC)
      def run_pipeline(file_path = nil)
        unless file_path && File.exist?(file_path)
          paste_from_cad
          return
        end

        Logger.clear!
        Progress.start('Chuẩn bị import DWG...')
        Logger.info("--- Bắt đầu quy trình NAUQ CAD TO 3D v#{PLUGIN_VERSION} ---")

        if file_path && File.exist?(file_path) && (file_path.downcase.end_with?('.dwg') || file_path.downcase.end_with?('.dxf'))
          Config.set(:last_cad_dir, File.dirname(file_path)) rescue nil
          Progress.update(10, 'Đang nạp dữ liệu DWG...')
          definition = DWGReader.import_dwg_for_placement(file_path)

          if definition && definition.valid?
            Progress.finish('Rê chuột chọn vị trí đặt bản vẽ')
            CADPlacementManager.start(definition, file_path) do |placed_cad|
              BuildDialog.show do
                execute_3d_building(placed_cad)
              end
            end
            Logger.info("Bản vẽ CAD '#{definition.name}' đã dính vào chuột — Click để đặt xuống mô hình.")
            return
          end
        end

        # If user cancelled file picker, check for existing CAD in model
        cad_group = DWGReader.find_or_create_cad_original_group(Sketchup.active_model)
        cad_group = DWGReader.adopt_loose_cad_imports(cad_group)

        if cad_group && DWGReader.has_cad_geometry?(cad_group)
          Progress.finish('Đã nhận CAD')
          Logger.info("Sử dụng bản vẽ CAD hiện có trong model ('#{DWGReader::CAD_ORIGINAL_GROUP_NAME}').")
          BuildDialog.show do
            execute_3d_building(cad_group)
          end
        else
          Progress.finish('Hủy thao tác')
          Logger.info('Đã hủy chọn file CAD DWG.')
        end
      end

      # Step 3: Execute 3D Building after user confirms dimensions in BuildDialog
      def execute_3d_building(cad_group)
        return unless cad_group && cad_group.valid?

        Sketchup.active_model.select_tool(nil) rescue nil
        Sketchup.active_model.selection.clear rescue nil
        Progress.start('Đang chuẩn bị dựng 3D...')
        settings = Config.settings
        win_h = settings[:window_height] || [settings[:door_height] - settings[:window_offset], 200.0].max
        Logger.info("Bắt đầu dựng 3D với thông số (Chiều cao tường: #{settings[:wall_height]}mm, Cote trên cửa: #{settings[:door_height]}mm, Cote bậu cửa sổ: #{settings[:window_offset]}mm, Chiều cao cửa sổ: #{win_h}mm)")

        # Parse Layers & Blocks for validation
        wall_layer = settings[:wall_layer]
        Progress.update(10, 'Đang quét layer tường...')
        wall_edges = LayerParser.collect_edges_by_layer(cad_group, wall_layer)
        Logger.info("Quét layer tường '#{wall_layer}': tìm thấy #{wall_edges.size} đường nét trong CAD gốc.")

        Progress.update(20, 'Đang quét block cửa...')
        door_blocks = BlockParser.collect_blocks(cad_group, settings[:door_block], settings[:door_layer])
        Logger.info("Quét layer cửa '#{settings[:door_layer]}': tìm thấy #{door_blocks.size} block cửa.")

        # Phase 2 - Detect openings before preparing wall reference geometry.
        Progress.update(30, 'Đang nhận diện cửa đi và cửa sổ...')
        Logger.info('--- Phase 2: Opening Detector ---')
        raw_openings = OpeningDetector.detect_all_openings(cad_group)

        # Phase 3 - Prepare reference faces without creating a wall solid.
        Progress.update(45, 'Đang chuẩn bị hình tham chiếu tường...')
        Logger.info('--- Phase 3: Wall reference (no solid wall) ---')
        walls_group = WallBuilder.build_wall_reference(cad_group)

        if walls_group
          Logger.info('Wall reference prepared successfully.')

          # Phase 4 - Normalize openings against the reference geometry.
          Progress.update(55, 'Đang chuẩn hóa vị trí opening...')
          normalized_openings = OpeningNormalizer.normalize_all(raw_openings, walls_group, cad_group)

          # Phase 5 - Build final wall geometry from Wall Face 2D source of truth.
          Progress.update(65, 'Đang dựng tường 3D từ Wall Face 2D...')
          Logger.info('--- Phase 5: Wall Face 2D → assign openings → WallFillBuilder → extrude ---')
          WallBuilder.build_walls(cad_group, walls_group, normalized_openings)
          Logger.info('Base wall + WallFill geometry created from Wall Face 2D source of truth.')

          # Phase 6 - Build 3D Door and Window Components
          Progress.update(80, 'Đang dựng chi tiết Cửa đi và Cửa sổ 3D...')
          Logger.info('--- Phase 6: Door & Window 3D Builders ---')
          DoorBuilder.build_doors(normalized_openings, nil, cad_group) if defined?(DoorBuilder)
          WindowBuilder.build_windows(normalized_openings, nil, cad_group) if defined?(WindowBuilder)
        else
          puts '[NAUQ ERROR] Wall reference preparation returned nil!'
          Logger.error('--- Wall reference preparation failed. ---')
        end

        # Show Error Report ONLY if actual critical errors occurred
        if Logger.errors.any?
          ReportDialog.show
        end

        Progress.finish('Dựng 3D hoàn tất')
      end

      # Find existing NAUQ_CAD_ORIGINAL group in model
      def find_existing_cad_group
        model = Sketchup.active_model
        return nil unless model

        DWGReader.find_or_create_cad_original_group(model)
      end

      # Write embedded SVG icons to temp directory and return paths
      def load_embedded_icons
        temp_dir = defined?(Sketchup) && Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : (ENV['TEMP'] || '/tmp')

        settings_svg      = File.join(temp_dir, 'nauq_cad_to_3d_settings.svg').tr('\\', '/')
        import_svg        = File.join(temp_dir, 'nauq_cad_to_3d_import.svg').tr('\\', '/')
        wallfill_svg      = File.join(temp_dir, 'nauq_cad_to_3d_wallfill.svg').tr('\\', '/')
        insert_door_svg   = File.join(temp_dir, 'nauq_cad_to_3d_insert_door.svg').tr('\\', '/')
        door_settings_svg = File.join(temp_dir, 'nauq_cad_to_3d_door_settings.svg').tr('\\', '/')
        resize_svg        = File.join(temp_dir, 'nauq_cad_to_3d_resize.svg').tr('\\', '/')
        hide_overlap_svg  = File.join(temp_dir, 'nauq_cad_to_3d_hide_overlap.svg').tr('\\', '/')
        stair_svg         = File.join(temp_dir, 'nauq_cad_to_3d_stair.svg').tr('\\', '/')
        snapshot_svg      = File.join(temp_dir, 'nauq_cad_to_3d_snapshot.svg').tr('\\', '/')

        begin
          File.write(settings_svg, SETTINGS_ICON_SVG)
          File.write(import_svg, IMPORT_DWG_ICON_SVG)
          File.write(wallfill_svg, WALLFILL_ICON_SVG)
          File.write(insert_door_svg, INSERT_DOOR_ICON_SVG)
          File.write(door_settings_svg, DOOR_SETTINGS_ICON_SVG)
          File.write(resize_svg, RESIZE_DOOR_ICON_SVG)
          File.write(hide_overlap_svg, HIDE_OVERLAP_ICON_SVG)
          File.write(stair_svg, STAIR_ICON_SVG)
          File.write(snapshot_svg, SNAPSHOT_ICON_SVG)
        rescue StandardError => e
          Logger.warn("Không thể ghi SVG icons: #{e.message}")
        end

        {
          settings: settings_svg,
          import: import_svg,
          wallfill: wallfill_svg,
          insert_door: insert_door_svg,
          door_settings: door_settings_svg,
          resize: resize_svg,
          hide_overlap: hide_overlap_svg,
          stair: stair_svg,
          snapshot: snapshot_svg
        }
      end

      def open_settings
        SettingsDialog.show
      end

      def open_replace_dialog
        ReplaceDialog.show
      end

      def open_resize_dialog
        ResizeToolDialog.show
      end

      def open_stair_dialog
        StairDialog.show
      end

      # Kích hoạt công cụ chụp & cắt khung nhìn trực quan (Snapshot Crop Tool)
      def capture_viewport_to_clipboard
        model = Sketchup.active_model
        return unless model

        tool = SnapshotCropTool.new
        model.select_tool(tool)
      end

      def open_manual_door_tool
        model = Sketchup.active_model
        return unless model

        tool = ManualDoorPlacementTool.new do |width, height, door_type, panel_count, has_fix_top|
          # Callback when user selects door config in dialog
          Logger.info("Manual door creation: width=#{width.round}mm, height=#{height.round}mm, type=#{door_type}, panels=#{panel_count}, fix_top=#{has_fix_top}")
          
          # TODO: Implement door creation logic based on parameters
          # For now, just log the action
          ::UI.messagebox("Manual door tool activated!\n\nWidth: #{width.round}mm\nHeight: #{height.round}mm\nType: #{door_type}\nPanels: #{panel_count}", MB_OK)
        end
        
        model.select_tool(tool)
      end

      def activate_wallfill_tool
        tool = WallFillTool.new(:door)
        Sketchup.active_model.select_tool(tool)
      end

      def activate_opening_door_tool
        model = Sketchup.active_model
        return unless model

        selected_faces = model.selection.grep(Sketchup::Face)
        tool = OpeningDoorTool.new
        if selected_faces.any?
          tool.create_from_selected_faces(selected_faces)
        else
          model.select_tool(tool)
        end
      end

      def hide_overlapping_edges
        model = Sketchup.active_model
        return unless model

        # Collect targets from selection, or whole model if nothing selected
        targets = model.selection.empty? ? model.entities : model.selection

        model.start_operation('Hide Overlapping Edges', true)
        begin
          hidden_count = Core::GeometryHelper.hide_coplanar_overlap_edges(targets)
          model.commit_operation
          msg = hidden_count > 0 ? "Đã ẩn thành công #{hidden_count} nét trùng lặp!" : "Không tìm thấy nét giáp ranh / nét trùng nào cần ẩn."
          Sketchup.status_text = msg
          ::UI.messagebox(msg, MB_OK)
        rescue StandardError => e
          model.abort_operation
          Logger.error("Lỗi khi ẩn nét trùng: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
          ::UI.messagebox("Lỗi khi ẩn nét trùng: #{e.message}", MB_OK)
        end
      end

      def unhide_all_edges
        model = Sketchup.active_model
        return unless model

        targets = model.selection.empty? ? model.entities : model.selection

        model.start_operation('Unhide All Edges', true)
        begin
          unhidden_count = Core::GeometryHelper.unhide_all_edges(targets)
          model.commit_operation
          msg = unhidden_count > 0 ? "Đã hiện lại #{unhidden_count} nét ẩn trong vùng chọn!" : "Không có nét ẩn nào trong vùng chọn."
          Sketchup.status_text = msg
          ::UI.messagebox(msg, MB_OK)
        rescue StandardError => e
          model.abort_operation
          Logger.error("Lỗi khi hiện nét ẩn: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
          ::UI.messagebox("Lỗi khi hiện nét ẩn: #{e.message}", MB_OK)
        end
      end

      # Paste from AutoCAD (Ctrl+C / COPYCLIP from AutoCAD within 30 seconds)
      def paste_from_cad
        latest_file = CADClipboard.find_latest_cad_copy(30.0)
        if latest_file && File.exist?(latest_file)
          age_secs = ((Time.now - File.mtime(latest_file))).round(0)
          Logger.info("Đã tìm thấy bản vẽ CAD vừa copy từ AutoCAD (#{File.basename(latest_file)}, cách đây #{age_secs} giây).")
          run_pipeline(latest_file)
        else
          choice = ::UI.messagebox(
            "Không tìm thấy dữ liệu CAD vừa Copy từ AutoCAD (hoặc lệnh Copy đã quá 30 giây).\n\n" \
            "👉 Cách thực hiện:\n" \
            "1. Mở file AutoCAD, quét chọn đối tượng và bấm Ctrl + C.\n" \
            "2. Quay lại SketchUp và bấm ngay nút [TẠO 3D].\n\n" \
            "Bạn có muốn chọn file CAD (.DWG/.DXF) có sẵn từ máy tính không?",
            MB_YESNO
          )
          run_pipeline_from_file if choice == IDYES
        end
      end

      # Register Menus & Toolbar (Ensuring no duplicate toolbar items are added on reload)
      def init_ui
        register_menus_and_toolbars
      end

      def register_menus_and_toolbars
        return if @menus_registered
        @menus_registered = true

        icons = load_embedded_icons

        # 1. Menus
        begin
          main_menu = ::UI.menu('Plugins') || ::UI.menu('Extensions') || ::UI.menu('Draw')
          if main_menu
            menu = main_menu.add_submenu(PLUGIN_NAME) rescue nil
            target_menu = menu || main_menu
            target_menu.add_item('Cài đặt (Settings)...') { open_settings }
            if menu
              menu.add_separator
              menu.add_item('1. [TẠO 3D] Paste từ AutoCAD (Ctrl+C)...') { paste_from_cad }
              menu.add_item('2. [TẠO 3D] Chọn file CAD DWG...') { run_pipeline_from_file }
              menu.add_separator
              menu.add_item('3. [WALLFILL] Tạo Lanh-tô & Bậu cửa...') { activate_wallfill_tool }
              menu.add_item('4. [CỬA] Thêm Cửa vào Opening...') { activate_opening_door_tool }
              menu.add_item('5. [TƯỜNG] Ẩn Nét Trùng Lặp...') { hide_overlapping_edges }
              menu.add_item('6. [TƯỜNG] Hiện Nét Ẩn trong Vùng Chọn...') { unhide_all_edges }
              menu.add_item('7. Resize Door/Window...') { open_resize_dialog }
              menu.add_item('8. Tạo Cầu Thang (Stairs)...') { open_stair_dialog }
              menu.add_item('9. [CỬA THỦ CÔNG] Tạo Cửa Thủ Công (2 điểm)...') { open_manual_door_tool }
              menu.add_separator
              menu.add_item('10. [CHỤP 3D] Chụp Góc Nhìn 3D sang Clipboard (Ctrl+V)...') { capture_viewport_to_clipboard }
              menu.add_separator
              menu.add_item('[DEV] Reload Plugin (Nap lai code)') { reload! }
            else
              target_menu.add_item("[TẠO 3D] #{PLUGIN_NAME}") { paste_from_cad }
              target_menu.add_item("[WALLFILL] Tạo Lanh-tô") { activate_wallfill_tool }
              target_menu.add_item("[CỬA] Thêm Cửa vào Opening") { activate_opening_door_tool }
              target_menu.add_item("[TƯỜNG] Ẩn Nét Trùng Lặp") { hide_overlapping_edges }
              target_menu.add_item("[TƯỜNG] Hiện Nét Ẩn Vùng Chọn") { unhide_all_edges }
              target_menu.add_item("[THANG] Tạo Cầu Thang") { open_stair_dialog }
              target_menu.add_item("[CHỤP 3D] Chụp Góc Nhìn 3D sang Clipboard") { capture_viewport_to_clipboard }
              target_menu.add_item("[DEV] Reload #{PLUGIN_NAME}") { reload! }
            end
          end
        rescue StandardError, ScriptError => e
          puts "[NAUQ CAD TO 3D] Warning: Menu creation skipped: #{e.message}"
        end

        # 2. Toolbar
        begin
          tb = ::UI::Toolbar.new(PLUGIN_NAME)

          cmd_settings = ::UI::Command.new('Settings') { open_settings }
          cmd_settings.menu_text = 'Cài đặt'
          cmd_settings.tooltip = 'Mở bảng Cài đặt NAUQ CAD TO 3D'

          if icons[:settings] && File.exist?(icons[:settings])
            cmd_settings.small_icon = icons[:settings]
            cmd_settings.large_icon = icons[:settings]
          end

          cmd_run = ::UI::Command.new('Build3D') { paste_from_cad }
          cmd_run.menu_text = '[TẠO 3D]'
          cmd_run.tooltip = 'Dán trực tiếp đối tượng vừa Ctrl+C từ AutoCAD để Tạo 3D'

          if icons[:import] && File.exist?(icons[:import])
            cmd_run.small_icon = icons[:import]
            cmd_run.large_icon = icons[:import]
          end

          cmd_wallfill = ::UI::Command.new('WallFill') { activate_wallfill_tool }
          cmd_wallfill.menu_text = 'Tạo Lanh-tô'
          cmd_wallfill.tooltip = 'Tạo Lanh-tô cửa đi & Bậu cửa sổ (Click vào mặt hốc tường đứng)'

          if icons[:wallfill] && File.exist?(icons[:wallfill])
            cmd_wallfill.small_icon = icons[:wallfill]
            cmd_wallfill.large_icon = icons[:wallfill]
          end

          cmd_insert_door = ::UI::Command.new('InsertDoor') { activate_opening_door_tool }
          cmd_insert_door.menu_text = 'Thêm Cửa'
          cmd_insert_door.tooltip = 'Thêm Cửa vào Opening (Click hốc tường | Bấm [Alt] để vẽ thủ công 2 điểm)'

          if icons[:insert_door] && File.exist?(icons[:insert_door])
            cmd_insert_door.small_icon = icons[:insert_door]
            cmd_insert_door.large_icon = icons[:insert_door]
          end

          cmd_hide_overlap = ::UI::Command.new('HideOverlap') { hide_overlapping_edges }
          cmd_hide_overlap.menu_text = 'Ẩn Nét Trùng'
          cmd_hide_overlap.tooltip = 'Ẩn các nét trùng lặp / giáp ranh giữa các khối tường, Group hoặc Component'

          if icons[:hide_overlap] && File.exist?(icons[:hide_overlap])
            cmd_hide_overlap.small_icon = icons[:hide_overlap]
            cmd_hide_overlap.large_icon = icons[:hide_overlap]
          end

          cmd_resize = ::UI::Command.new('ResizeDoorWindow') { open_resize_dialog }
          cmd_resize.menu_text = 'Resize Door/Window'
          cmd_resize.tooltip = 'Click chọn hoặc quét nhiều cửa trên mô hình để sửa kích thước Dài/Rộng/Cao nhanh'

          if icons[:resize] && File.exist?(icons[:resize])
            cmd_resize.small_icon = icons[:resize]
            cmd_resize.large_icon = icons[:resize]
          end

          cmd_stair = ::UI::Command.new('StairBuilder') { open_stair_dialog }
          cmd_stair.menu_text = 'Tạo Cầu Thang'
          cmd_stair.tooltip = 'Tạo Cầu Thang 3D chuẩn kết cấu thi công và phong thủy'

          if icons[:stair] && File.exist?(icons[:stair])
            cmd_stair.small_icon = icons[:stair]
            cmd_stair.large_icon = icons[:stair]
          end

          cmd_snapshot = ::UI::Command.new('Snapshot3D') { capture_viewport_to_clipboard }
          cmd_snapshot.menu_text = 'Chụp 3D sang Clipboard'
          cmd_snapshot.tooltip = 'Chụp góc nhìn 3D độ nét cao (1920x1080) và sao chép vào Clipboard (Ctrl+V để dán)'

          if icons[:snapshot] && File.exist?(icons[:snapshot])
            cmd_snapshot.small_icon = icons[:snapshot]
            cmd_snapshot.large_icon = icons[:snapshot]
          end

          tb.add_item(cmd_settings)
          tb.add_item(cmd_run)
          tb.add_item(cmd_wallfill)
          tb.add_item(cmd_insert_door)
          tb.add_item(cmd_hide_overlap)
          tb.add_item(cmd_resize)
          tb.add_item(cmd_stair)
          tb.add_item(cmd_snapshot)

          tb.show
          tb.restore if tb.respond_to?(:get_last_state) && tb.get_last_state == 1

          @toolbar = tb
        rescue StandardError, ScriptError => e
          puts "[NAUQ CAD TO 3D] Warning: Toolbar creation skipped: #{e.message}"
        end

          # Right-click Context Menu
          begin
            ::UI.add_context_menu_handler do |context_menu|
              sub = context_menu.add_submenu('NAUQ CAD to 3D')
              sub.add_item('Ẩn Nét Trùng Lặp (Hide Overlap)') { hide_overlapping_edges }
              sub.add_item('Hiện Nét Ẩn trong Vùng Chọn (Unhide Selected)') { unhide_all_edges }
            end
          rescue StandardError, ScriptError => e
            puts "[NAUQ CAD TO 3D] Warning: Context menu creation skipped: #{e.message}"
          end
        end
      end
    end
  end

# Alias for TT_CAD_TO_3D namespace compatibility
TT_CAD_TO_3D = NAUQ::CadTo3D unless defined?(TT_CAD_TO_3D)

# Boot sequence: load all submodules, then initialize UI
# This MUST be at the end of the file so all methods are defined first.
if defined?(Sketchup)
  puts '[NAUQ CAD TO 3D] === BOOT START ==='
  begin
    NAUQ::CadTo3D.reload!
    puts '[NAUQ CAD TO 3D] === reload! OK ==='
  rescue StandardError, ScriptError => e
    puts "[NAUQ CAD TO 3D] === reload! FAILED: #{e.class}: #{e.message} ==="
    puts e.backtrace.first(3).join("\n") if e.backtrace
  end

  begin
    NAUQ::CadTo3D.init_ui
    puts '[NAUQ CAD TO 3D] === init_ui OK ==='
  rescue StandardError, ScriptError => e
    puts "[NAUQ CAD TO 3D] === init_ui FAILED: #{e.class}: #{e.message} ==="
    puts e.backtrace.first(3).join("\n") if e.backtrace
  end

  file_loaded(__FILE__) unless file_loaded?(__FILE__)
  puts '[NAUQ CAD TO 3D] === BOOT COMPLETE ==='
end
