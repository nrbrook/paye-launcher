# -*- coding: utf-8 -*-
"""Prints IRmarks for synthetic RTI documents (no real data).

Runs inside "rti shell" (Python 2.7) on either runtime:
    echo "execfile('irmark_probe.py')" | rti shell
The output of the two runtimes must be identical.
"""
from __future__ import print_function

import datetime
import decimal
import hashlib
import json
import sys
from xml.etree import ElementTree as ET  # noqa: N817
from xml.sax.saxutils import escape

from bptrti_submission.submissions import submission as S  # noqa: N812

NAMES = [u"Smith", u"O'Neill & Sons", u"Zoë Brûlé", u"<Tag>", u"£ sign", u"Lee-Jones"]
TEMPLATE = (
    u"<GovTalkMessage><EnvelopeVersion>2.0</EnvelopeVersion>"
    u"<Header><MessageDetails><Class>HMRC-PAYE-RTI-%s</Class><Qualifier>request</Qualifier>"
    u"<Function>submit</Function></MessageDetails></Header><GovTalkDetails><Keys>"
    u'<Key Type="TaxOfficeNumber">123</Key><Key Type="TaxOfficeReference">A%03d</Key></Keys></GovTalkDetails>'
    u'<Body><IRenvelope><IRheader><Keys><Key Type="TaxOfficeNumber">123</Key></Keys>'
    u"<PeriodEnd>%d-04-05</PeriodEnd><DefaultCurrency>GBP</DefaultCurrency><Sender>Employer</Sender></IRheader>"
    u"<Employee><Name><Fore>%s</Fore><Sur>%s</Sur></Name><Pay>%d.%02d</Pay><Note>  a  b\tc\r\nd </Note>"
    u'<Empty/><Attr x="1" b="&quot;q&quot;" a="2"/></Employee></IRenvelope></Body></GovTalkMessage>'
)

rows = []
marks = 0
for rtitype in ("FPS", "EPS", "EYU", "NVR"):
    for year in (2025, 2026):
        for i, name in enumerate(NAMES):
            doc = TEMPLATE % (rtitype, i, year + 1, escape(name), escape(name[::-1]), 1000 * (i + 1) + i, (i * 37) % 100)
            try:
                node = S.generate_irmarknode(ET.fromstring(doc.encode("utf-8")), year, rtitype)
                node_text = ET.tostring(node)
                marks += 1
            except Exception as error:  # noqa: BLE001 - the error text is part of the comparison
                node_text = "EXC %r" % (error,)
            try:
                full = S.irmark_submissondocument(ET.fromstring(doc.encode("utf-8")), rtitype, year)
                full_text, mark = ET.tostring(full), S.getirmark(full)
            except Exception as error:  # noqa: BLE001
                full_text, mark = "EXC %r" % (error,), ""
            rows.append((rtitype, year, i, node_text, mark, hashlib.sha256(full_text).hexdigest()))

for row in rows:
    print("IRMARK %s %s %d node=%s mark=%s doc_sha256=%s" % row)
print("IRMARK_COUNT", marks)
print("IRMARK_SUMMARY", hashlib.sha256(repr(rows)).hexdigest(), len(rows))
print(
    "MISC",
    json.dumps({"a": 1.1, "b": [1, 2, 3], "c": u"£"}, sort_keys=True),
    decimal.Decimal("1234.565").quantize(decimal.Decimal("0.01"), rounding=decimal.ROUND_HALF_UP),
    "%.2f" % 2.675,
    repr(0.1 + 0.2),
    datetime.date(2026, 4, 6).strftime("%A %d %B %Y"),
    sys.maxunicode,
)
