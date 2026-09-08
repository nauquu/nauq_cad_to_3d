# frozen_string_literal: true

require 'json'

module NAUQ
  module CadTo3D
    # HtmlDialog for plugin settings & presets UI (Balanced 2-column layout, Light mode scrollbar)
    module SettingsDialog
      class << self
        def show
          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            return
          end

          @dialog = UI::HtmlDialog.new(
            dialog_title: 'Settings & Presets',
            preferences_key: 'NAUQ_CAD_TO_3D_Settings_Dialog',
            scrollable: true,
            resizable: true,
            width: 640,
            height: 400,
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
          dialog.add_action_callback('get_initial_data') do |_action_context|
            data = {
              settings: Config.settings,
              presets: Config.presets,
              active_preset: Config.active_preset
            }
            dialog.execute_script("initDialog(#{data.to_json});")
          end

          dialog.add_action_callback('save_settings') do |_action_context, data_hash|
            if data_hash.is_a?(Hash)
              Config.update(data_hash)
              Logger.info('Cập nhật cài đặt thành công.')
              dialog.execute_script("showToast('Đã lưu cài đặt thành công!');")
            end
          end

          dialog.add_action_callback('save_custom_preset') do |_action_context, payload|
            if payload.is_a?(Hash) && payload['name']
              name = payload['name'].to_s.force_encoding('UTF-8').strip
              data = payload['data'] || {}
              if Config.save_preset(name, data)
                Config.update(data)
                res = {
                  presets: Config.presets,
                  active_preset: name
                }
                toast_msg = "Đã lưu cấu hình: #{name}"
                dialog.execute_script("updatePresetsList(#{res.to_json}); showToast(#{toast_msg.to_json});")
              end
            end
          end

          dialog.add_action_callback('delete_custom_preset') do |_action_context, name|
            utf8_name = name.to_s.force_encoding('UTF-8')
            if Config.delete_preset(utf8_name)
              res = {
                presets: Config.presets,
                active_preset: Config.active_preset
              }
              toast_msg = "Đã xóa cấu hình: #{utf8_name}"
              dialog.execute_script("updatePresetsList(#{res.to_json}); showToast(#{toast_msg.to_json});")
            end
          end

          dialog.add_action_callback('reset_settings') do |_action_context|
            Config.reset!
            Config.restore_default_presets!
            data = {
              settings: Config.settings,
              presets: Config.presets,
              active_preset: Config.active_preset
            }
            dialog.execute_script("initDialog(#{data.to_json}); showToast('Đã khôi phục toàn bộ cấu hình mặc định!');")
          end

          dialog.add_action_callback('reload_plugin') do |_action_context|
            success = NAUQ::CadTo3D.reload!
            if success
              dialog.execute_script("showToast('✓ Đã cập nhật (Reload) code plugin thành công!');")
            else
              dialog.execute_script("showToast('Lỗi khi nạp lại plugin!');")
            end
          end

          dialog.add_action_callback('close_dialog') do |_action_context|
            dialog.close
          end
        end

        def html_content
          <<~HTML
            <!DOCTYPE html>
            <html lang="vi">
            <head>
              <meta charset="UTF-8">
              <title>Settings</title>
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
                  padding: 14px;
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
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                }

                .header h2 {
                  font-size: 14px;
                  font-weight: 700;
                  color: var(--text-main);
                }

                .header p {
                  font-size: 11px;
                  color: var(--text-muted);
                  margin-top: 1px;
                }

                .toast {
                  display: none;
                  background-color: #10b981;
                  color: white;
                  font-size: 11px;
                  font-weight: 600;
                  text-align: center;
                  padding: 5px 10px;
                  border-radius: 4px;
                  margin-bottom: 8px;
                  animation: fadeIn 0.2s ease-in-out;
                }

                @keyframes fadeIn {
                  from { opacity: 0; transform: translateY(-4px); }
                  to { opacity: 1; transform: translateY(0); }
                }

                /* Preset Quick-Selector Bar */
                .preset-card {
                  background: #f0fdf4;
                  border: 1px solid #bbf7d0;
                  border-radius: 6px;
                  padding: 7px 10px;
                  margin-bottom: 10px;
                  display: flex;
                  align-items: center;
                  justify-content: space-between;
                  gap: 8px;
                  flex-wrap: wrap;
                }

                .preset-label {
                  display: flex;
                  align-items: center;
                  gap: 5px;
                  font-size: 11px;
                  font-weight: 700;
                  color: #166534;
                }

                .preset-controls {
                  display: flex;
                  align-items: center;
                  gap: 6px;
                  flex: 1;
                  justify-content: flex-end;
                  min-width: 260px;
                }

                .preset-controls select {
                  background: #ffffff;
                  border: 1px solid #86efac;
                  color: #0f172a;
                  font-weight: 600;
                  padding: 4px 6px;
                  border-radius: 4px;
                  font-size: 11px;
                  flex: 1;
                  max-width: 250px;
                  outline: none;
                }

                .preset-controls select:focus {
                  border-color: #16a34a;
                }

                .btn-preset-save {
                  background: #16a34a;
                  color: #ffffff;
                  border: none;
                  padding: 4px 8px;
                  font-size: 11px;
                  font-weight: 600;
                  border-radius: 4px;
                  cursor: pointer;
                  white-space: nowrap;
                }

                .btn-preset-save:hover {
                  background: #15803d;
                }

                .btn-preset-del {
                  background: #ef4444;
                  color: #ffffff;
                  border: none;
                  padding: 4px 8px;
                  font-size: 11px;
                  font-weight: 600;
                  border-radius: 4px;
                  cursor: pointer;
                  white-space: nowrap;
                  transition: all 0.15s ease;
                }

                .btn-preset-del:hover {
                  background: #dc2626;
                }

                .btn-preset-del.disabled {
                  background: #e2e8f0;
                  color: #94a3b8;
                  cursor: not-allowed;
                }

                .btn-preset-del.disabled:hover {
                  background: #e2e8f0;
                }

                /* Form Layout */
                .sections-grid {
                  display: grid;
                  grid-template-columns: 1fr 1fr;
                  gap: 10px;
                }

                .section {
                  background: var(--card-bg);
                  border: 1px solid var(--border-color);
                  border-radius: 6px;
                  padding: 8px 10px;
                }

                .section-title {
                  font-size: 11px;
                  font-weight: 700;
                  color: var(--text-main);
                  text-transform: uppercase;
                  letter-spacing: 0.4px;
                  margin-bottom: 6px;
                  padding-bottom: 3px;
                  border-bottom: 1px solid #f1f5f9;
                }

                .form-grid {
                  display: grid;
                  grid-template-columns: 1fr 1fr;
                  gap: 6px 8px;
                }

                .form-group {
                  display: flex;
                  flex-direction: column;
                  gap: 2px;
                }

                .form-group.full {
                  grid-column: span 2;
                }

                label {
                  font-size: 11px;
                  font-weight: 600;
                  color: var(--text-muted);
                }

                input, select {
                  background: #ffffff;
                  border: 1px solid var(--border-color);
                  color: var(--text-main);
                  border-radius: 4px;
                  padding: 4px 7px;
                  font-size: 11px;
                  outline: none;
                }

                input:focus, select:focus {
                  border-color: var(--primary-color);
                }

                .actions {
                  display: flex;
                  justify-content: flex-end;
                  gap: 8px;
                  margin-top: 12px;
                }

                button {
                  padding: 5px 12px;
                  border-radius: 4px;
                  border: 1px solid transparent;
                  font-size: 11px;
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

                .btn-reload {
                  background-color: #0284c7;
                  color: #ffffff;
                  border-color: #0369a1;
                }

                .btn-reload:hover {
                  background-color: #0369a1;
                }

                .toast {
                  position: fixed;
                  top: 14px;
                  left: 50%;
                  transform: translateX(-50%);
                  background: #0f172a;
                  color: #f8fafc;
                  padding: 7px 16px;
                  border-radius: 6px;
                  font-size: 11.5px;
                  font-weight: 600;
                  box-shadow: 0 4px 14px rgba(0,0,0,0.25);
                  display: none;
                  z-index: 9999;
                  border-left: 3px solid #22c55e;
                  transition: opacity 0.2s ease;
                }
              </style>
            </head>
            <body>
              <div class="header">
                <div>
                  <h2>Settings &amp; Presets</h2>
                  <p>Cấu hình thông số layer CAD, dung sai và kích thước mặc định</p>
                </div>
              </div>

              <div id="toast" class="toast"></div>

              <!-- Quick Presets Bar -->
              <div class="preset-card">
                <div style="display: flex; gap: 6px; width: 100%; align-items: center; flex-wrap: wrap;">
                  <div class="preset-label" style="font-weight: 700; color: #166534;">Cấu hình:</div>
                  <select id="presetSelect" onchange="onPresetChange(this.value)" style="flex: 2; min-width: 140px; border: 1px solid #86efac; padding: 4px 6px; border-radius: 4px; font-size: 11px;">
                    <!-- Populated dynamically -->
                  </select>
                  <input type="text" id="presetNameInput" placeholder="Đặt tên cấu hình..." style="flex: 2; min-width: 130px; border: 1px solid #86efac; padding: 4px 6px; font-size: 11px; border-radius: 4px; outline: none; background: #ffffff; color: #0f172a;" />
                  <button type="button" class="btn-preset-save" onclick="saveCurrentPreset()" title="Lưu thông số ở bảng dưới thành cấu hình này">Lưu Preset</button>
                  <button type="button" class="btn-preset-del" id="btnDeletePreset" onclick="deleteCurrentPreset()" title="Xóa cấu hình đang chọn">Xóa Preset</button>
                </div>
              </div>

              <form id="settingsForm">
                <div class="sections-grid">
                  <!-- Cot trai: Tuong & Cua so -->
                  <div style="display: flex; flex-direction: column; gap: 10px;">
                    <!-- Tuong Section -->
                    <div class="section">
                      <div class="section-title">Tường (Wall)</div>
                      <div class="form-grid">
                        <div class="form-group">
                          <label>Layer CAD</label>
                          <input type="text" id="wall_layer" name="wall_layer" required>
                        </div>
                        <div class="form-group">
                          <label>Dung sai (mm)</label>
                          <input type="number" id="wall_tolerance" name="wall_tolerance" step="1" required>
                        </div>
                        <div class="form-group">
                          <label>Chiều cao dầm (mm)</label>
                          <input type="number" id="beam_depth" name="beam_depth" step="10" value="400">
                        </div>
                        <div class="form-group" style="justify-content: flex-end; padding-bottom: 2px;">
                          <label style="display: flex; align-items: center; gap: 6px; cursor: pointer; color: var(--text-main); font-weight: 500;">
                            <input type="checkbox" id="deduct_beam" name="deduct_beam" style="width: 14px; height: 14px; cursor: pointer;">
                            Trừ dầm sàn &amp; Tạo sàn trên
                          </label>
                        </div>
                      </div>
                    </div>

                    <!-- Cua so Section -->
                    <div class="section">
                      <div class="section-title">Cửa sổ (Window)</div>
                      <div class="form-grid">
                        <div class="form-group full">
                          <label>Layer CAD</label>
                          <input type="text" id="window_layer" name="window_layer" required>
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- Cot phai: Cua di & Global -->
                  <div style="display: flex; flex-direction: column; gap: 10px;">
                    <!-- Cua di Section -->
                    <div class="section">
                      <div class="section-title">Cửa đi (Door)</div>
                      <div class="form-grid">
                        <div class="form-group">
                          <label>Layer CAD</label>
                          <input type="text" id="door_layer" name="door_layer" required>
                        </div>
                        <div class="form-group">
                          <label>Block CAD</label>
                          <input type="text" id="door_block" name="door_block" required>
                        </div>
                      </div>
                    </div>

                    <!-- Global Section -->
                    <div class="section">
                      <div class="section-title">Khung &amp; Ô kính (Global)</div>
                      <div class="form-grid">
                        <div class="form-group full">
                          <label>Khung bao (mm)</label>
                          <input type="number" id="frame_size" name="frame_size" step="1" required>
                        </div>
                        <div class="form-group full">
                          <label>Phân nhóm Cửa 3D</label>
                          <select id="door_grouping" name="door_grouping" required>
                            <option value="2">Cửa đi và cửa sổ 2 group riêng (Mặc định)</option>
                            <option value="1">Cửa đi và cửa sổ chung 1 group</option>
                            <option value="0">Không tạo group cửa (đặt tự do)</option>
                          </select>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="actions">
                  <button type="button" class="btn-reload" onclick="reloadPlugin()" title="Nạp lại toàn bộ code mới nhất mà không cần mở lại SketchUp">Update Plugin</button>
                  <div style="flex: 1;"></div>
                  <button type="button" class="btn-secondary" onclick="resetForm()">Mặc định</button>
                  <button type="button" class="btn-secondary" onclick="closeForm()">Hủy</button>
                  <button type="submit" class="btn-primary">Lưu Cài Đặt</button>
                </div>
              </form>

              <script>
                let globalPresets = {};
                let currentActivePresetName = '';

                document.addEventListener('DOMContentLoaded', () => {
                  if (window.sketchup) {
                    sketchup.get_initial_data();
                  }
                });

                function initDialog(data) {
                  globalPresets = data.presets || {};
                  currentActivePresetName = data.active_preset || '';
                  renderPresetOptions();
                  if (data.settings) {
                    populateForm(data.settings);
                  }
                }

                function renderPresetOptions() {
                  const selectEl = document.getElementById('presetSelect');
                  selectEl.innerHTML = '';

                  for (const name in globalPresets) {
                    const opt = document.createElement('option');
                    opt.value = name;
                    opt.textContent = name;
                    if (name === currentActivePresetName) {
                      opt.selected = true;
                    }
                    selectEl.appendChild(opt);
                  }

                  document.getElementById('presetNameInput').value = currentActivePresetName;
                  updateDeleteBtnVisibility();
                }

                function updateDeleteBtnVisibility() {
                  const selectEl = document.getElementById('presetSelect');
                  const selectedName = selectEl.value;
                  const btnDel = document.getElementById('btnDeletePreset');
                  if (selectedName) {
                    btnDel.classList.remove('disabled');
                    btnDel.style.opacity = '1';
                    btnDel.title = 'Xóa cấu hình "' + selectedName + '"';
                  } else {
                    btnDel.classList.add('disabled');
                    btnDel.style.opacity = '0.6';
                  }
                }

                function onPresetChange(presetName) {
                  currentActivePresetName = presetName;
                  document.getElementById('presetNameInput').value = presetName;
                  updateDeleteBtnVisibility();

                  const preset = globalPresets[presetName];
                  if (preset && preset.data) {
                    populateForm(preset.data);
                    showToast('Đã áp dụng cấu hình: ' + presetName);
                  }
                }

                function saveCurrentPreset() {
                  const newName = document.getElementById('presetNameInput').value.trim();
                  if (!newName) {
                    showToast('Vui lòng nhập tên cấu hình mẫu!');
                    return;
                  }

                  const currentData = getFormData();
                  const oldName = document.getElementById('presetSelect').value;

                  const isCustomOld = globalPresets[oldName] && globalPresets[oldName].is_custom;
                  if (isCustomOld && oldName !== newName) {
                    if (window.sketchup) {
                      sketchup.delete_custom_preset(oldName);
                    }
                  }

                  if (window.sketchup) {
                    sketchup.save_custom_preset({
                      name: newName,
                      data: currentData
                    });
                  }
                }

                function deleteCurrentPreset() {
                  const selectEl = document.getElementById('presetSelect');
                  const name = selectEl.value;
                  if (!name) return;

                  if (confirm('Bạn có chắc chắn muốn xóa cấu hình "' + name + '" không?')) {
                    if (window.sketchup) {
                      sketchup.delete_custom_preset(name);
                    }
                  }
                }

                function updatePresetsList(res) {
                  globalPresets = res.presets || {};
                  currentActivePresetName = res.active_preset || '';
                  renderPresetOptions();
                }

                function populateForm(data) {
                  for (const key in data) {
                    const el = document.getElementById(key);
                    if (el) {
                      if (el.type === 'checkbox') {
                        el.checked = Boolean(data[key] === true || data[key] === 'true');
                      } else {
                        el.value = data[key];
                      }
                    }
                  }
                }

                function getFormData() {
                  const form = document.getElementById('settingsForm');
                  const formData = new FormData(form);
                  const data = {};
                  formData.forEach((value, key) => {
                    const num = Number(value);
                    data[key] = (isNaN(num) || value.trim() === '') ? value : num;
                  });

                  const deductBeamEl = document.getElementById('deduct_beam');
                  if (deductBeamEl) {
                    data['deduct_beam'] = deductBeamEl.checked;
                  }
                  return data;
                }

                let toastTimer = null;
                function showToast(msg) {
                  let toast = document.getElementById('toast');
                  if (!toast) {
                    toast = document.createElement('div');
                    toast.id = 'toast';
                    toast.className = 'toast';
                    document.body.appendChild(toast);
                  }
                  toast.innerText = msg;
                  toast.style.display = 'block';
                  toast.style.opacity = '1';
                  clearTimeout(toastTimer);
                  toastTimer = setTimeout(() => {
                    toast.style.opacity = '0';
                    setTimeout(() => { toast.style.display = 'none'; }, 200);
                  }, 2500);
                }

                function reloadPlugin() {
                  const btn = document.querySelector('.btn-reload');
                  if (btn) btn.textContent = 'Đang Update...';
                  if (window.sketchup) {
                    sketchup.reload_plugin();
                  }
                  setTimeout(() => {
                    if (btn) btn.textContent = 'Update Plugin';
                  }, 1200);
                }

                document.getElementById('settingsForm').addEventListener('submit', (e) => {
                  e.preventDefault();
                  const data = getFormData();
                  if (window.sketchup) {
                    sketchup.save_settings(data);
                  }

                  const activePresetName = document.getElementById('presetSelect').value;
                  if (globalPresets[activePresetName] && globalPresets[activePresetName].is_custom) {
                    if (window.sketchup) {
                      sketchup.save_custom_preset({
                        name: activePresetName,
                        data: data
                      });
                    }
                  }
                });

                function resetForm() {
                  if (window.sketchup) {
                    sketchup.reset_settings();
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
