# PowerShell script to package Trimble-compliant .rbz extension for SketchUp
# Output: nauq_cad_to_3d.rbz (Root contains nauq_cad_to_3d.rb and nauq_cad_to_3d/ directory)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$rbzFile = "nauq_cad_to_3d.rbz"
$mainRb = "nauq_cad_to_3d.rb"
$changelogFile = "CHANGELOG.md"

if (Test-Path $rbzFile) {
    Remove-Item -Path $rbzFile -Force
}

# Read version from code and CHANGELOG
$codeVersion = (Get-Content $mainRb | Select-String "PLUGIN_VERSION\s*=\s*'([^']+)'").Matches.Groups[1].Value
if (-not $codeVersion) {
    $codeVersion = "1.9.0"
}

Write-Host ""
Write-Host "Building Trimble-compliant nauq_cad_to_3d.rbz (v$codeVersion)..." -ForegroundColor Cyan

python -c @"
import os
import zipfile

script_dir = r'$scriptDir'
rbz_path = os.path.join(script_dir, 'nauq_cad_to_3d.rbz')

root_loader = '''# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module NAUQ
  module CadTo3D
    unless file_loaded?(__FILE__)
      # NOTE: Extension Warehouse encrypts .rb files into .rbe, so the
      # registration path MUST omit the .rb file extension.
      ex = SketchupExtension.new('NAUQ CAD to 3D', 'nauq_cad_to_3d/nauq_cad_to_3d')
      ex.description = 'Tu dong chuyen doi ban ve kien truc 2D CAD DWG thanh mo hinh SketchUp 3D.'
      ex.version     = '$codeVersion'
      ex.copyright   = 'NAUQ Architecture'
      ex.creator     = 'VuQuan'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
'''

with open(os.path.join(script_dir, 'nauq_cad_to_3d.rb'), 'r', encoding='utf-8') as f:
    main_content = f.read()

if os.path.exists(rbz_path):
    os.remove(rbz_path)

with zipfile.ZipFile(rbz_path, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('nauq_cad_to_3d.rb', root_loader)
    z.writestr('nauq_cad_to_3d/nauq_cad_to_3d.rb', main_content)
    
    modules = ['core', 'import', 'wall', 'opening', 'door', 'window', 'stair', 'library', 'ui']
    for mod in modules:
        mod_dir = os.path.join(script_dir, mod)
        if os.path.exists(mod_dir):
            for root, _, files in os.walk(mod_dir):
                for file in files:
                    if file.endswith(('.rb', '.json', '.html', '.css', '.js', '.png', '.svg')):
                        full_path = os.path.join(root, file)
                        rel_path = os.path.relpath(full_path, script_dir)
                        arcname = 'nauq_cad_to_3d/' + rel_path.replace('\\\\', '/')
                        z.write(full_path, arcname)

size_kb = round(os.path.getsize(rbz_path) / 1024.0, 2)
print(f'Success! Created Trimble-compliant nauq_cad_to_3d.rbz (Size: {size_kb} KB)')

# Auto-sync to local SketchUp installed plugins directory for instant live reload
appdata = os.environ.get('APPDATA', '')
for ver in ['SketchUp 2026', 'SketchUp 2025', 'SketchUp 2024', 'SketchUp 2023', 'SketchUp 2022', 'SketchUp 2021', 'SketchUp 2017']:
    plugins_dir = os.path.join(appdata, 'SketchUp', ver, 'SketchUp', 'Plugins')
    if os.path.exists(plugins_dir):
        # 1. Root extension loader
        try:
            with open(os.path.join(plugins_dir, 'nauq_cad_to_3d.rb'), 'w', encoding='utf-8') as rf:
                rf.write(root_loader)
        except Exception:
            pass

        # 2. Package directory
        target_dir = os.path.join(plugins_dir, 'nauq_cad_to_3d')
        for mod in modules:
            src_dir = os.path.join(script_dir, mod)
            dst_dir = os.path.join(target_dir, mod)
            if os.path.exists(src_dir):
                os.makedirs(dst_dir, exist_ok=True)
                for f in os.listdir(src_dir):
                    if f.endswith(('.rb', '.json', '.html', '.css', '.js', '.png', '.svg')):
                        try:
                            with open(os.path.join(src_dir, f), 'r', encoding='utf-8') as sf:
                                content = sf.read()
                            with open(os.path.join(dst_dir, f), 'w', encoding='utf-8') as df:
                                df.write(content)
                        except Exception:
                            pass
        try:
            with open(os.path.join(script_dir, 'nauq_cad_to_3d.rb'), 'r', encoding='utf-8') as sf:
                content = sf.read()
            with open(os.path.join(target_dir, 'nauq_cad_to_3d.rb'), 'w', encoding='utf-8') as df:
                df.write(content)
        except Exception:
            pass
"@
