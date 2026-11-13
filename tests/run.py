"""Run the addon in a fake WoW environment.

Usage:  pip install lupa
        python tests/run.py                 # run every tests/t_*.lua
        python tests/run.py tests/t_session.lua
"""
import glob, os, sys
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)

def run(script_path):
    L = lua51.LuaRuntime()
    L.execute(open(os.path.join(HERE, "wowmock.lua")).read())
    L.globals().ADDON_DIR = ADDON
    L.execute('''
ns = {}
function LoadAddon(dir)
  for _, f in ipairs({"Core.lua","Comm.lua","Circle.lua","UI.lua"}) do
    local fh = io.open(dir .. "/" .. f); local src = fh:read("*a"); fh:close()
    local chunk, err = loadstring(src, f)
    if not chunk then error(err) end
    local ok, e = pcall(chunk, "SummonCircle", ns)
    if not ok then table.insert(ERRORS, "load " .. f .. ": " .. tostring(e)) end
  end
end
''')
    L.execute(open(script_path).read())
    failed = False
    for e in L.globals().ERRORS.values():
        print("  ERROR:", e); failed = True
    for c in L.globals().CHAT.values():
        print("  " + c)
        if c.startswith("FAIL"): failed = True
    return not failed

if __name__ == "__main__":
    scripts = sys.argv[1:] or sorted(glob.glob(os.path.join(HERE, "t_*.lua")))
    ok = True
    for s in scripts:
        print(os.path.basename(s))
        ok = run(s) and ok
    sys.exit(0 if ok else 1)
