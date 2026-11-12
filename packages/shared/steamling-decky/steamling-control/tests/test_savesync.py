import unittest
from unittest import mock

from tests.helpers import TempDirCase  # noqa: F401  (puts py_modules on the path)
from steamling_control import savesync

GOOD_ID = "MFZWI3D-BONSGYC-YLTMRWG-C43ENR5-QXGZDMM-FZWI3DP-BONSGYY-LTMRWAD"


class SaveSyncTest(unittest.TestCase):
    def test_without_the_tool_it_reports_not_installed(self):
        with mock.patch.object(savesync, "SYNC", "/nonexistent/steamling-sync"):
            self.assertFalse(savesync.sync_status()["installed"])

    def test_accept_refuses_anything_but_a_device_id(self):
        for bad in ("", "ABC", GOOD_ID.lower(), GOOD_ID + "-X", "../../etc"):
            with self.assertRaises(ValueError):
                savesync.accept_device(bad)

    def test_accept_passes_a_good_id_through(self):
        with mock.patch.object(savesync, "_run", return_value={"on": True}) as run:
            savesync.accept_device(GOOD_ID)
        run.assert_called_once()
        self.assertEqual(run.call_args.args[0], ["accept", GOOD_ID])


if __name__ == "__main__":
    unittest.main()
