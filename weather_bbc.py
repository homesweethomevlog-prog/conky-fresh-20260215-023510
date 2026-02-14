#!/usr/bin/env python3
import json
import sys
import urllib.error
import urllib.request

URL = "https://weather-broker-cdn.api.bbci.co.uk/en/forecast/aggregated/1701668"


def unavailable() -> None:
    print("Unavailable")


def icon_key_for_condition(text: str) -> str:
    condition = text.lower()

    if "thunder" in condition or "storm" in condition:
        return "storm"
    if "rain" in condition or "shower" in condition or "drizzle" in condition:
        return "rain"
    if "snow" in condition or "sleet" in condition or "blizzard" in condition:
        return "snow"
    if "cloud" in condition or "overcast" in condition:
        return "cloudy"
    if "mist" in condition or "fog" in condition or "haze" in condition:
        return "fog"
    if "clear" in condition or "sun" in condition:
        return "clear"
    return "partly"


try:
    with urllib.request.urlopen(URL, timeout=12) as response:
        payload = json.load(response)

    report = payload["forecasts"][0]["detailed"]["reports"][0]
    temp = report.get("temperatureC")
    description = report.get("enhancedWeatherDescription") or report.get("weatherTypeText") or ""
    humidity = report.get("humidity")
    wind_kph = report.get("windSpeedKph")

    mode = sys.argv[1] if len(sys.argv) > 1 else "summary"

    if mode == "icon":
        print(icon_key_for_condition(description))
    elif mode == "details":
        if humidity is None and wind_kph is None:
            unavailable()
        else:
            humidity_text = f"Humidity: {humidity}%" if humidity is not None else "Humidity: N/A"
            wind_text = f"Wind: {wind_kph} km/h" if wind_kph is not None else "Wind: N/A"
            print(f"{humidity_text}  {wind_text}")
    else:
        if temp is None and not description:
            unavailable()
        elif temp is None:
            print(description)
        elif description:
            print(f"{temp}\u00b0C  {description}")
        else:
            print(f"{temp}\u00b0C")
except (KeyError, IndexError, TypeError, ValueError, urllib.error.URLError, TimeoutError):
    unavailable()
