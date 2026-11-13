"""Regression tests for the live suite's pass/fail contract; no desktop needed."""
import copy
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

from run import Smoke, Unavailable, check_environment, check_senders, custom_stacked, native_positioned, response_received


SCREEN = {"visible": {"x": 0, "y": 25, "width": 1200, "height": 800}}


def sample():
    return {"screens": [copy.deepcopy(SCREEN)], "native": [], "overlays": []}


class ContractTests(unittest.TestCase):
    def test_no_notifications_is_not_a_pass(self):
        self.assertFalse(native_positioned(sample(), "unique"))
        self.assertFalse(custom_stacked(sample(), ["a", "b", "c"]))

    def test_unrelated_notification_cannot_satisfy_arrival(self):
        state = sample()
        state["native"] = [{"description": "Lab Alpha, another-run", "frame": {
            "x": 8, "y": 717, "width": 350, "height": 100}}]
        self.assertFalse(native_positioned(state, "unique"))
        state["native"][0]["description"] = "Lab Alpha, unique"
        self.assertTrue(native_positioned(state, "unique"))

    def test_visible_but_wrong_corner_fails(self):
        state = sample()
        state["native"] = [{"description": "Lab Alpha, unique", "frame": {
            "x": 842, "y": 33, "width": 350, "height": 100}}]
        self.assertFalse(native_positioned(state, "unique"))

    def test_native_test_rejects_custom_replacement(self):
        state = sample()
        state["native"] = [{"description": "unique", "frame": {
            "x": 8, "y": 717, "width": 350, "height": 100}}]
        state["overlays"] = [{"texts": ["unique"]}]
        self.assertFalse(native_positioned(state, "unique"))

    def test_custom_pile_requires_distinct_titles_and_no_overlap(self):
        state = sample()
        state["overlays"] = [{"texts": [title], "frame": {
            "x": -2, "y": 400 + i * 110, "width": 370, "height": 120,
        }} for i, title in enumerate(["a", "b", "c"])]
        self.assertTrue(custom_stacked(state, ["a", "b", "c"]))
        state["overlays"][2]["texts"] = ["b"]
        self.assertFalse(custom_stacked(state, ["a", "b", "c"]))
        state["overlays"][2]["texts"] = ["c"]
        state["overlays"][2]["frame"]["y"] = 400
        self.assertFalse(custom_stacked(state, ["a", "b", "c"]))

    def test_offscreen_custom_pile_fails(self):
        state = sample()
        state["overlays"] = [{"texts": ["a"], "frame": {
            "x": -500, "y": 400, "width": 370, "height": 120,
        }}]
        self.assertFalse(custom_stacked(state, ["a"]))

    def test_action_requires_exact_run_title_sender_and_action(self):
        self.assertFalse(response_received(["date Lab Alpha action=archive title=old-run"], "run"))
        self.assertFalse(response_received(["date Lab Alpha action=archive title=run-extra"], "run"))
        self.assertFalse(response_received(["date Lab Bravo action=archive title=run"], "run"))
        self.assertFalse(response_received(["date Lab Alpha action=snooze title=run"], "run"))
        self.assertTrue(response_received(["date Lab Alpha action=archive title=run"], "run"))

    def test_missing_arrival_times_out(self):
        smoke = Smoke(Path("unused"), Path("unused"), Path("unused"))
        smoke.snapshot = Mock(return_value=sample())
        with self.assertRaisesRegex(AssertionError, "never arrived"):
            smoke.wait(lambda s: native_positioned(s, "unique"), "never arrived", seconds=0.01)

    def test_app_exit_cannot_look_like_successful_dismissal(self):
        smoke = Smoke(Path("unused"), Path("unused"), Path("unused"))
        smoke.process = Mock()
        smoke.process.poll.return_value = 1
        smoke.process.returncode = 1
        smoke.run_directory = Path("artifacts")
        with self.assertRaisesRegex(AssertionError, "app exited"):
            smoke.snapshot()

    def test_preflight_rejects_an_existing_app_or_missing_permissions(self):
        ready = {"trusted": True, "locked": False, "notificationCenter": True,
                 "screens": [SCREEN], "runningApps": []}
        check_environment(ready)
        for key, value in [("trusted", False), ("locked", True), ("notificationCenter", False),
                           ("screens", []), ("runningApps", [{"pid": 123}])]:
            with self.subTest(key=key), self.assertRaises(Unavailable):
                check_environment({**ready, key: value})

    def test_sender_preflight_rejects_denied_temporary_or_malformed_settings(self):
        for payload in ['{}', '{"authorized": false, "alertsEnabled": true, "persistent": true}',
                        '{"authorized": true, "alertsEnabled": true, "persistent": false}', 'not-json']:
            with self.subTest(payload=payload), patch("run.Path.is_file", return_value=True), \
                    patch("run.command", return_value=Mock(stdout=payload)), self.assertRaises(Unavailable):
                check_senders()


if __name__ == "__main__":
    unittest.main()
