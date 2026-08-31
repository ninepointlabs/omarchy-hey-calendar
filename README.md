# HEY Calendar for Omarchy

A native Omarchy bar widget + panel for your HEY calendar and journal —
Today, Week, Month, and Year views, with a day-detail panel for events and
journal entries, all driven by the [HEY CLI](https://hey.com) (`hey`).

Built to match the look, spacing, and interaction patterns of Omarchy's own
`omarchy.clock` calendar popup and the official `37signals.hey` plugin, so it
feels like a stock part of the shell rather than a bolted-on extra.

## Features

- **Bar chip**: today's date, or the next upcoming event when one exists
  (toggle in settings).
- **Four views**: Today (full day detail inline), Week (seven-day agenda),
  Month (grid with ISO week numbers, matching the clock popup), Year (twelve
  compact months).
- **Day detail**: click any day in Week/Month/Year to see its events and
  journal entry. Quick-add and inline-edit events; quick-edit or delete the
  journal entry; "Open in editor" hands a longer journal entry off to
  `$EDITOR` in a floating terminal.
- **Activity pips**: a dot under any day with an event, and a second dot for
  a journal entry, on both the Month and Year grids.
- **Multi-calendar aware**: events are color-dotted by their HEY calendar,
  and the quick-add form lets you pick a destination calendar.
- **Native setup flow**: if the HEY CLI isn't installed or isn't signed in,
  the panel offers the same one-click install/sign-in flow as the HEY email
  plugin.

## Requirements

- Omarchy, with the HEY CLI installed and signed in (`hey auth login`, or
  `omarchy pkg aur add hey-cli` first if it isn't installed — the panel
  offers both from inside the setup screen).

## Install

This repo is the development copy (kept under `~/Projects` per the author's
convention). To try it locally without publishing to GitHub first:

```sh
cp -r ~/Projects/omarchy-hey-calendar ~/.config/omarchy/plugins/tim.hey-calendar
omarchy plugin validate ~/.config/omarchy/plugins/tim.hey-calendar
omarchy plugin enable tim.hey-calendar
```

(A real copy, not a symlink — Omarchy's file watcher doesn't follow a
symlinked plugin directory back into `~/Projects`.)

Once pushed to a git remote, it can be installed the normal way instead:

```sh
omarchy plugin add https://github.com/<you>/omarchy-hey-calendar.git --enable
```

## Settings

- **Show next event in bar** — when on and an event remains today, the bar
  chip shows its time and title instead of the date.
- **Default view** — which of Today/Week/Month/Year opens first.

## Keyboard

- `1` `2` `3` `4` — jump to Today / Week / Month / Year
- Arrow keys — step the current view (month/week/year navigation)
- `t` — jump back to today
- `r` — refresh
- `Esc` — close the day detail, or the panel
- `Tab` / `Shift+Tab` — switch to the next/previous bar panel

## Architecture notes

- `Service.qml` is the shared data layer (one instance per shell, so
  multiple monitors share one set of `hey` calls). It probes the CLI's
  install/auth state the same way `37signals.hey` does, fetches the active
  view's date window (`hey event list` / `hey journal list`, both of which
  accept `--starts-on`/`--ends-on`), and serializes event/journal mutations
  one at a time.
- `Model.js` is pure JS: date/grid math (adapted from `omarchy.clock`),
  `hey` command builders and response parsing, and the same
  bounded-output/timeout process wrapper `37signals.hey` uses so a hung or
  oversized `hey` invocation can't wedge the shell.
- `MonthGrid.qml` renders both the Month view and (in `compact` mode) each
  of the Year view's twelve months, so they can never drift apart visually.
- `DayDetail.qml` is the day's content — used embedded for Today, and as an
  overlay's content everywhere else.

See `THIRD_PARTY_NOTICES.md` for the specific code this plugin adapts from
Omarchy's built-in clock plugin and from `37signals.hey`.

## Known limitations (v1)

- Recurring events show only on the single occurrence the HEY CLI returns
  (it lists a series once, not per-occurrence), with no local RRULE
  expansion.
- Moving an event to a different day isn't exposed in the UI (the CLI
  supports it via `hey event edit <id> <new-date> ...`, just not wired up
  here yet).
- No per-calendar visibility toggle — every calendar's events show, colored
  by calendar.
- Week start follows the system locale; there's no in-panel toggle for it
  (unlike the clock popup's "W" click).
