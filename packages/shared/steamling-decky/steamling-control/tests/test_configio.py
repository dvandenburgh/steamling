import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests.helpers import TempDirCase  # noqa: F401  (puts py_modules on the path)
from steamling_control import configio


class ConfigIoTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.tweaks = {"global": {}, "games": {}}
        for target, value in (("EXPORT_DIR", self.dir),
                              ("STEAM_CONFIG_VDF", self.dir / "none.vdf"),
                              ("load_tweaks", lambda: json.loads(json.dumps(self.tweaks))),
                              ("save_tweaks", self._save)):
            patcher = mock.patch.object(configio, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def _save(self, tweaks):
        self.tweaks = tweaks

    def test_controller_type_and_touchscreen_travel(self):
        self.tweaks["games"]["10"] = {"enabled": True, "name": "Game", "gamepadType": "ds5",
                                      "touchDisabled": True, "fanMode": "quiet"}
        path = configio.export_config("10", "Game")["path"]
        data = json.loads(Path(path).read_text())
        entry = data["games"]["10"]
        self.assertEqual(entry["gamepadType"], "ds5")
        self.assertIs(entry["touchDisabled"], True)
        self.assertNotIn("fanMode", entry)

    def test_import_keeps_this_handhelds_fan_curve(self):
        self.tweaks["games"]["10"] = {"enabled": True, "name": "Game", "gamepadType": "xb360"}
        path = configio.export_config("10", "Game")["path"]
        self.tweaks["games"]["20"] = {"enabled": True, "name": "Other", "fanMode": "performance",
                                      "envVars": "OLD=1"}
        configio.apply_config(path, "10", "20", "Other")
        entry = self.tweaks["games"]["20"]
        self.assertEqual(entry["fanMode"], "performance")
        self.assertEqual(entry["gamepadType"], "xb360")
        self.assertNotIn("envVars", entry)


if __name__ == "__main__":
    unittest.main()
