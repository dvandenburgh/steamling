# libssc patches

Applied on top of v0.4.4, in the order armada builds them. Numbers are never reused.

- `0001-meson-drop-the-mocking-and-tests-subdirs.patch`: from Terra's libssc package
  (terrapkg/packages, commit 23ec8c9aeaad, `anda/lib/libssc/`). The test harness isn't run here.
- `0002-sensor-allow-sample-rate-override.patch`: written by suckbluefrog for their Batocera ARM
  builds. The earliest surviving copy is in MaSieS4Fun's SteamOS ARM port on GitHub, commit
  3548c401e6d2, under `external-and-mods/kernel/vendor/qcom-gyro/src/libssc/` (`0003-` there).
- `0003-sensor-release-the-client-reference-taken-in-open-and-close.patch`: armada.
- `0004-sensor-fail-an-open-that-is-never-confirmed.patch`: armada.
- `0005-sensor-log-a-failed-disable-before-handing-its-error-to-the-task.patch`: armada.
