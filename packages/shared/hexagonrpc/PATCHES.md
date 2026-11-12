# hexagonrpc patches

Applied on top of v0.5.0. All five come from armada's hexagonrpc package, refreshed so they apply
without fuzz. Numbers are never reused.

- `0001-hexagonrpcd-add-sns-registry-reverse-interface.patch`: written by suckbluefrog for their
  Batocera ARM builds, which are gone now. The earliest surviving copy is in MaSieS4Fun's SteamOS
  ARM port on GitHub, commit 3548c401e6d2, under
  `external-and-mods/kernel/vendor/qcom-gyro/src/hexagonrpc/` (`0002-` there).
- `0002-hexagonrpcd-add-writable-hexagonfs.patch`: same source, `0005-` there.
- `0003-hexagonrpcd-support-writable-sensor-registry.patch`: same source, `0006-` there.
- `0004-hexagonrpcd-support-large-and-extended-callbacks.patch`: same source, `0007-` there.
- `0005-hexagonrpcd-answer-a-request-it-cannot-serve.patch`:
  https://github.com/kettlelinux/kettlelinux/blob/05b375895bbb1507ff7c77d755a4d005b47af617/packages/hexagonrpc/0005-hexagonrpcd-answer-a-request-it-cannot-serve.patch
