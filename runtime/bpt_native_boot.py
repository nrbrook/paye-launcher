# -*- coding: utf-8 -*-
"""
Native (arm64) start-up for the installed HMRC Basic PAYE Tools server.

This file contains no HMRC code. It does the same work as the py2app
start-up files (__boot__.py and site.py) in HMRC's rti.app, but it runs
on a native Python 2.7.16 with native builds of the open-source C
extension packages (4Suite-XML, Pillow, lxml, scandir).

The HMRC .pyc files are loaded unchanged from the installed app. Nothing
in the installed app is written or modified.

Usage:
    python2.7 -S -E -B bpt_native_boot.py <manage.py command> [args...]

Environment:
    BPT_RTI_APP   path of rti.app (default: inside /Applications/Basic PAYE Tools.app)
"""
import os
import sys


def _paths(rti_app):
    resources = os.path.join(rti_app, "Contents", "Resources")
    hmrc_lib = os.path.join(resources, "lib", "python2.7")
    native_lib = os.path.join(sys.prefix, "lib", "python2.7")
    return resources, hmrc_lib, native_lib


def _set_sys_path(hmrc_lib, native_lib):
    # Order:
    #  1. native builds of the open-source packages that have C extensions;
    #     these shadow the x86_64 copies in the HMRC app.
    #  2. native lib-dynload (the standard C modules).
    #  3. the HMRC pure-Python code, exactly as py2app lays it out
    #     (HMRC's x86_64 lib-dynload is left out).
    #  4. the native standard library, only as a fallback.
    overlay = os.path.join(native_lib, "bpt-native")
    sys.path[:] = [
        overlay,
        os.path.join(native_lib, "lib-dynload"),
        hmrc_lib,
        os.path.join(hmrc_lib, "plat-darwin"),
        os.path.join(hmrc_lib, "plat-mac"),
        os.path.join(hmrc_lib, "plat-mac", "lib-scriptpackages"),
        os.path.join(hmrc_lib, "lib-tk"),
        os.path.join(hmrc_lib, "lib-old"),
        os.path.join(hmrc_lib, "site-packages.zip"),
        os.path.join(hmrc_lib, "site-packages"),
        native_lib,
        os.path.join(native_lib, "plat-darwin"),
        os.path.join(native_lib, "plat-mac"),
    ]


def _site_like_py2app():
    # py2app's site.py: absolute __file__ for loaded modules, optional
    # sitecustomize, and no sys.setdefaultencoding afterwards.
    for module in list(sys.modules.values()):
        f = getattr(module, "__file__", None)
        if isinstance(f, basestring) and not os.path.isabs(f):
            module.__file__ = os.path.abspath(f)
    try:  # noqa: SIM105 - contextlib.suppress does not exist in Python 2.7
        import sitecustomize  # noqa: F401
    except ImportError:
        pass
    if hasattr(sys, "setdefaultencoding"):
        del sys.setdefaultencoding


def _disable_linecache():
    # Same as HMRC's __boot__.py.
    import linecache

    def fake_getline(*args, **kwargs):
        return ""

    linecache.orig_getline = linecache.getline
    linecache.getline = fake_getline


def main():
    rti_app = os.environ.get("BPT_RTI_APP") or \
        "/Applications/Basic PAYE Tools.app/Contents/Helpers/rti.app"
    rti_app = os.path.abspath(rti_app)
    resources, hmrc_lib, native_lib = _paths(rti_app)
    if not os.path.isfile(os.path.join(resources, "manage.py")):
        sys.stderr.write("Basic PAYE Tools server not found at %s\n" % rti_app)
        sys.exit(2)

    # The same environment that the py2app bootstrap gives the HMRC code.
    os.environ["RESOURCEPATH"] = resources
    os.environ["EXECUTABLEPATH"] = os.path.join(rti_app, "Contents", "MacOS", "rti")
    os.environ["ARGVZERO"] = os.environ["EXECUTABLEPATH"]
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    os.environ.setdefault("PYTHONUNBUFFERED", "1")
    sys.dont_write_bytecode = True

    _set_sys_path(hmrc_lib, native_lib)
    _site_like_py2app()

    sys.frozen = "macosx_app"
    sys.prefix = sys.exec_prefix = resources
    os.chdir(resources)
    _disable_linecache()

    script = os.path.join(resources, "manage.py")
    sys.argv = [script] + sys.argv[1:]
    with open(script, "rU") as fp:
        source = fp.read() + "\n"

    main_globals = sys.modules["__main__"].__dict__
    for name in list(main_globals):
        if name not in ("__builtins__", "__name__", "__doc__", "__package__"):
            del main_globals[name]
    main_globals["__file__"] = script
    exec(compile(source, script, "exec"), main_globals, main_globals)


if __name__ == "__main__":
    main()
