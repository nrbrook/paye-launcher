// PAYE Launcher
// Copyright (C) 2026 Nick Brook
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for details.
//
// PAYE Launcher is not made by, connected with or endorsed by HM Revenue &
// Customs. It contains no HMRC code: it runs the copy of Basic PAYE Tools that
// the user installed from GOV.UK.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
