# InputPlumber patches

Applied on top of v0.84.0. They come from armada's InputPlumber package (`0005-`, `0006-`, `0008-`
and `0009-` there), rebased from 0.83.0. Numbers are never reused.

- `0001-feat-ssc-qualcomm-sensor-core-support.patch`: the FastRPC IMU source, from
  ShadowBlip/InputPlumber pull request 590, commit 3caa7902d92e, with armada's fixes on top. The
  Cargo.lock entry for libloading is added here, so `cargo fetch --locked` works.
- `0002-feat-ssc-gyro-auto-calibration.patch`: armada.
- `0003-feat-ssc-suspend-source-devices-across-system-sleep.patch`: armada. Rebased: 0.84.0 has no
  `ResetEffects` source command, which armada adds in a patch not carried here.
- `0004-feat-ssc-mount-correction-from-the-environment.patch`: armada.
