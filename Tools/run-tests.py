"""Exécute Tests/run.lua dans un interpréteur Lua 5.1 embarqué (paquet PyPI « lupa »).

Usage : python Tools/run-tests.py <racine du projet>
Utilisé par Tools/run-tests.ps1 quand aucun Lua 5.1 / LuaJIT natif n'est installé.
"""
import os
import sys


def main() -> int:
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
    try:
        from lupa.lua51 import LuaRuntime  # lupa >= 2.0 embarque Lua 5.1
    except ImportError as error:
        print(f"lupa (Lua 5.1) indisponible : {error}", file=sys.stderr)
        return 2

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("PGR_TEST_EMBEDDED = true")
    lua.globals().arg = lua.table(root.replace("\\", "/"))
    sys.stdout.flush()
    failures = lua.eval("dofile")(os.path.join(root, "Tests", "run.lua").replace("\\", "/"))
    lua.execute("io.stdout:flush()")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
