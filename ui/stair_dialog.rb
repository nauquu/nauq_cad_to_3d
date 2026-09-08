# frozen_string_literal: true

require 'json'

module NAUQ
  module CadTo3D
    # HtmlDialog for Construction-Accurate Parametric Stair Generator with Real-time 2D Floor Plan Preview
    module StairDialog
      class << self
        def show
          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            return
          end

          @dialog = UI::HtmlDialog.new(
            dialog_title: 'Tạo Cầu Thang',
            preferences_key: 'NAUQ_CAD_TO_3D_Stair_Dialog',
            scrollable: true,
            resizable: true,
            width: 740,
            height: 570,
            left: 200,
            top: 100,
            style: UI::HtmlDialog::STYLE_DIALOG
          )

          initial_data = load_saved_stair_settings
          @dialog.set_html(html_content(initial_data))
          attach_callbacks(@dialog)
          @dialog.show
        end

        def close
          @dialog&.close
        end

        private

        DEFAULT_STAIR_SETTINGS = {
          'floor_height' => 3600.0,
          'total_steps' => 21,
          'stair_width' => 1000.0,
          'tread_run' => 270.0,
          'slab_thickness' => 100.0,
          'type' => 'u_shape_3',
          'flight1_steps' => 8,
          'flight2_steps' => 5,
          'flight3_steps' => 8,
          'f1_steps' => 8,
          'f2_steps' => 5,
          'f3_steps' => 8,
          'l1_steps' => 11,
          'l2_steps' => 10,
          'winder_landing' => false
        }.freeze

        def attach_callbacks(dialog)
          dialog.add_action_callback('save_settings') do |_action_context, data_hash|
            save_stair_settings(data_hash) if data_hash.is_a?(Hash)
          end

          dialog.add_action_callback('get_initial_data') do |_action_context|
            data = load_saved_stair_settings
            dialog.execute_script("initStairDialog(#{data.to_json});")
          end

          dialog.add_action_callback('generate_stair') do |_action_context, data_hash|
            if data_hash.is_a?(Hash)
              save_stair_settings(data_hash)
              dialog.close
              model = Sketchup.active_model
              model.start_operation('NAUQ Tạo Cầu Thang 3D', true)

              begin
                # __dir__ may carry the wrong encoding on Windows; force UTF-8
                # (SketchupSuggestions/FileEncoding workaround).
                dialog_dir = __dir__.dup
                dialog_dir.force_encoding('UTF-8') if dialog_dir.respond_to?(:force_encoding)
                load File.join(dialog_dir, '../stair/railing_builder.rb') rescue nil
                load File.join(dialog_dir, '../stair/stair_builder.rb') rescue nil
                stair_group = StairBuilder.build(data_hash)
                if stair_group && stair_group.valid?
                  # Chuyển thành Component để dính trực tiếp vào con trỏ chuột (Interactive Placement)
                  comp_name = stair_group.name.to_s
                  comp_inst = stair_group.to_component
                  definition = comp_inst.definition
                  definition.name = comp_name unless comp_name.empty?
                  comp_inst.erase!
                  model.commit_operation

                  # Kích hoạt công cụ đặt cầu thang bám theo chuột tại điểm gốc chân thang (0,0,0)
                  UI.start_timer(0.05, false) do
                    model.place_component(definition, false)
                  end
                  Logger.info("Đã tạo cầu thang và dính theo con trỏ chuột: #{comp_name}")
                else
                  model.abort_operation
                  UI.messagebox('Không thể tạo hình học cầu thang.')
                end
              rescue StandardError => e
                model.abort_operation
                UI.messagebox("Lỗi khi tạo cầu thang: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
              end
            end
          end

          dialog.add_action_callback('cancel') do |_action_context|
            dialog.close
          end
        end

        def load_saved_stair_settings
          raw = Sketchup.read_default('NAUQ_CAD_TO_3D', 'stair_settings_b64', nil) rescue nil
          if raw.nil? || raw.empty?
            raw = Sketchup.read_default('NAUQ_CAD_TO_3D', 'stair_settings_json', nil) rescue nil
          end

          if raw && !raw.empty?
            begin
              json_str = raw.to_s.strip.start_with?('{') ? raw : Base64.decode64(raw)
              parsed = JSON.parse(json_str)
              if parsed.is_a?(Hash) && !parsed.empty?
                merged = DEFAULT_STAIR_SETTINGS.merge(parsed)
                return merged
              end
            rescue StandardError => e
              Logger.warn("Lỗi đọc thông số cầu thang đã lưu: #{e.message}") if defined?(Logger)
            end
          end

          # Fallback default
          DEFAULT_STAIR_SETTINGS.dup
        end

        def save_stair_settings(data_hash)
          return unless data_hash.is_a?(Hash) && defined?(Sketchup)

          json_str = data_hash.to_json
          b64 = Base64.encode64(json_str).strip
          Sketchup.write_default('NAUQ_CAD_TO_3D', 'stair_settings_b64', b64)
          Sketchup.write_default('NAUQ_CAD_TO_3D', 'stair_settings_json', json_str)
        end

        def html_content(initial_data = nil)
          initial_data ||= load_saved_stair_settings
          data_json = initial_data.to_json

          type_val = (initial_data['type'] || 'u_shape_3').to_s
          h_val = (initial_data['floor_height'] || 3600).to_f.round(1)
          h_val = h_val.to_i if h_val == h_val.to_i
          n_val = (initial_data['total_steps'] || 21).to_i
          f1_val = (initial_data['f1_steps'] || initial_data['flight1_steps'] || 8).to_i
          f2_val = (initial_data['f2_steps'] || initial_data['flight2_steps'] || 5).to_i
          f3_val = (initial_data['f3_steps'] || initial_data['flight3_steps'] || 8).to_i
          l1_val = (initial_data['l1_steps'] || 11).to_i
          l2_val = (initial_data['l2_steps'] || 10).to_i
          w_val = (initial_data['stair_width'] || 1000).to_f.round(1)
          w_val = w_val.to_i if w_val == w_val.to_i
          b_val = (initial_data['tread_run'] || 270).to_f.round(1)
          b_val = b_val.to_i if b_val == b_val.to_i
          raw_winder = initial_data['winder_landing']
          winder_val = if raw_winder.to_s == '3' || raw_winder == 3
                         3
                       elsif raw_winder == true || raw_winder == 'true' || raw_winder == 1 || raw_winder.to_s == '2' || raw_winder == 2
                         2
                       else
                         0
                       end

          <<~HTML
            <!DOCTYPE html>
            <html lang="vi">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Tạo Cầu Thang</title>
              <style>
                :root {
                  --primary: #2563eb;
                  --primary-hover: #1d4ed8;
                  --bg-main: #f8fafc;
                  --card-bg: #ffffff;
                  --text-main: #1e293b;
                  --text-muted: #64748b;
                  --border: #e2e8f0;
                  --radius: 8px;
                  --success: #16a34a;
                  --warning: #d97706;
                }

                * {
                  box-sizing: border-box;
                  margin: 0;
                  padding: 0;
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                  user-select: none;
                }

                body {
                  background-color: var(--bg-main);
                  color: var(--text-main);
                  font-size: 13px;
                  display: flex;
                  flex-direction: column;
                  height: 100vh;
                  overflow: hidden;
                }

                .header {
                  padding: 12px 18px;
                  background: var(--card-bg);
                  border-bottom: 1px solid var(--border);
                  display: flex;
                  align-items: center;
                  justify-content: space-between;
                }

                .header h1 {
                  font-size: 15px;
                  font-weight: 700;
                  color: var(--primary);
                  display: flex;
                  align-items: center;
                  gap: 8px;
                }

                .header .subtitle {
                  font-size: 12px;
                  color: var(--text-muted);
                }

                .content {
                  flex: 1;
                  min-height: 0;
                  padding: 14px 18px;
                  overflow: hidden;
                  display: flex;
                  flex-direction: column;
                  gap: 12px;
                }

                .type-selector {
                  display: grid;
                  grid-template-columns: repeat(3, 1fr);
                  gap: 8px;
                  flex-shrink: 0;
                }

                .type-btn {
                  background: var(--card-bg);
                  border: 2px solid var(--border);
                  border-radius: var(--radius);
                  padding: 8px;
                  text-align: center;
                  font-weight: 600;
                  font-size: 12px;
                  color: var(--text-muted);
                  cursor: pointer;
                  transition: all 0.15s ease;
                }

                .type-btn:hover {
                  border-color: #cbd5e1;
                  color: var(--text-main);
                }

                .type-btn.active {
                  border-color: var(--primary);
                  background: #eff6ff;
                  color: var(--primary);
                }

                .main-layout {
                  display: grid;
                  grid-template-columns: 310px 1fr;
                  gap: 14px;
                  flex: 1;
                  min-height: 0;
                  overflow: hidden;
                }

                .card {
                  background: var(--card-bg);
                  border: 1px solid var(--border);
                  border-radius: var(--radius);
                  padding: 12px;
                  display: flex;
                  flex-direction: column;
                  justify-content: space-between;
                  overflow-y: auto;
                  min-height: 0;
                }

                .card-title {
                  font-size: 12px;
                  font-weight: 700;
                  color: var(--text-muted);
                  text-transform: uppercase;
                  letter-spacing: 0.5px;
                  margin-bottom: 8px;
                }

                .form-group {
                  margin-bottom: 8px;
                }

                .form-label {
                  display: block;
                  font-size: 12px;
                  font-weight: 600;
                  margin-bottom: 3px;
                  color: var(--text-main);
                }

                .form-label .unit {
                  color: var(--text-muted);
                  font-weight: normal;
                }

                .form-input {
                  width: 100%;
                  height: 30px;
                  padding: 4px 8px;
                  border: 1px solid var(--border);
                  border-radius: 6px;
                  font-size: 13px;
                  color: var(--text-main);
                  background: #fff;
                  outline: none;
                }

                .form-input:focus {
                  border-color: var(--primary);
                  box-shadow: 0 0 0 2px rgba(37, 99, 235, 0.15);
                }

                .live-stat-badge {
                  font-size: 11px;
                  font-weight: 700;
                  padding: 2px 6px;
                  border-radius: 4px;
                  background: #f1f5f9;
                  color: var(--text-main);
                }

                .live-stat-badge.good {
                  background: #dcfce7;
                  color: var(--success);
                }

                .live-stat-badge.warn {
                  background: #fef3c7;
                  color: var(--warning);
                }

                .summary-box {
                  background: #f8fafc;
                  border: 1px solid #e2e8f0;
                  border-radius: 6px;
                  padding: 8px 12px;
                  display: flex;
                  flex-direction: column;
                  gap: 4px;
                  font-size: 12px;
                }

                .summary-row {
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                }

                .preview-card {
                  background: var(--card-bg);
                  border: 1px solid var(--border);
                  border-radius: var(--radius);
                  padding: 12px;
                  display: flex;
                  flex-direction: column;
                  min-height: 0;
                  overflow: hidden;
                }

                .preview-title {
                  font-size: 12px;
                  font-weight: 700;
                  color: var(--text-muted);
                  margin-bottom: 8px;
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                  flex-shrink: 0;
                }

                .preview-stage {
                  flex: 1;
                  min-height: 0;
                  background: #f1f5f9;
                  border-radius: 6px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  position: relative;
                  overflow: hidden;
                  border: 1px dashed #cbd5e1;
                }

                .preview-stage svg {
                  max-width: 100%;
                  max-height: 100%;
                  width: 100%;
                  height: 100%;
                }

                .preview-stage svg text {
                  stroke: none !important;
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
                  text-rendering: geometricPrecision;
                  -webkit-font-smoothing: antialiased;
                }

                .actions {
                  padding: 12px 18px;
                  background: var(--card-bg);
                  border-top: 1px solid var(--border);
                  display: flex;
                  justify-content: flex-end;
                  gap: 10px;
                  flex-shrink: 0;
                }

                .btn {
                  padding: 7px 16px;
                  border-radius: 6px;
                  font-size: 13px;
                  font-weight: 600;
                  cursor: pointer;
                  border: none;
                  transition: background 0.15s ease;
                }

                .btn-secondary {
                  background: #f1f5f9;
                  color: var(--text-main);
                }

                .btn-secondary:hover {
                  background: #e2e8f0;
                }

                .btn-primary {
                  background: var(--primary);
                  color: #ffffff;
                }

                .btn-primary:hover {
                  background: var(--primary-hover);
                }
              </style>
            </head>
            <body>
              <div class="header">
                <h1>
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="22 17 17 17 17 12 12 12 12 7 7 7 7 2 2 2"></polyline>
                  </svg>
                  Tạo Cầu Thang Chuẩn Thi Công
                </h1>
              </div>

              <div class="content">
                <div class="type-selector">
                  <div class="type-btn #{type_val == 'u_shape_3' ? 'active' : ''}" id="btn_u_shape_3" onclick="setType('u_shape_3')">Chữ U (3 Vế)</div>
                  <div class="type-btn #{type_val == 'straight' ? 'active' : ''}" id="btn_straight" onclick="setType('straight')">Thẳng (1 Vế)</div>
                  <div class="type-btn #{type_val == 'l_shape' ? 'active' : ''}" id="btn_l_shape" onclick="setType('l_shape')">Chữ L (90°)</div>
                </div>

                <div class="main-layout">
                  <div class="card">
                    <div>
                      <div class="card-title">Thông Số Hình Học</div>
                      
                      <div class="form-group">
                        <label class="form-label">Chiều cao tầng (H) <span class="unit">mm</span></label>
                        <input type="number" id="floor_height" class="form-input" value="#{h_val}" step="10" oninput="recalc()">
                      </div>

                      <div class="form-group">
                        <label class="form-label">Tổng số bậc (N) <span id="step_meaning" class="live-stat-badge">Sinh (#{n_val})</span></label>
                        <input type="number" id="total_steps" class="form-input" value="#{n_val}" min="3" max="50" oninput="recalc(true)">
                      </div>

                      <div class="form-group" id="group_split_3" style="display: #{type_val == 'u_shape_3' ? 'block' : 'none'};">
                        <label class="form-label">Số bậc Vế 1 - Vế 2 - Vế 3</label>
                        <div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 6px;">
                          <input type="number" id="f1_steps" class="form-input" value="#{f1_val}" min="1" oninput="onCustomSplit3(1)">
                          <input type="number" id="f2_steps" class="form-input" value="#{f2_val}" min="1" oninput="onCustomSplit3(2)">
                          <input type="number" id="f3_steps" class="form-input" value="#{f3_val}" min="1" oninput="onCustomSplit3(3)">
                        </div>
                      </div>

                      <div class="form-group" id="group_split_2" style="display: #{type_val == 'l_shape' ? 'block' : 'none'};">
                        <label class="form-label">Số bậc Vế 1 / Vế 2</label>
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 6px;">
                          <input type="number" id="l1_steps" class="form-input" value="#{l1_val}" min="1" oninput="onCustomSplit2(1)">
                          <input type="number" id="l2_steps" class="form-input" value="#{l2_val}" min="1" oninput="onCustomSplit2(2)">
                        </div>
                      </div>

                      <div class="form-group" id="group_winder" style="display: #{type_val == 'straight' ? 'none' : 'block'};">
                        <label class="form-label">Kiểu Chiếu Nghỉ</label>
                        <select id="winder_landing" class="form-input" onchange="recalc(true)">
                          <option value="0" #{winder_val == 0 ? 'selected' : ''}>Chiếu nghỉ phẳng (1 bậc)</option>
                          <option value="2" #{winder_val == 2 ? 'selected' : ''}>Chia 2 bậc chéo (1 đường chéo)</option>
                          <option value="3" #{winder_val == 3 ? 'selected' : ''}>Chia 3 bậc chéo (2 tia nan quạt)</option>
                        </select>
                      </div>

                      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px;">
                        <div class="form-group">
                          <label class="form-label">Rộng vế (W) <span class="unit">mm</span></label>
                          <input type="number" id="stair_width" class="form-input" value="#{w_val}" step="10" oninput="renderRealtimePlan(); saveCurrentFormState();">
                        </div>

                        <div class="form-group">
                          <label class="form-label">Mặt bậc (B) <span class="unit">mm</span></label>
                          <input type="number" id="tread_run" class="form-input" value="#{b_val}" step="5" oninput="recalc()">
                        </div>
                      </div>

                      <div class="form-group" style="margin-top: 6px; padding-top: 8px; border-top: 1px dashed var(--border);">
                        <label class="form-label" style="display: flex; align-items: center; justify-content: space-between; cursor: pointer;">
                          <span style="font-weight: 700; color: var(--primary);">Lan Can & Tay Vịn</span>
                          <input type="checkbox" id="railing_enabled" checked onchange="toggleRailingBox(); renderRealtimePlan(); saveCurrentFormState();">
                        </label>
                      </div>

                      <div id="railing_options_box" style="display: block;">
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px;">
                          <div class="form-group">
                            <label class="form-label">Kiểu lan can</label>
                            <select id="railing_style" class="form-input" onchange="renderRealtimePlan(); saveCurrentFormState();">
                              <option value="glass">Kính cường lực + Tay vịn</option>
                              <option value="vertical_bars">Nan sắt đứng + Tay vịn</option>
                              <option value="horizontal_rails">Thanh suốt ngang + Trụ</option>
                              <option value="handrail_only">Tay vịn đơn</option>
                            </select>
                          </div>

                          <div class="form-group">
                            <label class="form-label">Vị trí đặt</label>
                            <select id="railing_side" class="form-input" onchange="renderRealtimePlan(); saveCurrentFormState();">
                              <option value="inner">Trong (Giếng thang)</option>
                              <option value="outer">Ngoài (Sát tường)</option>
                              <option value="both">Cả 2 bên</option>
                            </select>
                          </div>
                        </div>

                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px;">
                          <div class="form-group">
                            <label class="form-label">Cao lan can <span class="unit">mm</span></label>
                            <input type="number" id="railing_height" class="form-input" value="900" step="50" min="600" max="1500" oninput="saveCurrentFormState();">
                          </div>

                          <div class="form-group">
                            <label class="form-label">Tiết diện tay vịn</label>
                            <select id="handrail_profile" class="form-input" onchange="saveCurrentFormState();">
                              <option value="rect_60_40">Hộp 60x40 mm</option>
                              <option value="round_50">Tròn Ø50 mm</option>
                              <option value="square_40">Vuông 40x40 mm</option>
                            </select>
                          </div>
                        </div>
                      </div>
                    </div>

                    <div class="summary-box">
                      <div class="summary-row">
                        <span>Cổ bậc (h):</span>
                        <strong id="calc_riser_h">171.4 mm</strong>
                      </div>
                      <div class="summary-row">
                        <span>Độ dốc (α):</span>
                        <strong id="calc_slope">32.4°</strong>
                      </div>
                      <div class="summary-row">
                        <span>Bản đáy:</span>
                        <strong>Bê tông 100mm</strong>
                      </div>
                    </div>
                  </div>

                  <div class="preview-card">
                    <div class="preview-title">
                      <span>MẶT BẰNG THANG (REALTIME)</span>
                      <span id="preview_type_label" style="color: var(--primary); font-size: 11px;">Thang Chữ U</span>
                    </div>
                    
                    <div class="preview-stage" id="preview_stage">
                    </div>
                  </div>
                </div>

                <div class="actions">
                  <button type="button" class="btn btn-secondary" onclick="cancel()">Hủy</button>
                  <button type="button" class="btn btn-primary" onclick="generate()">+ Tạo Cầu Thang 3D</button>
                </div>

                <script>
                  const initialSavedData = #{data_json};
                  let currentType = '#{type_val}';

                  function toggleRailingBox() {
                    const chk = document.getElementById('railing_enabled');
                    const box = document.getElementById('railing_options_box');
                    if (box && chk) {
                      box.style.display = chk.checked ? 'block' : 'none';
                    }
                  }

                  function getWinderVal() {
                    if (currentType === 'straight') return 0;
                    const elem = document.getElementById('winder_landing');
                    return elem ? (parseInt(elem.value) || 0) : 0;
                  }

                  function saveCurrentFormState() {
                    const f1 = parseInt(document.getElementById('f1_steps').value) || 8;
                    const f2 = parseInt(document.getElementById('f2_steps').value) || 5;
                    const f3 = parseInt(document.getElementById('f3_steps').value) || 8;
                    const l1 = parseInt(document.getElementById('l1_steps').value) || 11;
                    const l2 = parseInt(document.getElementById('l2_steps').value) || 10;
                    const winder = getWinderVal();

                    const rEnabled = document.getElementById('railing_enabled') ? document.getElementById('railing_enabled').checked : true;
                    const rStyle = document.getElementById('railing_style') ? document.getElementById('railing_style').value : 'glass';
                    const rSide = document.getElementById('railing_side') ? document.getElementById('railing_side').value : 'inner';
                    const rHeight = parseFloat(document.getElementById('railing_height') ? document.getElementById('railing_height').value : 900) || 900;
                    const rProfile = document.getElementById('handrail_profile') ? document.getElementById('handrail_profile').value : 'rect_60_40';

                    const payload = {
                      type: currentType,
                      floor_height: parseFloat(document.getElementById('floor_height').value) || 3600,
                      total_steps: parseInt(document.getElementById('total_steps').value) || 21,
                      flight1_steps: currentType === 'l_shape' ? l1 : f1,
                      flight2_steps: currentType === 'l_shape' ? l2 : f2,
                      flight3_steps: f3,
                      f1_steps: f1,
                      f2_steps: f2,
                      f3_steps: f3,
                      l1_steps: l1,
                      l2_steps: l2,
                      stair_width: parseFloat(document.getElementById('stair_width').value) || 1000,
                      tread_run: parseFloat(document.getElementById('tread_run').value) || 270,
                      slab_thickness: 100.0,
                      winder_landing: winder,
                      railing: {
                        enabled: rEnabled,
                        style: rStyle,
                        side: rSide,
                        height: rHeight,
                        handrail_profile: rProfile,
                        inset: 50.0
                      }
                    };

                    try { localStorage.setItem('NAUQ_STAIR_SAVED_DATA', JSON.stringify(payload)); } catch(e) {}
                    if (window.sketchup && typeof sketchup.save_settings === 'function') {
                      sketchup.save_settings(payload);
                    }
                  }

                  function renderRealtimePlan() {
                    const stage = document.getElementById('preview_stage');
                    const label = document.getElementById('preview_type_label');
                    const type = currentType;
                    const winderVal = getWinderVal();
                    const rEnabled = document.getElementById('railing_enabled') ? document.getElementById('railing_enabled').checked : true;
                    const rSide = document.getElementById('railing_side') ? document.getElementById('railing_side').value : 'inner';
                    let svg = '';

                    if (type === 'straight') {
                      label.textContent = 'Thang Thẳng (1 Vế)';
                      const n = parseInt(document.getElementById('total_steps').value) || 21;
                      const step_h = 16;
                      const w = 65;
                      const l = Math.max(1, n - 1) * step_h;
                      const pad = 20;
                      const view_w = w + 2 * pad;
                      const view_h = l + 2 * pad;
                      const x = pad;
                      const y = pad;

                      let steps_svg = '';
                      let nums_svg = '';
                      for (let i = 1; i < n; i++) {
                        const sy = (y + l - i * step_h).toFixed(1);
                        steps_svg += `<line x1="${x}" y1="${sy}" x2="${x + w}" y2="${sy}" stroke="#93C5FD" stroke-width="1.5"/>`;
                      }

                      for (let i = 1; i <= n - 1; i++) {
                        const cx = (x + 14).toFixed(1);
                        const cy = (y + l - (i - 0.5) * step_h + 3.5).toFixed(1);
                        nums_svg += `<text x="${cx}" y="${cy}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${i}</text>`;
                      }

                      let rail_1_svg = '';
                      if (rEnabled) {
                        if (rSide === 'inner' || rSide === 'both') {
                          rail_1_svg += `<line x1="${x + 6}" y1="${y + l}" x2="${x + 6}" y2="${y}" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round"/>`;
                        }
                        if (rSide === 'outer' || rSide === 'both') {
                          rail_1_svg += `<line x1="${x + w - 6}" y1="${y + l}" x2="${x + w - 6}" y2="${y}" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round"/>`;
                        }
                      }

                      svg = `
                        <svg viewBox="0 0 ${view_w} ${view_h}" width="100%" height="100%" fill="none">
                          <rect x="${x}" y="${y}" width="${w}" height="${l}" fill="#EFF6FF" stroke="#2563EB" stroke-width="2"/>
                          ${steps_svg}
                          <path d="M ${x + w/2},${y + l - 8} L ${x + w/2},${y + 12}" stroke="#2563EB" stroke-width="1.8" stroke-dasharray="4 3" stroke-linecap="round"/>
                          <circle cx="${x + w/2}" cy="${y + l - 8}" r="2.5" fill="#2563EB" stroke="none"/>
                          <polygon points="${x + w/2},${y + 12} ${x + w/2 - 4},${y + 20} ${x + w/2 + 4},${y + 20}" fill="#2563EB" stroke="none"/>
                          ${nums_svg}
                          ${rail_1_svg}
                        </svg>
                      `;
                    } else if (type === 'l_shape') {
                      let typeDesc = 'Thang Chữ L (90°)';
                      if (winderVal === 2) typeDesc += ' - Chia 2 Bậc Chéo';
                      if (winderVal === 3) typeDesc += ' - Chia 3 Bậc Chéo';
                      label.textContent = typeDesc;

                      const n1 = parseInt(document.getElementById('l1_steps').value) || 10;
                      const n2 = parseInt(document.getElementById('l2_steps').value) || 10;
                      const step_px = 22;
                      const w = 65;
                      const l1 = (n1 - 1) * step_px;
                      const l2 = (n2 - 1) * step_px;
                      const pad = 22;
                      const total_w = w + l2;
                      const total_h = w + l1;
                      const view_w = total_w + 2 * pad;
                      const view_h = total_h + 2 * pad;
                      const landing_x = pad;
                      const landing_y = pad;
                      const f1_x = pad;
                      const f1_y = pad + w;
                      const f2_x = pad + w;
                      const f2_y = pad;

                      // Flight 1: Dọc bên trái, đi từ Dưới lên Trên - Chữ ở nửa ngoài (Bên Trái)
                      let steps_1 = '';
                      let nums_1 = '';
                      for (let i = 1; i < n1; i++) {
                        const sy = (f1_y + l1 - i * step_px).toFixed(1);
                        steps_1 += `<line x1="${f1_x}" y1="${sy}" x2="${f1_x + w}" y2="${sy}" stroke="#93C5FD" stroke-width="1.5"/>`;
                      }
                      for (let i = 1; i <= n1 - 1; i++) {
                        const cx = (f1_x + 14).toFixed(1);
                        const cy = (f1_y + l1 - (i - 0.5) * step_px + 3.5).toFixed(1);
                        nums_1 += `<text x="${cx}" y="${cy}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${i}</text>`;
                      }

                      // Flight 2: Ngang ở trên, đi từ Trái sang Phải - Chữ ở nửa ngoài (Phía Trên)
                      let steps_2 = '';
                      let nums_2 = '';
                      for (let j = 1; j < n2; j++) {
                        const sx = (f2_x + j * step_px).toFixed(1);
                        steps_2 += `<line x1="${sx}" y1="${f2_y}" x2="${sx}" y2="${f2_y + w}" stroke="#93C5FD" stroke-width="1.5"/>`;
                      }
                      const landingSteps = winderVal === 3 ? 3 : (winderVal === 2 ? 2 : 1);
                      const f2_start = n1 + landingSteps;
                      for (let j = 0; j < n2 - 1; j++) {
                        const cx = (f2_x + (j + 0.5) * step_px).toFixed(1);
                        const cy = (f2_y + 14).toFixed(1);
                        const num = f2_start + j;
                        nums_2 += `<text x="${cx}" y="${cy}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${num}</text>`;
                      }

                      let landing_svg = '';
                      if (winderVal === 3) {
                        landing_svg = `
                          <rect x="${landing_x}" y="${landing_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <line x1="${landing_x + w}" y1="${landing_y + w}" x2="${landing_x}" y2="${landing_y + w/2}" stroke="#93C5FD" stroke-width="1.5"/>
                          <line x1="${landing_x + w}" y1="${landing_y + w}" x2="${landing_x + w/2}" y2="${landing_y}" stroke="#93C5FD" stroke-width="1.5"/>
                          <text x="${landing_x + 14}" y="${landing_y + w - 12}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${n1}</text>
                          <text x="${landing_x + 18}" y="${landing_y + 20}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${n1 + 1}</text>
                          <text x="${landing_x + w - 14}" y="${landing_y + 14}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${n1 + 2}</text>
                        `;
                      } else if (winderVal === 2) {
                        landing_svg = `
                          <rect x="${landing_x}" y="${landing_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <line x1="${landing_x + w}" y1="${landing_y + w}" x2="${landing_x}" y2="${landing_y + w}" stroke="#93C5FD" stroke-width="1.5"/>
                          <text x="${landing_x + 14}" y="${landing_y + w - 14}" fill="#1E40AF" font-size="9" font-weight="600" text-anchor="middle" stroke="none">${n1}</text>
                          <text x="${landing_x + 16}" y="${landing_y + 16}" fill="#1E40AF" font-size="9" font-weight="600" text-anchor="middle" stroke="none">${n1 + 1}</text>
                        `;
                      } else {
                        landing_svg = `<rect x="${landing_x}" y="${landing_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <text x="${landing_x + 16}" y="${landing_y + 16}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${n1}</text>`;
                      }

                      let rail_l_svg = '';
                      if (rEnabled) {
                        if (rSide === 'inner' || rSide === 'both') {
                          rail_l_svg += `<path d="M ${f1_x + w - 6},${f1_y + l1} L ${landing_x + w - 6},${landing_y + w - 6} L ${f2_x + l2},${landing_y + w - 6}" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
                        }
                        if (rSide === 'outer' || rSide === 'both') {
                          rail_l_svg += `<path d="M ${f1_x + 6},${f1_y + l1} L ${landing_x + 6},${landing_y + 6} L ${f2_x + l2},${landing_y + 6}" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
                        }
                      }

                      svg = `
                        <svg viewBox="0 0 ${view_w} ${view_h}" width="100%" height="100%" fill="none">
                          <rect x="${f1_x}" y="${f1_y}" width="${w}" height="${l1}" fill="#EFF6FF" stroke="#2563EB" stroke-width="2"/>
                          ${steps_1}
                          ${nums_1}
                          ${landing_svg}
                          <rect x="${f2_x}" y="${f2_y}" width="${l2}" height="${w}" fill="#EFF6FF" stroke="#2563EB" stroke-width="2"/>
                          ${steps_2}
                          ${nums_2}
                          <path d="M ${f1_x + w/2},${f1_y + l1 - 8} L ${landing_x + w/2},${landing_y + w/2} L ${f2_x + l2 - 8},${f2_y + w/2}" fill="none" stroke="#2563EB" stroke-width="1.8" stroke-dasharray="4 3" stroke-linecap="round" stroke-linejoin="round"/>
                          <circle cx="${f1_x + w/2}" cy="${f1_y + l1 - 8}" r="2.5" fill="#2563EB" stroke="none"/>
                          <polygon points="${f2_x + l2 - 8},${f2_y + w/2} ${f2_x + l2 - 16},${f2_y + w/2 - 4} ${f2_x + l2 - 16},${f2_y + w/2 + 4}" fill="#2563EB" stroke="none"/>
                          ${rail_l_svg}
                        </svg>
                      `;
                    } else { // u_shape_3
                      let typeDesc = 'Thang Chữ U (3 Vế)';
                      if (winderVal === 2) typeDesc += ' - Chia 2 Bậc Chéo';
                      if (winderVal === 3) typeDesc += ' - Chia 3 Bậc Chéo';
                      label.textContent = typeDesc;
                      const n1 = parseInt(document.getElementById('f1_steps').value) || 7;
                      const n2 = parseInt(document.getElementById('f2_steps').value) || 4;
                      const n3 = parseInt(document.getElementById('f3_steps').value) || 8;
                      const step_px = 20;
                      const w = 60;
                      const l1 = (n1 - 1) * step_px;
                      const l2 = (n2 - 1) * step_px;
                      const l3 = (n3 - 1) * step_px;
                      const pad = 20;
                      const max_h = Math.max(l1, l3);
                      const total_w = 2 * w + l2;
                      const total_h = w + max_h;
                      const view_w = total_w + 2 * pad;
                      const view_h = total_h + 2 * pad;
                      const landing1_x = pad;
                      const landing1_y = pad;
                      const f1_x = pad;
                      const f1_y = pad + w;
                      const f1_bottom = f1_y + l1;
                      const f2_x = pad + w;
                      const f2_y = pad;
                      const landing2_x = pad + w + l2;
                      const landing2_y = pad;
                      const f3_x = pad + w + l2;
                      const f3_y = pad + w;
                      const f3_bottom = f3_y + l3;
                      const void_x = pad + w;
                      const void_y = pad + w;
                      const void_w = l2;
                      const void_h = max_h;

                      // Flight 1: Dọc bên trái, đi từ Dưới lên Trên - Chữ ở nửa ngoài (Bên Trái)
                      let steps_1 = '', nums_1 = '';
                      for (let i = 1; i < n1 - 1; i++) {
                        const sy = (f1_bottom - i * step_px).toFixed(1);
                        steps_1 += `<line x1="${f1_x}" y1="${sy}" x2="${f1_x + w}" y2="${sy}" stroke="#93C5FD" stroke-width="1.5"/>`;
                      }
                      for (let i = 1; i <= n1 - 1; i++) {
                        const cx = (f1_x + 14).toFixed(1);
                        const cy = (f1_bottom - (i - 0.5) * step_px + 3.5).toFixed(1);
                        nums_1 += `<text x="${cx}" y="${cy}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${i}</text>`;
                      }

                      // Flight 2: Ngang ở trên, đi từ Trái qua Phải - Chữ ở nửa ngoài (Phía Trên)
                      let steps_2 = '', nums_2 = '';
                      for (let j = 1; j < n2 - 1; j++) {
                        const sx = (f2_x + j * step_px).toFixed(1);
                        steps_2 += `<line x1="${sx}" y1="${f2_y}" x2="${sx}" y2="${f2_y + w}" stroke="#93C5FD" stroke-width="1.5"/>`;
                      }
                      const l1_steps_count = winderVal === 3 ? 3 : (winderVal === 2 ? 2 : 1);
                      const f2_start = n1 + l1_steps_count;
                      for (let j = 0; j < n2 - 1; j++) {
                        const cx = (f2_x + (j + 0.5) * step_px).toFixed(1);
                        const cy = (f2_y + 14).toFixed(1);
                        const num = f2_start + j;
                        nums_2 += `<text x="${cx}" y="${cy}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${num}</text>`;
                      }

                      // Flight 3: Dọc bên phải, đi từ Trên xuống Dưới - Chữ ở nửa ngoài (Bên Phải)
                      let steps_3 = '', nums_3 = '';
                      for (let k = 1; k < n3 - 1; k++) {
                        const sy = (f3_y + k * step_px).toFixed(1);
                        steps_3 += `<line x1="${f3_x}" y1="${sy}" x2="${f3_x + w}" y2="${sy}" stroke="#93C5FD" stroke-width="1.5"/>`;
                      }
                      const cn2_start = f2_start + (n2 - 1);
                      const l2_steps_count = winderVal === 3 ? 3 : (winderVal === 2 ? 2 : 1);
                      const f3_start = cn2_start + l2_steps_count;
                      for (let k = 0; k < n3 - 1; k++) {
                        const cx = (f3_x + w - 14).toFixed(1);
                        const cy = (f3_y + (k + 0.5) * step_px + 3.5).toFixed(1);
                        const num = f3_start + k;
                        nums_3 += `<text x="${cx}" y="${cy}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${num}</text>`;
                      }

                      let landing1_svg = '', landing2_svg = '';
                      if (winderVal === 3) {
                        landing1_svg = `
                          <rect x="${landing1_x}" y="${landing1_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <line x1="${landing1_x + w}" y1="${landing1_y + w}" x2="${landing1_x}" y2="${landing1_y + w/2}" stroke="#93C5FD" stroke-width="1.5"/>
                          <line x1="${landing1_x + w}" y1="${landing1_y + w}" x2="${landing1_x + w/2}" y2="${landing1_y}" stroke="#93C5FD" stroke-width="1.5"/>
                          <text x="${landing1_x + 14}" y="${landing1_y + w - 12}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${n1}</text>
                          <text x="${landing1_x + 18}" y="${landing1_y + 20}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${n1 + 1}</text>
                          <text x="${landing1_x + w - 14}" y="${landing1_y + 14}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${n1 + 2}</text>
                        `;
                        landing2_svg = `
                          <rect x="${landing2_x}" y="${landing2_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <line x1="${landing2_x}" y1="${landing2_y + w}" x2="${landing2_x + w/2}" y2="${landing2_y}" stroke="#93C5FD" stroke-width="1.5"/>
                          <line x1="${landing2_x}" y1="${landing2_y + w}" x2="${landing2_x + w}" y2="${landing2_y + w/2}" stroke="#93C5FD" stroke-width="1.5"/>
                          <text x="${landing2_x + 14}" y="${landing2_y + 14}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${cn2_start}</text>
                          <text x="${landing2_x + w - 18}" y="${landing2_y + 20}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${cn2_start + 1}</text>
                          <text x="${landing2_x + w - 14}" y="${landing2_y + w - 12}" fill="#1E40AF" font-size="8.5" font-weight="600" text-anchor="middle" stroke="none">${cn2_start + 2}</text>
                        `;
                      } else if (winderVal === 2) {
                        landing1_svg = `
                          <rect x="${landing1_x}" y="${landing1_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <line x1="${landing1_x}" y1="${landing1_y}" x2="${landing1_x + w}" y2="${landing1_y + w}" stroke="#93C5FD" stroke-width="1.5"/>
                          <text x="${landing1_x + 14}" y="${landing1_y + w - 14}" fill="#1E40AF" font-size="9" font-weight="600" text-anchor="middle" stroke="none">${n1}</text>
                          <text x="${landing1_x + 16}" y="${landing1_y + 16}" fill="#1E40AF" font-size="9" font-weight="600" text-anchor="middle" stroke="none">${n1 + 1}</text>
                        `;
                        landing2_svg = `
                          <rect x="${landing2_x}" y="${landing2_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <line x1="${landing2_x + w}" y1="${landing2_y}" x2="${landing2_x}" y2="${landing2_y + w}" stroke="#93C5FD" stroke-width="1.5"/>
                          <text x="${landing2_x + w - 16}" y="${landing2_y + 16}" fill="#1E40AF" font-size="9" font-weight="600" text-anchor="middle" stroke="none">${cn2_start}</text>
                          <text x="${landing2_x + w - 14}" y="${landing2_y + w - 14}" fill="#1E40AF" font-size="9" font-weight="600" text-anchor="middle" stroke="none">${cn2_start + 1}</text>
                        `;
                      } else {
                        landing1_svg = `<rect x="${landing1_x}" y="${landing1_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <text x="${landing1_x + 16}" y="${landing1_y + 16}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${n1}</text>`;
                        landing2_svg = `<rect x="${landing2_x}" y="${landing2_y}" width="${w}" height="${w}" fill="#DBEAFE" stroke="#2563EB" stroke-width="2"/>
                          <text x="${landing2_x + w - 16}" y="${landing2_y + 16}" fill="#1E40AF" font-size="9.5" font-weight="600" text-anchor="middle" stroke="none">${cn2_start}</text>`;
                      }

                      let rail_u_svg = '';
                      if (rEnabled) {
                        if (rSide === 'inner' || rSide === 'both') {
                          rail_u_svg += `<path d="M ${f1_x + w - 6},${f1_bottom} L ${landing1_x + w - 6},${landing1_y + w - 6} L ${landing2_x + 6},${landing2_y + w - 6} L ${f3_x + 6},${f3_bottom}" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
                        }
                        if (rSide === 'outer' || rSide === 'both') {
                          rail_u_svg += `<path d="M ${f1_x + 6},${f1_bottom} L ${landing1_x + 6},${landing1_y + 6} L ${landing2_x + w - 6},${landing2_y + 6} L ${f3_x + w - 6},${f3_bottom}" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
                        }
                      }

                      svg = `
                        <svg viewBox="0 0 ${view_w} ${view_h}" width="100%" height="100%" fill="none">
                          <rect x="${void_x}" y="${void_y}" width="${void_w}" height="${void_h}" fill="#F8FAFC" stroke="#CBD5E1" stroke-width="1.5" stroke-dasharray="4 4"/>
                          <rect x="${f1_x}" y="${f1_y}" width="${w}" height="${l1}" fill="#EFF6FF" stroke="#2563EB" stroke-width="2"/>
                          ${steps_1}
                          ${nums_1}
                          ${landing1_svg}
                          <rect x="${f2_x}" y="${f2_y}" width="${l2}" height="${w}" fill="#EFF6FF" stroke="#2563EB" stroke-width="2"/>
                          ${steps_2}
                          ${nums_2}
                          ${landing2_svg}
                          <rect x="${f3_x}" y="${f3_y}" width="${w}" height="${l3}" fill="#EFF6FF" stroke="#2563EB" stroke-width="2"/>
                          ${steps_3}
                          ${nums_3}
                          <path d="M ${f1_x + w/2},${f1_bottom - 8} L ${landing1_x + w/2},${landing1_y + w/2} L ${landing2_x + w/2},${landing2_y + w/2} L ${f3_x + w/2},${f3_bottom - 8}" fill="none" stroke="#2563EB" stroke-width="1.8" stroke-dasharray="4 3" stroke-linecap="round" stroke-linejoin="round"/>
                          <circle cx="${f1_x + w/2}" cy="${f1_bottom - 8}" r="2.5" fill="#2563EB" stroke="none"/>
                          <polygon points="${f3_x + w/2},${f3_bottom - 8} ${f3_x + w/2 - 4},${f3_bottom - 16} ${f3_x + w/2 + 4},${f3_bottom - 16}" fill="#2563EB" stroke="none"/>
                          ${rail_u_svg}
                        </svg>
                      `;
                    }
                    stage.innerHTML = svg;
                  }

                  function initStairDialog(data) {
                    if (!data) return;
                    if (data.floor_height) document.getElementById('floor_height').value = data.floor_height;
                    if (data.total_steps) document.getElementById('total_steps').value = data.total_steps;
                    if (data.stair_width) document.getElementById('stair_width').value = data.stair_width;
                    if (data.tread_run) document.getElementById('tread_run').value = data.tread_run;
                    if (document.getElementById('winder_landing') && typeof data.winder_landing !== 'undefined') {
                      let wVal = 0;
                      if (data.winder_landing.toString() === '3' || data.winder_landing === 3) wVal = 3;
                      else if (data.winder_landing === true || data.winder_landing === 'true' || data.winder_landing === 1 || data.winder_landing.toString() === '2' || data.winder_landing === 2) wVal = 2;
                      document.getElementById('winder_landing').value = wVal.toString();
                    }
                    if (data.type) setType(data.type, false);

                    if (data.f1_steps || data.flight1_steps) document.getElementById('f1_steps').value = data.f1_steps || data.flight1_steps;
                    if (data.f2_steps || data.flight2_steps) document.getElementById('f2_steps').value = data.f2_steps || data.flight2_steps;
                    if (data.f3_steps || data.flight3_steps) document.getElementById('f3_steps').value = data.f3_steps || data.flight3_steps;
                    if (data.l1_steps) document.getElementById('l1_steps').value = data.l1_steps;
                    if (data.l2_steps) document.getElementById('l2_steps').value = data.l2_steps;

                    if (data.railing) {
                      const r = data.railing;
                      if (typeof r.enabled !== 'undefined') {
                        const chk = document.getElementById('railing_enabled');
                        if (chk) chk.checked = (r.enabled === true || r.enabled === 'true');
                        toggleRailingBox();
                      }
                      if (r.style && document.getElementById('railing_style')) document.getElementById('railing_style').value = r.style;
                      if (r.side && document.getElementById('railing_side')) document.getElementById('railing_side').value = r.side;
                      if (r.height && document.getElementById('railing_height')) document.getElementById('railing_height').value = r.height;
                      if (r.handrail_profile && document.getElementById('handrail_profile')) document.getElementById('handrail_profile').value = r.handrail_profile;
                    }

                    recalc(false);
                  }

                  function setType(t, autoSplit = true) {
                    currentType = t;
                    document.querySelectorAll('.type-btn').forEach(btn => btn.classList.remove('active'));
                    const btn = document.getElementById('btn_' + t);
                    if (btn) btn.classList.add('active');
                    const split3 = document.getElementById('group_split_3');
                    const split2 = document.getElementById('group_split_2');
                    const winderGroup = document.getElementById('group_winder');
                    if (t === 'straight') {
                      split3.style.display = 'none'; split2.style.display = 'none'; winderGroup.style.display = 'none';
                    } else if (t === 'l_shape') {
                      split3.style.display = 'none'; split2.style.display = 'block'; winderGroup.style.display = 'block';
                    } else {
                      split3.style.display = 'block'; split2.style.display = 'none'; winderGroup.style.display = 'block';
                    }
                    recalc(autoSplit);
                    saveCurrentFormState();
                  }

                  function recalc(autoSplit = false) {
                    const h_total = parseFloat(document.getElementById('floor_height').value) || 3600;
                    const n = parseInt(document.getElementById('total_steps').value) || 21;
                    const b = parseFloat(document.getElementById('tread_run').value) || 270;
                    const winderVal = getWinderVal();

                    const riser_h = h_total / n;
                    const riserElem = document.getElementById('calc_riser_h');
                    riserElem.textContent = riser_h.toFixed(1) + ' mm';
                    riserElem.className = (riser_h >= 150 && riser_h <= 180) ? 'live-stat-badge good' : 'live-stat-badge warn';
                    document.getElementById('calc_slope').textContent = (Math.atan2(riser_h, b) * 180 / Math.PI).toFixed(1) + '°';

                    const cycle = n % 4;
                    const badge = document.getElementById('step_meaning');
                    const meanings = ['Cung Tử', 'Cung Sinh', 'Cung Lão', 'Cung Bệnh'];
                    badge.textContent = meanings[cycle] + ' (' + n + ')';
                    badge.className = (cycle === 1) ? 'live-stat-badge good' : ((cycle === 2) ? 'live-stat-badge' : 'live-stat-badge warn');

                    if (autoSplit) {
                      if (currentType === 'u_shape_3') {
                        const extra = winderVal === 3 ? 4 : (winderVal === 2 ? 2 : 0);
                        const usable = Math.max(3, n - extra);
                        const f2 = Math.max(2, Math.floor(usable * 0.25));
                        const rem = usable - f2;
                        document.getElementById('f1_steps').value = Math.floor(rem / 2);
                        document.getElementById('f2_steps').value = f2;
                        document.getElementById('f3_steps').value = rem - Math.floor(rem / 2);
                      } else if (currentType === 'l_shape') {
                        const extra = winderVal === 3 ? 2 : (winderVal === 2 ? 1 : 0);
                        const usable = Math.max(2, n - extra);
                        document.getElementById('l1_steps').value = Math.floor(usable / 2);
                        document.getElementById('l2_steps').value = usable - Math.floor(usable / 2);
                      }
                    } else {
                      if (currentType === 'u_shape_3') {
                        const extra = winderVal === 3 ? 4 : (winderVal === 2 ? 2 : 0);
                        let f1 = parseInt(document.getElementById('f1_steps').value) || 1;
                        let f2 = parseInt(document.getElementById('f2_steps').value) || 1;
                        let f3 = n - f1 - f2 - extra;
                        if (f3 < 1) { f2 = Math.max(1, f2 - (1 - f3)); document.getElementById('f2_steps').value = f2; f3 = Math.max(1, n - f1 - f2 - extra); }
                        document.getElementById('f3_steps').value = f3;
                      } else if (currentType === 'l_shape') {
                        const extra = winderVal === 3 ? 2 : (winderVal === 2 ? 1 : 0);
                        let l1 = parseInt(document.getElementById('l1_steps').value) || 1;
                        let l2 = n - l1 - extra;
                        if (l2 < 1) { l1 = Math.max(1, n - extra - 1); document.getElementById('l1_steps').value = l1; l2 = 1; }
                        document.getElementById('l2_steps').value = l2;
                      }
                    }
                    renderRealtimePlan();
                    saveCurrentFormState();
                  }

                  function onCustomSplit3(changed) {
                    const n = parseInt(document.getElementById('total_steps').value) || 21;
                    const winderVal = getWinderVal();
                    const extra = winderVal === 3 ? 4 : (winderVal === 2 ? 2 : 0);
                    let f1 = parseInt(document.getElementById('f1_steps').value) || 1;
                    let f2 = parseInt(document.getElementById('f2_steps').value) || 1;
                    let f3 = parseInt(document.getElementById('f3_steps').value) || 1;
                    if (changed === 1) {
                      if (f1 + f2 + extra >= n) { f1 = Math.max(1, n - f2 - extra - 1); document.getElementById('f1_steps').value = f1; }
                      document.getElementById('f3_steps').value = Math.max(1, n - f1 - f2 - extra);
                    } else if (changed === 2) {
                      if (f2 + extra >= n - 1) { f2 = Math.max(1, n - extra - 2); document.getElementById('f2_steps').value = f2; }
                      const rem = n - f2 - extra;
                      document.getElementById('f1_steps').value = Math.max(1, Math.floor(rem / 2));
                      document.getElementById('f3_steps').value = Math.max(1, rem - Math.floor(rem / 2));
                    } else if (changed === 3) {
                      if (f3 + f2 + extra >= n) { f3 = Math.max(1, n - f2 - extra - 1); document.getElementById('f3_steps').value = f3; }
                      document.getElementById('f1_steps').value = Math.max(1, n - f2 - f3 - extra);
                    }
                    renderRealtimePlan();
                    saveCurrentFormState();
                  }

                  function onCustomSplit2(changed) {
                    const n = parseInt(document.getElementById('total_steps').value) || 21;
                    const winderVal = getWinderVal();
                    const extra = winderVal === 3 ? 2 : (winderVal === 2 ? 1 : 0);
                    if (changed === 1) {
                      let l1 = parseInt(document.getElementById('l1_steps').value) || 1;
                      if (l1 + extra >= n) { l1 = Math.max(1, n - extra - 1); document.getElementById('l1_steps').value = l1; }
                      document.getElementById('l2_steps').value = Math.max(1, n - l1 - extra);
                    } else if (changed === 2) {
                      let l2 = parseInt(document.getElementById('l2_steps').value) || 1;
                      if (l2 + extra >= n) { l2 = Math.max(1, n - extra - 1); document.getElementById('l2_steps').value = l2; }
                      document.getElementById('l1_steps').value = Math.max(1, n - l2 - extra);
                    }
                    renderRealtimePlan();
                    saveCurrentFormState();
                  }

                  function generate() {
                    saveCurrentFormState();
                    const f1 = parseInt(document.getElementById('f1_steps').value) || 8;
                    const f2 = parseInt(document.getElementById('f2_steps').value) || 5;
                    const f3 = parseInt(document.getElementById('f3_steps').value) || 8;
                    const l1 = parseInt(document.getElementById('l1_steps').value) || 11;
                    const l2 = parseInt(document.getElementById('l2_steps').value) || 10;
                    const winder = getWinderVal();

                    const rEnabled = document.getElementById('railing_enabled') ? document.getElementById('railing_enabled').checked : true;
                    const rStyle = document.getElementById('railing_style') ? document.getElementById('railing_style').value : 'glass';
                    const rSide = document.getElementById('railing_side') ? document.getElementById('railing_side').value : 'inner';
                    const rHeight = parseFloat(document.getElementById('railing_height') ? document.getElementById('railing_height').value : 900) || 900;
                    const rProfile = document.getElementById('handrail_profile') ? document.getElementById('handrail_profile').value : 'rect_60_40';

                    const payload = {
                      type: currentType,
                      floor_height: parseFloat(document.getElementById('floor_height').value) || 3600,
                      total_steps: parseInt(document.getElementById('total_steps').value) || 21,
                      flight1_steps: currentType === 'l_shape' ? l1 : f1,
                      flight2_steps: currentType === 'l_shape' ? l2 : f2,
                      flight3_steps: f3,
                      f1_steps: f1,
                      f2_steps: f2,
                      f3_steps: f3,
                      l1_steps: l1,
                      l2_steps: l2,
                      stair_width: parseFloat(document.getElementById('stair_width').value) || 1000,
                      tread_run: parseFloat(document.getElementById('tread_run').value) || 270,
                      slab_thickness: 100.0,
                      winder_landing: winder,
                      railing: {
                        enabled: rEnabled,
                        style: rStyle,
                        side: rSide,
                        height: rHeight,
                        handrail_profile: rProfile,
                        inset: 50.0
                      }
                    };

                    if (window.sketchup && typeof sketchup.generate_stair === 'function') {
                      sketchup.generate_stair(payload);
                    }
                  }

                  function cancel() {
                    sketchup.cancel();
                  }

                  // Execute immediately upon DOM initialization: check localStorage first, then initialSavedData
                  let restoredState = null;
                  try {
                    const local = localStorage.getItem('NAUQ_STAIR_SAVED_DATA');
                    if (local) restoredState = JSON.parse(local);
                  } catch(e) {}

                  if (!restoredState && typeof initialSavedData === 'object' && initialSavedData !== null) {
                    restoredState = initialSavedData;
                  }

                  if (restoredState) {
                    initStairDialog(restoredState);
                  } else {
                    recalc(false);
                  }

                  window.onload = function() {
                    if (restoredState) {
                      initStairDialog(restoredState);
                    }
                    if (window.sketchup) {
                      sketchup.get_initial_data();
                    }
                  };
                </script>
              </body>
              </html>
          HTML
        end
      end
    end
  end
end
