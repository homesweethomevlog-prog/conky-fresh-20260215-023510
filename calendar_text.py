#!/usr/bin/env python3
import calendar
from datetime import date

today = date.today()
year = today.year
month = today.month

headers = "Su Mo Tu We Th Fr Sa"
weeks = calendar.Calendar(firstweekday=6).monthdayscalendar(year, month)

lines = [f"{calendar.month_name[month]} {year}", headers]

for week in weeks:
	cells = []
	for day in week:
		if day == 0:
			cells.append("  ")
		elif day == today.day:
			cells.append(f"${{color F7C873}}{day:>2}${{color}}")
		else:
			cells.append(f"{day:>2}")
	lines.append(" ".join(cells).rstrip())

centered_lines = [f"${{alignc}}{line}" for line in lines]
print("\n".join(centered_lines), end="")
