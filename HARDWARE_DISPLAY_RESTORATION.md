# Fork patch: Hardware Display mode for Apple VNC

This fork (moosetk/open-screen-sharing) carries one functional patch on top of
[nekohasekai/open-screen-sharing](https://github.com/nekohasekai/open-screen-sharing):
it brings back the View › Resolution › Display choice between **Hardware Display**
(Apple VNC) / **Fixed Resolution** (other servers) and **Dynamic Resolution**.

Fork automation and the upstream update procedure are described in
[`.github/fork/README.md`](.github/fork/README.md).

## What changed upstream

- In v1.0.1 (`78ff8de`) `SessionController` had `usesDynamicResolution`, and
  `wantsVirtualDisplay` was `!isIOS && usesDynamicResolution`. With Hardware Display
  selected the client never sent a virtual display request; the Apple high-performance
  stream was started directly with the connection.
- Commit [`3b8e913`](https://github.com/nekohasekai/open-screen-sharing/commit/3b8e91385c286bb636bf7f2a52a56b8c5eb36dd4)
  ("Fix resolution design", between v1.0.1 and v1.0.3) removed the option. Since then
  `wantsVirtualDisplay` is `!isIOS && (usesHighPerformance || route.remoteProtocol == .rdp)`,
  so every Apple VNC session asks the Mac for a virtual display. The `1.0.2` database
  migration drops the stored `usesDynamicResolution` column.

## What this patch does

Restores the v1.0.1 behaviour on top of current upstream:

- `usesDynamicResolution` in `SessionMemory`, `SessionController` and `Computer`, plus a
  `restore-hardware-display` migration that re-adds the column (default `true`, so
  existing connections keep Dynamic Resolution).
- `wantsVirtualDisplay` requires `usesDynamicResolution`.
- Switching to Hardware Display while connected reconnects, and restarting a dropped
  stream in that mode reconnects, as in v1.0.1.
- HDR stays limited to Dynamic Resolution, as in v1.0.1.
- The menu and popover toggle, and the four strings with their v1.0.1 translations.

Files: `OpenScreenSharing/Session/SessionController.swift`,
`OpenScreenSharing/SessionUI/SessionMenus.swift`, `OpenScreenSharing/Model/Computer.swift`,
`OpenScreenSharing/Model/AppDatabase.swift`, `OpenScreenSharing/Resources/Localizable.xcstrings`.

## What is and is not known

- Known from code: Hardware Display means "do not ask the Mac for a virtual display".
  It is not a separate protocol, and it does not change the normal VNC path.
- Not verified: what macOS Screen Sharing streams when no virtual display is requested.
  User reports for v1.0.1 say the physical screen; the upstream maintainer says Apple VNC
  provides a single virtual display ([issue 6](https://github.com/nekohasekai/open-screen-sharing/issues/6)).
  Only a test against a real Mac settles this for current macOS versions.
- Still unsupported in either mode: choosing among several physical displays.

## Verification checklist (needs a Mac client and a Mac server)

1. Build: the `Fork - Build macOS (unsigned)` workflow artifact, or `make build_macos`.
2. Connect with Apple VNC, open View › Resolution: "Display" section shows
   Hardware Display / Dynamic Resolution; the scale list only appears for Dynamic.
3. Hardware Display: the session reconnects; the picture should match the server's
   physical screen (same windows, menu bar, wallpaper and resolution as the monitor;
   moving a window on the server's local monitor is visible). Resizing the client window
   should not change the server resolution.
4. Dynamic Resolution: resolution follows the window and the scale setting, as upstream.
5. Disconnect and reconnect: the chosen mode is remembered per computer.
6. Standard VNC connections still work and show "Fixed Resolution".
