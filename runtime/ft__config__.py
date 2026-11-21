# 4Suite-XML 1.0.2 install configuration (same layout as the 4Suite installer output).
NAME = '4Suite-XML'
VERSION = '1.0.2'
FULLNAME = '4Suite-XML-1.0.2'
URL = 'http://4suite.org/'

import sys
if getattr(sys, 'frozen', False):
    # "bundled" installation locations (e.g., py2exe, cx_Freeze, py2app)
    RESOURCEBUNDLE = True
    PYTHONLIBDIR = '/'
    BINDIR = None
    DATADIR = '/Share'
    SYSCONFDIR = None
    LOCALSTATEDIR = None
    LIBDIR = None
    LOCALEDIR = '/Share/Locale'
else:
    import os
    RESOURCEBUNDLE = False
    PYTHONLIBDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + os.sep
    BINDIR = None
    DATADIR = os.path.join(PYTHONLIBDIR, 'Ft', 'Share')
    SYSCONFDIR = None
    LOCALSTATEDIR = None
    LIBDIR = None
    LOCALEDIR = os.path.join(DATADIR, 'Locale')
