# frozen_string_literal: true

require 'json'

module NAUQ
  module CadTo3D
    # HtmlDialog for post-import 3D dimensions confirmation with preset quick selection
    module BuildDialog
      class << self
        def show(cad_group = nil, &on_confirm_block)
          @current_cad_group = cad_group
          @on_confirm_callback = on_confirm_block

          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            return
          end

          @dialog = UI::HtmlDialog.new(
            dialog_title: 'Thông số Dựng 3D',
            preferences_key: 'NAUQ_CAD_TO_3D_Build_Dialog',
            scrollable: true,
            resizable: true,
            width: 650,
            height: 510,
            left: 200,
            top: 150,
            style: UI::HtmlDialog::STYLE_DIALOG
          )

          @dialog.set_html(html_content)
          attach_callbacks(@dialog)
          @dialog.show
        end

        def close
          @dialog&.close
        end

        private

        def attach_callbacks(dialog)
          dialog.add_action_callback('get_build_params') do |_action_context|
            settings = Config.settings
            data = {
              wall_height: settings[:wall_height] || 3000.0,
              door_height: settings[:door_height] || 2200.0,
              window_height: settings[:window_height] || 1200.0,
              window_offset: settings[:window_offset] || 900.0,
              has_glass_transom: (settings[:glass_height] || 350.0) > 0,
              glass_height: settings[:glass_height] || 350.0,
              deduct_beam: settings[:deduct_beam] || false,
              beam_depth: settings[:beam_depth] || 400.0,
              presets: Config.presets,
              active_preset: Config.active_preset
            }
            dialog.execute_script("initBuildDialog(#{data.to_json});")
          end

          dialog.add_action_callback('rotate_cad') do |_action_context, angle_deg|
            deg = angle_deg.to_f
            deg = 90.0 if deg == 0.0
            model = Sketchup.active_model
            target = @current_cad_group
            target ||= DWGReader.find_or_create_cad_original_group(model)

            if target && target.valid?
              bounds = target.bounds
              center = bounds.center
              center_pt = Geom::Point3d.new(center.x, center.y, 0)
              rad = deg * Math::PI / 180.0
              rot = Geom::Transformation.rotation(center_pt, Geom::Vector3d.new(0, 0, 1), rad)
              model.start_operation('NAUQ Xoay CAD', true)
              target.transform!(rot)
              model.commit_operation
              model.active_view.invalidate
              Logger.info("Đã xoay bản vẽ CAD #{deg.round}° quanh trục Z.")
            end
          end

          dialog.add_action_callback('confirm_and_build') do |_action_context, data_hash|
            if data_hash.is_a?(Hash)
              has_glass = data_hash['has_glass_transom'] == true || data_hash['has_glass_transom'] == 'true'
              glass_h = has_glass ? (data_hash['glass_height'].to_f) : 0.0
              deduct_beam = data_hash['deduct_beam'] == true || data_hash['deduct_beam'] == 'true'
              beam_d = data_hash['beam_depth'].to_f
              beam_d = 400.0 if beam_d <= 0

              updates = {
                wall_height: data_hash['wall_height'].to_f,
                door_height: data_hash['door_height'].to_f,
                window_height: data_hash['window_height'].to_f,
                window_offset: data_hash['window_offset'].to_f,
                glass_height: glass_h,
                deduct_beam: deduct_beam,
                beam_depth: beam_d
              }

              Config.update(updates)
              Logger.info('Đã xác nhận thông số kích thước 3D.')
            end

            cb = @on_confirm_callback
            @on_confirm_callback = nil
            dialog.close
            cb&.call
          end

          dialog.add_action_callback('close_dialog') do |_action_context|
            @on_confirm_callback = nil
            dialog.close
          end
        end

        def html_content
          <<~HTML
            <!DOCTYPE html>
            <html lang="vi">
            <head>
              <meta charset="UTF-8">
              <title>Thông số Dựng 3D</title>
              <style>
                :root {
                  color-scheme: light;
                  --bg-color: #f8fafc;
                  --card-bg: #ffffff;
                  --border-color: #cbd5e1;
                  --text-main: #0f172a;
                  --text-muted: #64748b;
                  --primary-color: #059669;
                  --primary-hover: #047857;
                  --btn-secondary: #e2e8f0;
                  --btn-secondary-hover: #cbd5e1;
                }

                * { box-sizing: border-box; margin: 0; padding: 0; }

                html, body {
                  color-scheme: light;
                  background-color: var(--bg-color);
                  color: var(--text-main);
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
                  padding: 12px 14px;
                  font-size: 12px;
                  line-height: 1.4;
                }

                /* Custom Light mode scrollbar */
                ::-webkit-scrollbar {
                  width: 7px;
                  height: 7px;
                }
                ::-webkit-scrollbar-button {
                  display: none;
                  width: 0;
                  height: 0;
                }
                ::-webkit-scrollbar-track {
                  background: #f1f5f9;
                }
                ::-webkit-scrollbar-thumb {
                  background: #cbd5e1;
                  border-radius: 4px;
                }
                ::-webkit-scrollbar-thumb:hover {
                  background: #94a3b8;
                }

                .header {
                  padding-bottom: 8px;
                  margin-bottom: 10px;
                  border-bottom: 1px solid var(--border-color);
                }

                .header h2 {
                  font-size: 14px;
                  font-weight: 700;
                  color: var(--text-main);
                  text-transform: uppercase;
                  letter-spacing: 0.3px;
                }

                .header p {
                  font-size: 11px;
                  color: var(--text-muted);
                  margin-top: 1px;
                }

                /* Unified Top Toolbar */
                .top-toolbar {
                  background: #f0fdf4;
                  border: 1px solid #bbf7d0;
                  border-radius: 6px;
                  padding: 6px 12px;
                  margin-bottom: 10px;
                  display: flex;
                  align-items: center;
                  justify-content: space-between;
                  gap: 12px;
                }

                .toolbar-group {
                  display: flex;
                  align-items: center;
                  gap: 8px;
                }

                .toolbar-label {
                  font-size: 11px;
                  font-weight: 700;
                  color: #166534;
                  white-space: nowrap;
                }

                .toolbar-group select {
                  background: #ffffff;
                  border: 1px solid #86efac;
                  color: #0f172a;
                  font-weight: 600;
                  padding: 4px 8px;
                  border-radius: 4px;
                  font-size: 11px;
                  min-width: 200px;
                  outline: none;
                }

                .toolbar-group select:focus {
                  border-color: #16a34a;
                }

                .btn-group {
                  display: flex;
                  gap: 6px;
                }

                .btn-tool {
                  background: #ffffff;
                  color: var(--text-main);
                  border: 1px solid #86efac;
                  border-radius: 4px;
                  padding: 4px 10px;
                  font-size: 11px;
                  font-weight: 600;
                  cursor: pointer;
                  transition: all 0.15s ease;
                }

                .btn-tool:hover {
                  background: #dcfce7;
                  border-color: #16a34a;
                }

                .sections-grid {
                  display: grid;
                  grid-template-columns: 1fr 1fr;
                  gap: 10px;
                }

                .section {
                  background: var(--card-bg);
                  border: 1px solid var(--border-color);
                  border-radius: 6px;
                  padding: 10px 12px;
                  display: flex;
                  flex-direction: column;
                  justify-content: flex-start;
                }

                .section.full-width {
                  grid-column: span 2;
                }

                .section-title {
                  font-size: 11px;
                  font-weight: 700;
                  color: var(--text-main);
                  text-transform: uppercase;
                  letter-spacing: 0.4px;
                  margin-bottom: 8px;
                  padding-bottom: 4px;
                  border-bottom: 1px solid #f1f5f9;
                }

                .form-grid {
                  display: grid;
                  grid-template-columns: 1fr 1fr;
                  gap: 8px;
                }

                .form-group {
                  display: flex;
                  flex-direction: column;
                  gap: 3px;
                }

                .form-group.full {
                  grid-column: span 2;
                }

                label {
                  font-size: 11px;
                  font-weight: 600;
                  color: var(--text-muted);
                }

                input[type="number"], input[type="text"], select {
                  background: #ffffff;
                  border: 1px solid var(--border-color);
                  color: var(--text-main);
                  border-radius: 4px;
                  padding: 5px 8px;
                  font-size: 11.5px;
                  outline: none;
                }

                input:focus, select:focus {
                  border-color: var(--primary-color);
                }

                input:disabled {
                  background: #f1f5f9 !important;
                  color: #94a3b8 !important;
                  opacity: 0.6;
                  cursor: not-allowed;
                }

                .checkbox-row {
                  display: flex;
                  align-items: center;
                  gap: 6px;
                  margin-bottom: 4px;
                }

                .checkbox-row input {
                  width: 14px;
                  height: 14px;
                  cursor: pointer;
                }

                .actions {
                  display: flex;
                  justify-content: flex-end;
                  gap: 8px;
                  margin-top: 10px;
                }

                button {
                  padding: 6px 14px;
                  border-radius: 4px;
                  border: 1px solid transparent;
                  font-size: 11.5px;
                  font-weight: 600;
                  cursor: pointer;
                }

                .btn-primary {
                  background-color: var(--primary-color);
                  color: #ffffff;
                }

                .btn-primary:hover {
                  background-color: var(--primary-hover);
                }

                .btn-secondary {
                  background-color: var(--btn-secondary);
                  color: var(--text-main);
                  border-color: var(--border-color);
                }

                .btn-secondary:hover {
                  background-color: var(--btn-secondary-hover);
                }
              </style>
            </head>
            <body>
              <div class="header">
                <h2>THÔNG SỐ DỰNG 3D</h2>
                <p>Xác nhận kích thước Tường, Dầm sàn, Cửa đi và Cửa sổ trước khi tạo mô hình 3D</p>
              </div>

              <!-- Unified Top Toolbar: Presets & Rotate in 1 Row -->
              <div class="top-toolbar">
                <div class="toolbar-group">
                  <span class="toolbar-label">Cấu hình mẫu:</span>
                  <select id="presetSelect" onchange="onPresetChange(this.value)">
                    <!-- Populated dynamically -->
                  </select>
                </div>
                <div class="toolbar-group">
                  <span class="toolbar-label">Xoay CAD 2D:</span>
                  <div class="btn-group">
                    <button type="button" class="btn-tool" onclick="rotateCad(-90)">-90°</button>
                    <button type="button" class="btn-tool" onclick="rotateCad(90)">+90°</button>
                  </div>
                </div>
              </div>

              <form id="buildForm">
                <div class="sections-grid">
                  <!-- Row 1 Left: Tường & Dầm sàn -->
                  <div class="section">
                    <div class="section-title">Tường &amp; Dầm Sàn</div>
                    <div class="form-grid">
                      <div class="form-group full">
                        <label>Chiều cao tường (mm)</label>
                        <input type="number" id="wall_height" name="wall_height" step="10" required>
                      </div>
                      <div class="form-group full" style="margin-top: 4px;">
                        <div class="checkbox-row">
                          <input type="checkbox" id="deduct_beam" name="deduct_beam" onchange="toggleBeamInput()">
                          <label for="deduct_beam" style="color: var(--text-main); cursor: pointer; font-weight: 600;">Trừ dầm &amp; Tạo sàn trên</label>
                        </div>
                        <label id="beam_depth_label">Chiều cao dầm (mm)</label>
                        <input type="number" id="beam_depth" name="beam_depth" step="10" value="400">
                      </div>
                    </div>
                  </div>

                  <!-- Row 1 Right: Cửa đi & Lanh-tô -->
                  <div class="section">
                    <div class="section-title">Cửa Đi &amp; Lanh-tô</div>
                    <div class="form-grid">
                      <div class="form-group full">
                        <label>Cote lanh-tô / Cửa đi (mm)</label>
                        <input type="number" id="door_height" name="door_height" step="10" placeholder="VD: 2200" oninput="updateCalculatedWindowHeight()" onchange="updateCalculatedWindowHeight()" required>
                      </div>
                      <div class="form-group full" style="margin-top: 4px;">
                        <div class="checkbox-row">
                          <input type="checkbox" id="has_glass_transom" name="has_glass_transom" onchange="toggleGlassInput()">
                          <label for="has_glass_transom" style="color: var(--text-main); cursor: pointer; font-weight: 600;">Ô kính lanh-tô (Transom)</label>
                        </div>
                        <label id="glass_height_label">Chiều cao ô kính (mm)</label>
                        <input type="number" id="glass_height" name="glass_height" step="10">
                      </div>
                    </div>
                  </div>

                  <!-- Row 2 Full-width: Cửa sổ -->
                  <div class="section full-width">
                    <div class="section-title">Cửa Sổ (Window)</div>
                    <div class="form-grid">
                      <div class="form-group">
                        <label>Cote bậu cửa sổ (Offset mm)</label>
                        <input type="number" id="window_offset" name="window_offset" step="10" oninput="updateCalculatedWindowHeight()" onchange="updateCalculatedWindowHeight()" required>
                      </div>
                      <div class="form-group">
                        <label>Chiều cao cửa sổ (Tự tính mm)</label>
                        <input type="number" id="window_height_display" disabled style="background: #f1f5f9; color: var(--primary-color); font-weight: 700;">
                      </div>
                    </div>
                    <div style="font-size: 10px; color: var(--text-muted); margin-top: 6px;">* Chiều cao cửa sổ được tự động tính: Cote lanh-tô (Cửa đi) trừ đi Cote bậu cửa.</div>
                  </div>
                </div>

                <div class="actions">
                  <button type="button" class="btn-secondary" onclick="closeForm()">Hủy</button>
                  <button type="button" class="btn-primary" onclick="confirmAndBuild()">Đồng ý &amp; Dựng 3D</button>
                </div>
              </form>

              <script>
                let globalPresets = {};

                document.addEventListener('DOMContentLoaded', () => {
                  if (window.sketchup) {
                    sketchup.get_build_params();
                  }
                });

                function rotateCad(deg) {
                  if (window.sketchup) {
                    sketchup.rotate_cad(deg);
                  }
                }

                function updateCalculatedWindowHeight() {
                  const topCote = Number(document.getElementById('door_height').value) || 2200;
                  const sillCote = Number(document.getElementById('window_offset').value) || 900;
                  const winH = Math.max(topCote - sillCote, 100);
                  document.getElementById('window_height_display').value = winH;
                }

                function initBuildDialog(data) {
                  globalPresets = data.presets || {};
                  renderPresetOptions(data.active_preset);
                  populateForm(data);
                }

                function renderPresetOptions(activeName) {
                  const selectEl = document.getElementById('presetSelect');
                  selectEl.innerHTML = '';

                  for (const name in globalPresets) {
                    const opt = document.createElement('option');
                    opt.value = name;
                    opt.textContent = name;
                    if (name === activeName) {
                      opt.selected = true;
                    }
                    selectEl.appendChild(opt);
                  }
                }

                function onPresetChange(presetName) {
                  const preset = globalPresets[presetName];
                  if (preset && preset.data) {
                    const d = preset.data;
                    document.getElementById('wall_height').value = d.wall_height || 3000;
                    document.getElementById('door_height').value = d.door_height || 2200;
                    document.getElementById('window_offset').value = d.window_offset || 900;
                    updateCalculatedWindowHeight();

                    const glassH = Number(d.glass_height || 0);
                    document.getElementById('has_glass_transom').checked = (glassH > 0);
                    document.getElementById('glass_height').value = glassH;
                    toggleGlassInput();

                    const deductBeam = !!d.deduct_beam;
                    document.getElementById('deduct_beam').checked = deductBeam;
                    document.getElementById('beam_depth').value = d.beam_depth || 400;
                    toggleBeamInput();
                  }
                }

                function populateForm(data) {
                  document.getElementById('wall_height').value = data.wall_height || 3000;
                  document.getElementById('door_height').value = data.door_height || 2200;
                  document.getElementById('window_offset').value = data.window_offset || 900;
                  updateCalculatedWindowHeight();

                  const hasGlass = !!data.has_glass_transom;
                  document.getElementById('has_glass_transom').checked = hasGlass;
                  document.getElementById('glass_height').value = data.glass_height || 350;
                  toggleGlassInput();

                  const deductBeam = !!data.deduct_beam;
                  document.getElementById('deduct_beam').checked = deductBeam;
                  document.getElementById('beam_depth').value = data.beam_depth || 400;
                  toggleBeamInput();
                }

                function toggleGlassInput() {
                  const checked = document.getElementById('has_glass_transom').checked;
                  const glassInput = document.getElementById('glass_height');
                  const glassLabel = document.getElementById('glass_height_label');

                  glassInput.disabled = !checked;
                  if (glassLabel) glassLabel.style.color = checked ? 'var(--text-muted)' : '#cbd5e1';
                }

                function toggleBeamInput() {
                  const checked = document.getElementById('deduct_beam').checked;
                  const beamInput = document.getElementById('beam_depth');
                  const beamLabel = document.getElementById('beam_depth_label');

                  beamInput.disabled = !checked;
                  if (beamLabel) beamLabel.style.color = checked ? 'var(--text-muted)' : '#cbd5e1';
                }

                function confirmAndBuild() {
                  const wall_height = Number(document.getElementById('wall_height').value);
                  const door_height = Number(document.getElementById('door_height').value);
                  const window_offset = Number(document.getElementById('window_offset').value);
                  const window_height = Math.max(door_height - window_offset, 100);
                  const has_glass_transom = document.getElementById('has_glass_transom').checked;
                  const glass_height = Number(document.getElementById('glass_height').value);
                  const deduct_beam = document.getElementById('deduct_beam').checked;
                  const beam_depth = Number(document.getElementById('beam_depth').value);

                  const data = {
                    wall_height: wall_height,
                    door_height: door_height,
                    window_height: window_height,
                    window_offset: window_offset,
                    has_glass_transom: has_glass_transom,
                    glass_height: glass_height,
                    deduct_beam: deduct_beam,
                    beam_depth: beam_depth
                  };

                  if (window.sketchup) {
                    sketchup.confirm_and_build(data);
                  }
                }

                function closeForm() {
                  if (window.sketchup) {
                    sketchup.close_dialog();
                  }
                }
              </script>
            </body>
            </html>
          HTML
        end
      end
    end
  end
end
