"""Run the addon in a fake WoW environment.

Usage:  pip install lupa
        python tests/run.py                    # every tests/t_*.lua and tests/t_*.py
        python tests/run.py tests/t_session.lua

t_*.lua  one player; the script drives the addon directly.
t_*.py   several players in one group (see harness.World); the module's
         main(check) runs the scenario and reports through check(label, ok).
"""
import glob, importlib.util, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from harness import new_runtime  # noqa: E402


def run_lua(path):
    L = new_runtime()
    L.execute(open(path).read())
    lines = list(L.globals().CHAT.values())
    errors = list(L.globals().ERRORS.values())
    return lines, errors


def run_py(path):
    spec = importlib.util.spec_from_file_location(os.path.basename(path)[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    lines = []

    def check(label, ok, detail=""):
        lines.append(("PASS " if ok else "FAIL ") + label + ("" if ok or not detail else ": " + str(detail)))

    world = mod.main(check)
    errors = []
    for name, errs in (world.errors() if world else {}).items():
        errors += [name + ": " + e for e in errs]
    return lines, errors


def run(path):
    lines, errors = (run_py if path.endswith(".py") else run_lua)(path)
    failed = False
    for e in errors:
        print("  ERROR:", e); failed = True
    for c in lines:
        print("  " + c)
        if c.startswith("FAIL"): failed = True
    return not failed


if __name__ == "__main__":
    scripts = sys.argv[1:] or sorted(glob.glob(os.path.join(HERE, "t_*.lua")) + glob.glob(os.path.join(HERE, "t_*.py")))
    ok = True
    for s in scripts:
        print(os.path.basename(s))
        ok = run(s) and ok
    sys.exit(0 if ok else 1)
