# frozen_string_literal: true

module NAUQ
  module CadTo3D
    # HtmlDialog for displaying Error Reports (Light mode, clean, no gradients, no icon spam)
    module ReportDialog
      class << self
        def show(log_entries = Logger.warnings_and_errors)
          if log_entries.empty?
            Logger.info('Không phát hiện lỗi hoặc cảnh báo nào.')
            return
          end

          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            return
          end

          @dialog = UI::HtmlDialog.new(
            dialog_title: 'NAUQ CAD TO 3D REPORT',
            preferences_key: 'NAUQ_CAD_TO_3D_Report_Dialog',
            scrollable: true,
            resizable: true,
            width: 440,
            height: 520,
            left: 250,
            top: 200,
            style: UI::HtmlDialog::STYLE_DIALOG
          )

          @dialog.set_html(html_content(log_entries))
          attach_callbacks(@dialog, log_entries)
          @dialog.show
        end

        def close
          @dialog&.close
        end

        # Zoom camera to error position in SketchUp view
        def zoom_to_error(entry)
          model = Sketchup.active_model
          return unless model

          pos = entry[:position]
          entity = entry[:entity]

          if pos
            view = model.active_view
            eye = Geom::Point3d.new(pos.x + 100, pos.y - 100, pos.z + 100)
            target = pos
            up = Geom::Vector3d.new(0, 0, 1)

            view.camera.set(eye, target, up)
            model.selection.clear
            model.selection.add(entity) if entity && entity.valid?
            view.invalidate
          elsif entity && entity.valid?
            model.selection.clear
            model.selection.add(entity)
            model.active_view.zoom(entity)
          end
        end

        private

        # Escape a plain-text string before interpolating it into HTML
        # (matches CGI.escapeHTML behavior without depending on the cgi stdlib)
        def escape_html(str)
          str.to_s
             .gsub('&', '&amp;')
             .gsub('<', '&lt;')
             .gsub('>', '&gt;')
             .gsub('"', '&quot;')
             .gsub("'", '&#39;')
        end

        def attach_callbacks(dialog, log_entries)
          dialog.add_action_callback('zoom_to_id') do |_context, entry_id|
            entry = log_entries.find { |e| e[:id].to_i == entry_id.to_i }
            zoom_to_error(entry) if entry
          end

          dialog.add_action_callback('close_report') do |_context|
            dialog.close
          end
        end

        def html_content(log_entries)
          items_html = log_entries.map do |entry|
            level_class = entry[:level] == :error ? 'badge-error' : 'badge-warning'
            level_text = entry[:level] == :error ? 'Lỗi' : 'Cảnh báo'
            has_pos = entry[:position] || (entry[:entity] && entry[:entity].valid?)

            <<~ITEM
              <div class="report-card">
                <div class="card-header">
                  <span class="badge #{level_class}">#{level_text}</span>
                  <span class="timestamp">#{entry[:timestamp].strftime('%H:%M:%S')}</span>
                </div>
                <div class="card-body">
                  #{escape_html(entry[:message])}
                </div>
                #{has_pos ? "<div class='card-actions'><button onclick='zoomTo(#{entry[:id]})'>[Xem trên bản vẽ]</button></div>" : ''}
              </div>
            ITEM
          end.join("\n")

          <<~HTML
            <!DOCTYPE html>
            <html lang="vi">
            <head>
              <meta charset="UTF-8">
              <title>Báo cáo NAUQ CAD TO 3D</title>
              <style>
                :root {
                  --bg: #f8fafc;
                  --card-bg: #ffffff;
                  --text: #0f172a;
                  --muted: #64748b;
                  --border: #cbd5e1;
                  --warn-bg: #fef3c7;
                  --warn-text: #92400e;
                  --err-bg: #fee2e2;
                  --err-text: #991b1b;
                  --btn-bg: #059669;
                  --btn-hover: #047857;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                  background: var(--bg);
                  color: var(--text);
                  padding: 16px;
                  font-size: 13px;
                }
                /* Light mode scrollbar */
                ::-webkit-scrollbar {
                  width: 6px;
                  height: 6px;
                }
                ::-webkit-scrollbar-track {
                  background: #f1f5f9;
                }
                ::-webkit-scrollbar-thumb {
                  background: #cbd5e1;
                  border-radius: 3px;
                }
                ::-webkit-scrollbar-thumb:hover {
                  background: #94a3b8;
                }
                .header {
                  padding-bottom: 12px;
                  margin-bottom: 16px;
                  border-bottom: 1px solid var(--border);
                }
                .header h2 {
                  color: var(--text);
                  font-size: 15px;
                  font-weight: 700;
                }
                .header p {
                  font-size: 12px;
                  color: var(--muted);
                  margin-top: 2px;
                }
                .report-card {
                  background: var(--card-bg);
                  border: 1px solid var(--border);
                  border-radius: 4px;
                  padding: 12px;
                  margin-bottom: 10px;
                }
                .card-header {
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                  margin-bottom: 6px;
                }
                .badge {
                  padding: 2px 6px;
                  border-radius: 3px;
                  font-size: 10px;
                  font-weight: 700;
                  text-transform: uppercase;
                }
                .badge-warning { background: var(--warn-bg); color: var(--warn-text); }
                .badge-error { background: var(--err-bg); color: var(--err-text); }
                .timestamp { font-size: 10px; color: var(--muted); }
                .card-body { font-size: 12px; color: var(--text); line-height: 1.4; }
                .card-actions { margin-top: 8px; text-align: right; }
                button {
                  background: var(--btn-bg);
                  color: #fff;
                  border: none;
                  padding: 5px 10px;
                  border-radius: 3px;
                  font-size: 11px;
                  font-weight: 600;
                  cursor: pointer;
                }
                button:hover { background: var(--btn-hover); }
              </style>
            </head>
            <body>
              <div class="header">
                <h2>CAD TO 3D REPORT</h2>
                <p>Báo cáo cảnh báo và vị trí lỗi</p>
              </div>
              <div class="report-list">
                #{items_html}
              </div>
              <script>
                function zoomTo(id) {
                  if (window.sketchup) {
                    sketchup.zoom_to_id(id);
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
