#!/usr/bin/env python3
import json
from datetime import datetime
import urllib.error
import urllib.request

URL = "https://weather-broker-cdn.api.bbci.co.uk/en/forecast/aggregated/1701668"


def day_label(local_date: str) -> str:
    try:
        return datetime.strptime(local_date, "%Y-%m-%d").strftime("%a, %b %d")
    except ValueError:
        return local_date[:3]


def parse_daily_reports(payload: dict) -> list[dict]:
    daily: dict[str, dict] = {}

    for forecast in payload.get("forecasts", []):
        summary = forecast.get("summary", {})
        reports = summary.get("reports")

        if isinstance(reports, list):
            for report in reports:
                if not isinstance(report, dict):
                    continue
                local_date = report.get("localDate")
                if not local_date or local_date in daily:
                    continue
                daily[local_date] = report
            continue

        single_report = summary.get("report")
        if isinstance(single_report, dict):
            local_date = single_report.get("localDate")
            if local_date and local_date not in daily:
                daily[local_date] = single_report

    return [daily[key] for key in sorted(daily.keys())]


def format_line(report: dict) -> str:
    local_date = str(report.get("localDate") or "")
    label = day_label(local_date)

    max_c = report.get("maxTempC")
    min_c = report.get("minTempC")

    if max_c is None:
        max_c = report.get("temperatureC")
    if min_c is None:
        min_c = max_c

    condition = (
        report.get("enhancedWeatherDescription")
        or report.get("weatherTypeText")
        or report.get("weatherType")
        or "Unknown"
    )

    max_text = "--" if max_c is None else str(max_c)
    min_text = "--" if min_c is None else str(min_c)

    return f"{label}|{max_text}|{min_text}|{condition}"


def main() -> None:
    try:
        with urllib.request.urlopen(URL, timeout=12) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError, ValueError, TypeError):
        print("Unavailable")
        return

    daily_reports = parse_daily_reports(payload)

    if not daily_reports:
        print("Unavailable")
        return

    for report in daily_reports[:7]:
        print(format_line(report))


if __name__ == "__main__":
    main()
