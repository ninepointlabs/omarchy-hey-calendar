# Third-party notices

The bounded-capture process wrapper in `Model.js` (`boundedCaptureCommand` /
`boundedCaptureScript`) and the CLI setup/probe flow in `Model.js` and
`Service.qml` are adapted from 37signals' `37signals.hey` Omarchy plugin
(MIT License, Copyright (c) 2026 37signals LLC), which ships with Omarchy at
`~/.config/omarchy/plugins/37signals.hey`. Reused with attribution under the
terms of that license.

The month-grid date math in `Model.js` (`monthGrid`, `dateKey`, `isoWeek`,
`weekdayOrder`, `stepMonth`, `normalizedWeekStart`) is adapted from Omarchy's
built-in `omarchy.clock` shell plugin (`/usr/share/omarchy/shell/plugins/panels/clock`),
part of Omarchy itself, so the Month and Year views line up exactly with the
native Omarchy calendar popup.
