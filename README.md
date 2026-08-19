# Kick

**macOS says "the disk is in use." Kick shows you which app, then kicks the disk out safely. Free, open source, one window.**

Kick lists your external disks. It tries the normal macOS eject first. When macOS refuses because a program holds the disk, Kick shows that program, its open paths, and what to do. One button — *Safely Kick* — asks the eligible apps to quit, checks the disk again, and ejects it. A separate last-resort *Stop* button handles the stubborn ones, one polite request at a time.

Made by [nousworks](https://nousworks.co) · [kick.nousworks.co](https://kick.nousworks.co)

## What you get

- Lists mounted external disks: USB, Thunderbolt, SD cards, and multi-volume disks grouped as one device.
- Tries the normal macOS eject first. Clean disks eject right away.
- On "disk in use": shows each process, its name and icon, the app it was started from (for example Terminal), PID, and the open paths.
- **Safely Kick**: asks normal macOS apps that only read from the disk to quit, waits, checks again, then ejects.
- **Show**: brings the owning app to the front so you can close the window, change the folder, or answer a save dialog.
- **Stop** (last resort): for blockers Safely Kick will not close on its own. Kick checks the process identity again and sends one stop request. Never `SIGKILL`.
- Universal binary (Apple Silicon + Intel). macOS 14 Sonoma or later. Signed with Developer ID and notarized by Apple.

## Install

1. Download `Kick-x.y.z.zip` from [kick.nousworks.co](https://kick.nousworks.co) or the [GitHub releases page](https://github.com/ofbakirci/kick/releases).
2. Unzip. Move `Kick.app` to `/Applications`.
3. Open it. The app is notarized by Apple; it opens without warnings.
4. Pick a disk, press **Eject**. If macOS refuses, Kick explains why and offers the next step.

## Safety boundary

Kick never force-unmounts a disk and never sends `SIGKILL`. Everything it does is a request the target can refuse.

**Safely Kick** only asks normal macOS GUI apps to quit, and only when they:

- belong to you,
- hold the disk with read-only files or a current folder,
- are not a shell, terminal, backup tool, sync tool, virtual machine, or macOS system process,
- have a stable process identity (start time and executable path) that Kick re-checks right before it asks.

Everything else is shown with a manual step: "Change the terminal folder", "Wait for the backup", "Stop the virtual machine". Kick enables Safely Kick only after macOS reports a real busy-unmount error. Before each eject it checks the physical attachment identity, media and volume UUIDs, and mount paths again, so a swapped disk is never ejected by mistake.

**Stop** is separate and explicit. You pick one blocker, read what will happen and any risk note, and confirm. Kick then takes a fresh snapshot, confirms the same process still holds the disk, and sends one request: a normal quit request for an app (it can still show a save dialog), or one `SIGTERM` for a command-line tool. If the process ignores it, the disk stays mounted and Kick shows what is still open.

Save your work before you use either button. A normal app can still show its own save prompt when Kick asks it to quit.

## How it works

- Disks: `FileManager.mountedVolumeURLs` plus DiskArbitration and IOKit. Volumes are grouped by the physical `IOMedia` registry entry, so an APFS container and an exFAT partition on the same SSD appear as one disk.
- Eject: `FileManager.unmountVolume(at:options:)` with `allPartitionsAndEjectDisk`. Only `NSFileManagerUnmountBusyError` opens the blocker flow. macOS's own dissenting PID is used as a fallback when `lsof` sees nothing.
- Blockers: `/usr/sbin/lsof +f` on each mount, NUL-delimited fields, with a kernel-call timeout and a bounded wall-clock timeout. Each process is enriched with its executable path, start time, and owning app.
- Quit requests: `NSRunningApplication.terminate()`. Stop requests for tools: one `SIGTERM` after a PID-reuse check.

## Build from source

```sh
git clone https://github.com/ofbakirci/kick
cd kick
swift test --disable-sandbox
./script/build_and_run.sh          # builds dist/Kick.app and opens it
```

Demo modes show the UI states without a real disk:

```sh
./script/build_and_run.sh --demo-ready
./script/build_and_run.sh --demo-blocked      # protected blocker, Stop as last resort
./script/build_and_run.sh --demo-kickable     # eligible app, Safely Kick
```

Add `--demo-light` or `--demo-dark` after a demo mode to set the appearance. `script/build_test_holder.sh` builds a small GUI app that holds a file open, for controlled eject tests on an empty test disk.

## Release

```sh
./script/package_release.sh
```

This builds a universal `dist/release/Kick.app` and `dist/release/Kick-<version>-macOS.zip`. Without a signing identity the bundle is ad hoc signed, for local tests only.

For a public release set a Developer ID Application identity and a `notarytool` keychain profile. The script then signs with Hardened Runtime and a timestamp, submits the ZIP to Apple, staples the ticket, rebuilds the ZIP, and checks the app with Gatekeeper:

```sh
KICK_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
KICK_NOTARY_PROFILE="profile-name" \
  ./script/package_release.sh
```

`KICK_VERSION`, `KICK_BUILD_NUMBER`, and `KICK_ARCHS` (`arm64`, `x86_64`, or both) are optional. Kick is not sandboxed because it runs `lsof`; direct Developer ID distribution supports this design.

## License

MIT. See [LICENSE](LICENSE).
