import unittest
from unittest import mock

from tests.helpers import TempDirCase  # noqa: F401  (puts py_modules on the path)
from steamling_control import savesync

GOOD_ID = "MFZWI3D-BONSGYC-YLTMRWG-C43ENR5-QXGZDMM-FZWI3DP-BONSGYY-LTMRWAD"


class SaveSyncTest(unittest.TestCase):
    def test_without_the_tool_it_reports_not_installed(self):
        with mock.patch.object(savesync, "SYNC", "/nonexistent/steamling-sync"):
            self.assertFalse(savesync.sync_status()["installed"])

    def _status(self, get):
        with mock.patch.object(savesync, "SYNC", __file__), \
             mock.patch.object(savesync, "ENABLED_LINK", mock.Mock(is_symlink=lambda: True)):
            return savesync.sync_status(get=get, gui=lambda: ("key", "http://127.0.0.1:8384/rest"))

    def test_status_is_read_straight_from_syncthing(self):
        answers = {
            "system/status": {"myID": "ME"},
            "config": {"devices": [{"deviceID": "ME"}, {"deviceID": "PC12345", "name": "desk"}],
                       "folders": [{"id": "steamling-saves", "path": "/s", "devices": [{}, {}]},
                                   {"id": "other", "path": "/o"}]},
            "system/connections": {"connections": {"PC12345": {"connected": True}}},
            "cluster/pending/devices": {"NEW7777": {"name": "", "address": "10.0.0.2"}},
        }
        st = self._status(lambda base, key, path: answers[path])
        self.assertTrue(st["running"])
        self.assertEqual(st["deviceId"], "ME")
        self.assertEqual(st["devices"], [{"id": "PC12345", "name": "desk", "connected": True}])
        self.assertEqual(st["pending"], [{"id": "NEW7777", "name": "NEW7777", "address": "10.0.0.2"}])
        self.assertEqual([f["id"] for f in st["folders"]], ["steamling-saves"])
        self.assertTrue(st["folders"][0]["shared"])

    def test_a_syncthing_that_does_not_answer_is_on_but_not_running(self):
        def refuse(base, key, path):
            raise OSError("connection refused")
        st = self._status(refuse)
        self.assertTrue(st["on"])
        self.assertFalse(st["running"])

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
