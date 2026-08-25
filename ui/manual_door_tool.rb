# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # Manual Door Placement Tool
    # Cho phép người dùng chọn 2 điểm để định nghĩa kích thước cửa (width, height)
    # Sau đó dialog hiện lên để chọn loại cửa (số cánh, có ô fix kính trên, v.v...)
    class ManualDoorPlacementTool
      attr_accessor :first_point, :second_point, :dialog

      def initialize(&on_door_created)
        @first_point = nil
        @second_point = nil
        @ip = Sketchup::InputPoint.new
        @temp_line = nil
        @callback = on_door_created
        @dialog = nil
      end

      def activate
        Sketchup.status_text = '[NAUQ CAD TO 3D] Manual Door: Click điểm thứ nhất (góc dưới bên trái hốc cửa)'
      end

      def deactivate(view)
        view.invalidate
        cleanup_temp_line
      end

      def resume(view)
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        return unless @first_point

        @ip.pick(view, x, y)
        return unless @ip.valid?

        @second_point = @ip.position
        cleanup_temp_line

        # Vẽ temp line để preview
        @temp_line = view.draw_line(@first_point, @second_point)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @ip.pick(view, x, y)
        return unless @ip.valid?

        if @first_point.nil?
          # Chọn điểm thứ nhất
          @first_point = @ip.position
          Sketchup.status_text = '[NAUQ CAD TO 3D] Manual Door: Click điểm thứ hai (góc trên bên phải hốc cửa)'
        elsif @second_point.nil?
          # Chọn điểm thứ hai
          @second_point = @ip.position
          
          # Tính toán kích thước
          width = (@second_point.x - @first_point.x).abs
          height = (@second_point.z - @first_point.z).abs

          if width < 300 || height < 1500
            UI.messagebox('Kích thước cửa không hợp lệ! (Min width: 300mm, height: 1500mm)', MB_OK)
            @second_point = nil
            Sketchup.status_text = '[NAUQ CAD TO 3D] Manual Door: Click điểm thứ hai (góc trên bên phải hốc cửa)'
            return
          end

          cleanup_temp_line
          show_door_config_dialog(width, height)
          reset_tool
        end
      end

      def onKeyDown(key, _repeat, _flags, view)
        if key == VK_ESCAPE
          cleanup_temp_line
          reset_tool
          Sketchup.active_model.tools.pop_tool
        end
      end

      private

      def cleanup_temp_line
        @temp_line = nil
      end

      def reset_tool
        @first_point = nil
        @second_point = nil
        Sketchup.status_text = '[NAUQ CAD TO 3D] Manual Door: Click điểm thứ nhất (góc dưới bên trái hốc cửa)'
      end

      def show_door_config_dialog(width, height)
        # Tạo dialog để chọn loại cửa
        dialog_html = create_dialog_html(width, height)
        
        @dialog = UI::WebDialog.new('Manual Door Configuration', true,
                                     'ManualDoorDialog',
                                     400, 350, 200, 200, true)
        
        @dialog.set_html(dialog_html)
        
        @dialog.add_action_callback('on_door_created') do |_dialog, params|
          # Parse thông số từ dialog
          parts = params.split('|')
          door_type = parts[0]
          panel_count = parts[1].to_i
          has_fix_top = parts[2] == 'true'
          
          # Gọi callback
          @callback.call(width, height, door_type, panel_count, has_fix_top) if @callback
        end
        
        @dialog.show
      end

      def create_dialog_html(width, height)
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <style>
              body {
                font-family: Segoe UI, Arial, sans-serif;
                background: #f5f5f5;
                margin: 0;
                padding: 12px;
              }
              .form-group {
                margin-bottom: 12px;
              }
              label {
                display: block;
                font-weight: 600;
                margin-bottom: 4px;
                color: #333;
              }
              input[type="text"],
              input[type="number"],
              select {
                width: 100%;
                padding: 8px;
                border: 1px solid #ccc;
                border-radius: 4px;
                font-size: 14px;
                box-sizing: border-box;
              }
              input:disabled {
                background: #eee;
                color: #999;
              }
              .radio-group {
                display: flex;
                gap: 12px;
                margin-top: 6px;
              }
              .radio-group label {
                display: flex;
                align-items: center;
                margin: 0;
                font-weight: 400;
              }
              .radio-group input {
                width: auto;
                margin-right: 4px;
              }
              .button-group {
                display: flex;
                gap: 8px;
                margin-top: 16px;
              }
              button {
                flex: 1;
                padding: 10px;
                border: none;
                border-radius: 4px;
                font-size: 14px;
                font-weight: 600;
                cursor: pointer;
                transition: background 0.2s;
              }
              .btn-create {
                background: #059669;
                color: white;
              }
              .btn-create:hover {
                background: #047857;
              }
              .btn-cancel {
                background: #e5e7eb;
                color: #333;
              }
              .btn-cancel:hover {
                background: #d1d5db;
              }
              .info-box {
                background: #dbeafe;
                border: 1px solid #3b82f6;
                border-radius: 4px;
                padding: 8px;
                margin-bottom: 12px;
                font-size: 13px;
                color: #1e40af;
              }
            </style>
          </head>
          <body>
            <div class="info-box">
              Width: #{width.round}mm | Height: #{height.round}mm
            </div>

            <div class="form-group">
              <label for="door-type">Loại cửa:</label>
              <select id="door-type">
                <option value="door">🚪 Cửa đi (Door)</option>
                <option value="window">🪟 Cửa sổ (Window)</option>
              </select>
            </div>

            <div class="form-group">
              <label for="panel-count">Số cánh:</label>
              <select id="panel-count">
                <option value="1">1 cánh</option>
                <option value="2" selected>2 cánh</option>
                <option value="4">4 cánh</option>
              </select>
            </div>

            <div class="form-group">
              <label>Ô fix kính trên (chỉ cho cửa sổ):</label>
              <div class="radio-group">
                <label>
                  <input type="radio" name="fix-top" value="true" checked> Có
                </label>
                <label>
                  <input type="radio" name="fix-top" value="false"> Không
                </label>
              </div>
            </div>

            <div class="button-group">
              <button class="btn-create" onclick="onCreate()">Tạo cửa</button>
              <button class="btn-cancel" onclick="onCancel()">Hủy</button>
            </div>

            <script>
              function onCreate() {
                const doorType = document.getElementById('door-type').value;
                const panelCount = document.getElementById('panel-count').value;
                const hasFixTop = document.querySelector('input[name="fix-top"]:checked').value;
                
                const params = doorType + '|' + panelCount + '|' + hasFixTop;
                window.location = 'skp:on_door_created@' + params;
              }

              function onCancel() {
                window.location = 'skp:on_cancel@';
              }
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end
