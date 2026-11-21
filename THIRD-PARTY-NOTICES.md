# Third-party notices

PAYE Launcher is licensed under the GNU General Public License version 3
(see `LICENSE`). The download also contains the open-source components below,
each under its own license. The full license texts are inside the app at
`Contents/Resources/runtime/licenses/`.

| Component | Version | License | Use |
|---|---|---|---|
| Python | 2.7.16 | PSF License | Built-in runtime |
| pyenv patches for Python on Apple Silicon | from pyenv | MIT | Build of the built-in runtime |
| OpenSSL | 3.6.5 | Apache License 2.0 | HTTPS in the built-in runtime |
| SQLite | 3.51.2 | Public domain | Database in the built-in runtime |
| libjpeg-turbo | 3.2.1 | IJG License, BSD-3-Clause, zlib | JPEG images (Pillow) |
| 4Suite-XML | 1.0.2 | 4Suite License (Apache 1.1 style) | XML (used by Basic PAYE Tools) |
| Pillow | 6.2.2 | HPND (PIL license) | Images |
| lxml | 4.5.2 | BSD-3-Clause (and others, see its LICENSES.txt) | XML |
| scandir | 1.10.0 | BSD-3-Clause | File system |

The built-in runtime also uses libraries that are part of macOS (libxml2,
libxslt, zlib, libffi).

## Not included: HMRC software

PAYE Launcher contains **no** HMRC code, data, logos or other material.
Basic PAYE Tools is Crown copyright software of HM Revenue & Customs. Users
download and install it from GOV.UK. PAYE Launcher runs that installed copy.

"HMRC" and "Basic PAYE Tools" are used only to describe what this software
works with. PAYE Launcher is not made by, connected with or endorsed by HMRC.
