# LidKeeper

Keep your Mac running with the lid closed — screen off, system on.

The opposite of [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704): system sleep is blocked (`-i -m -s`) but display sleep is still allowed. When the lid closes, `pmset displaysleepnow` fires every second to force the screen off while the system stays awake.

## Requirements

- Apple Silicon Mac (M1–M4)
- macOS 14 Sonoma or later

## Build & Install

```bash
chmod +x build.sh
./build.sh
```

This compiles the Swift source, creates `LidKeeper.app` in `/Applications`, and ad-hoc signs it.

## Launch at Boot (optional)

```bash
cp com.lidkeeper.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.lidkeeper.plist
```

Or add `/Applications/LidKeeper.app` to Login Items in System Settings → General → Login Items.

## Usage

- **Green circle** in the menu bar = active. Close the lid and the display will turn off while the system keeps running.
- **Gray circle** = disabled. Normal macOS sleep behavior.
- Right-click the icon to toggle on/off or quit.

When active, `pmset displaysleep` is set to `0` (never). When disabled, it restores to `30` minutes.

## License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
