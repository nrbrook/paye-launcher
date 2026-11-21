# shellcheck shell=bash disable=SC2034 # these values are read by build_runtime.sh
# Pinned sources for the native runtime. Every download is checked against
# its SHA-256. Change a version only together with its hash.
#
# Python and the four Python packages are the same versions that HMRC's
# Basic PAYE Tools 26.1 bundles. OpenSSL is a later patch release of the same
# 3.6 series (security fixes); SQLite is the same version as HMRC's.

PYTHON_VERSION=2.7.16
PYTHON_URL=https://www.python.org/ftp/python/2.7.16/Python-2.7.16.tgz
PYTHON_SHA256=01da813a3600876f03f46db11cc5c408175e99f03af2ba942ef324389a83bad5

OPENSSL_VERSION=3.6.5
OPENSSL_URL=https://github.com/openssl/openssl/releases/download/openssl-3.6.5/openssl-3.6.5.tar.gz
OPENSSL_SHA256=a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98

SQLITE_VERSION=3.51.2
SQLITE_URL=https://www.sqlite.org/2026/sqlite-autoconf-3510200.tar.gz
SQLITE_SHA256=fbd89f866b1403bb66a143065440089dd76100f2238314d92274a082d4f2b7bb

LIBJPEG_TURBO_VERSION=3.2.1
LIBJPEG_TURBO_URL=https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.1/libjpeg-turbo-3.2.1.tar.gz
LIBJPEG_TURBO_SHA256=c27ad72a68da151177929aa969ae773a2da5ac2af9ce946079314fdac8cece7f

SETUPTOOLS_VERSION=44.1.1  # build tool only, not shipped
SETUPTOOLS_URL=https://files.pythonhosted.org/packages/b2/40/4e00501c204b457f10fe410da0c97537214b2265247bc9a5bc6edd55b9e4/setuptools-44.1.1.zip
SETUPTOOLS_SHA256=c67aa55db532a0dadc4d2e20ba9961cbd3ccc84d544e9029699822542b5a476b

SCANDIR_VERSION=1.10.0
SCANDIR_URL=https://files.pythonhosted.org/packages/df/f5/9c052db7bd54d0cbf1bc0bb6554362bba1012d03e5888950a4f5c5dadc4e/scandir-1.10.0.tar.gz
SCANDIR_SHA256=4d4631f6062e658e9007ab3149a9b914f3548cb38bfb021c64f39a025ce578ae

FOURSUITE_VERSION=1.0.2
FOURSUITE_URL=https://files.pythonhosted.org/packages/9a/5c/4ad2ee5f12028e0b40f3f6487cbdfe977ca8c112ecd88c175bc20de189fd/4Suite-XML-1.0.2.tar.bz2
FOURSUITE_SHA256=5a4546dc1fad9b240a46c1b967fae317857cd2d2689e4226de1647083bf6ac3c

PILLOW_VERSION=6.2.2
PILLOW_URL=https://files.pythonhosted.org/packages/b3/d0/a20d8440b71adfbf133452d4f6e0fe80de2df7c2578c9b498fb812083383/Pillow-6.2.2.tar.gz
PILLOW_SHA256=db9ff0c251ed066d367f53b64827cc9e18ccea001b986d08c265e53625dab950

LXML_VERSION=4.5.2
LXML_URL=https://files.pythonhosted.org/packages/2c/4d/3ec1ea8512a7fbf57f02dee3035e2cce2d63d0e9c0ab8e4e376e01452597/lxml-4.5.2.tar.gz
LXML_SHA256=cdc13a1682b2a6241080745b1953719e7fe0850b40a5c71ca574f090a1391df6
