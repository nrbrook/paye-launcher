# dmgbuild settings for the PAYE Launcher DMG (used by scripts/package_app.sh).
#
# dmgbuild writes the Finder window layout (.DS_Store) itself, so the build
# does not need Finder or a desktop session.
#
#   dmgbuild -s scripts/dmg_settings.py -D app=<path to .app> \
#     -D readme=<path to Read Me First.txt> -D background=<background.tiff> \
#     "<volume name>" <output.dmg>
#
# The icon positions must agree with scripts/make_dmg_background.swift.
# `defines` is given by dmgbuild when it runs this file.
import os.path

app = defines["app"]  # noqa: F821
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app, (defines["readme"], "Read Me First.txt")]  # noqa: F821
symlinks = {"Applications": "/Applications"}
# Finder always hides ".app". Do not hide it with a flag: the flag is Finder
# information on the signed bundle, and `codesign --verify --strict` refuses it.
hide_extensions = ["Read Me First.txt"]

background = defines["background"]  # noqa: F821
# The frame includes the title bar, and Finder can also show a path bar.
window_rect = ((200, 120), (600, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    app_name: (150, 150),
    "Applications": (450, 150),
    "Read Me First.txt": (300, 290),
}
