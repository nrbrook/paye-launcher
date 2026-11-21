"""Teaches Python 2.7's setup.py to read the OpenSSL 3 version number.

OpenSSL 3 defines OPENSSL_VERSION_NUMBER from MAJOR/MINOR/PATCH macros, which
the old regular expression in setup.py cannot read. Without this patch,
setup.py thinks OpenSSL is too old and does not build _hashlib.

Usage: python3 patch_setup_openssl3.py setup.py
"""

import sys

path = sys.argv[1]
with open(path) as f:
    source = f.read()

old = """            except IOError, msg:
                print "IOError while reading opensshv.h:", msg
                pass
"""
new = (
    old
    + """            if openssl_ver == 0:
                # OpenSSL 3 defines the version from MAJOR/MINOR/PATCH macros.
                parts = {}
                for line in open(name, 'r'):
                    m3 = re.match(r'^\\s*#\\s*define\\s+OPENSSL_VERSION_(MAJOR|MINOR|PATCH)\\s+(\\d+)', line)
                    if m3:
                        parts[m3.group(1)] = int(m3.group(2))
                if 'MAJOR' in parts:
                    openssl_ver = (parts['MAJOR'] << 28) | (parts.get('MINOR', 0) << 20) | (parts.get('PATCH', 0) << 4)
"""
)
if source.count(old) != 1:
    sys.exit("setup.py does not have the expected OpenSSL version code")
with open(path, "w") as f:
    f.write(source.replace(old, new))
print("patched")
