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

    def test_the_config_is_read_without_an_xml_parser(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".xml") as f:
            f.write('<configuration version="51">\n  <folder id="x"><address>no</address></folder>\n'
                    '  <gui enabled="true" tls="true" sendBasicAuthPrompt="false">\n'
                    '    <address>127.0.0.1:8385</address>\n    <apikey>abcDEF123</apikey>\n  </gui>\n'
                    '</configuration>\n')
            f.flush()
            self.assertEqual(savesync._gui(("/nonexistent/config.xml", f.name)),
                             ("abcDEF123", "https://127.0.0.1:8385/rest"))
        self.assertEqual(savesync._gui(("/nonexistent/config.xml",)), (None, None))

    def test_no_http_in_the_loader_falls_back_to_the_tool(self):
        def no_http(base, key, path):
            raise savesync._NoHttp("No module named 'urllib.request'")
        with mock.patch.object(savesync, "_run", return_value={"on": True, "running": True}) as run:
            st = self._status(no_http)
        self.assertEqual(run.call_args.args[0], ["status"])
        self.assertTrue(st["running"])

    def test_nothing_imports_what_the_loader_python_lacks(self):
        # Decky's frozen Python has no xml.etree; a top-level import of it stops the plugin loading.
        import pathlib
        import re
        root = pathlib.Path(savesync.__file__).resolve().parents[2]
        for path in [root / "main.py", *sorted((root / "py_modules").rglob("*.py"))]:
            for line in path.read_text().splitlines():
                self.assertIsNone(re.match(r"(import|from)\s+(xml|urllib\.request|ssl|http|sqlite3|email)\b", line),
                                  f"{path.name}: top-level '{line}'")

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
