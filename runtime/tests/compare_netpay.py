"""Post the same inputs to the HMRC net pay estimator on two servers and compare.

The estimator uses the PAYE, National Insurance and student loan code.
Exits with status 1 if a result differs or too few results are real amounts.

Usage: compare_netpay.py --native-port N --hmrc-port N [--year 2026]
"""

from __future__ import annotations

import argparse
import http.cookiejar
import itertools
import random
import re
import sys
import urllib.parse
import urllib.request

TAX_CODES = [
    "1257L",
    "BR",
    "D0",
    "D1",
    "0T",
    "NT",
    "K475",
    "S1257L",
    "C1257L",
    "SD2",
    "SK100",
    "C0T",
    "1100L",
    "500T",
    "1257M",
    "1257N",
]
NI_LETTERS = ["A", "B", "C", "H", "J", "M", "Z", "F", "I", "L", "S", "V", "X", "D", "E", "K", "N"]
PAY = [
    "0",
    "1",
    "5000",
    "6500",
    "12570",
    "12571",
    "25000",
    "50270",
    "50271",
    "60000",
    "75000.33",
    "100000",
    "125140",
    "200000.55",
]
PERIODS = ["W1", "W2", "W4", "M1", "M3", "M6", "MA"]
RESULT = re.compile(r"Estimated net pay is\s*&pound;\s*[\d,]+\.\d\d")


def cases() -> list[tuple[str, str, str, str]]:
    result = [(tc, "A", pay, "M1") for tc, pay in itertools.product(TAX_CODES, PAY)]
    result += [("1257L", ni, pay, "W1") for ni, pay in itertools.product(NI_LETTERS, PAY)]
    result += [("1257L", "A", pay, period) for period, pay in itertools.product(PERIODS, PAY)]
    rnd = random.Random(20261121)  # fixed seed: the same cases every run
    result += [
        (rnd.choice(TAX_CODES), rnd.choice(NI_LETTERS), rnd.choice(PAY), rnd.choice(PERIODS)) for _ in range(250)
    ]
    return result


def estimate(port: int, year: str, fields: dict[str, str]) -> str:
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), urllib.request.ProxyHandler({}))
    url = f"http://127.0.0.1:{port}/calculators/netpayestimator/{year}/"
    with opener.open(url, timeout=60) as response:
        html = response.read().decode("utf-8", "replace")
    token = re.search(r"name=['\"]csrfmiddlewaretoken['\"] value=['\"]([^'\"]+)", html)
    data = dict(fields, csrfmiddlewaretoken=token.group(1) if token else "")
    request = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(), headers={"Referer": url})
    with opener.open(request, timeout=60) as response:
        html = response.read().decode("utf-8", "replace")
    body = re.search(r'<div id="content"(.*?)<div id="footer"', html, re.S)
    text = re.sub(r"<script.*?</script>|<[^>]+>", " ", body.group(1) if body else html, flags=re.S)
    return re.sub(r"\s+", " ", text.replace(f":{port}", ":PORT")).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-port", type=int, required=True)
    parser.add_argument("--hmrc-port", type=int, required=True)
    parser.add_argument("--year", default="2026")
    parser.add_argument("--min-amounts", type=int, default=400)
    args = parser.parse_args()

    same = different = amounts = 0
    for tax_code, ni_letter, pay, period in cases():
        fields = {
            "name": "Test Person",
            "taxcode": tax_code,
            "niletter": ni_letter,
            "estimatedannualpay": pay,
            "paymethod": period,
            "submit": "Next",
        }
        native = estimate(args.native_port, args.year, fields)
        hmrc = estimate(args.hmrc_port, args.year, fields)
        if native == hmrc:
            same += 1
        else:
            different += 1
            print(f"DIFFERENT {tax_code} {ni_letter} {pay} {period}\n  native: {native[:300]}\n  hmrc:   {hmrc[:300]}")
        amounts += bool(RESULT.search(native))
    print(f"Net pay {args.year}: {same + different} cases, identical {same}, different {different}, amounts {amounts}")
    if amounts < args.min_amounts:
        print(f"FAIL: only {amounts} results were amounts (expected at least {args.min_amounts})")
        return 1
    return 1 if different else 0


if __name__ == "__main__":
    sys.exit(main())
