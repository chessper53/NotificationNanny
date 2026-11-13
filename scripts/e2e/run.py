#!/usr/bin/env python3
"""Explicitly enabled live macOS smoke tests. See docs/E2E.md for preparation and limits."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


class Unavailable(RuntimeError):
    pass


def command(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, text=True, **kwargs)


def contains(outer, inner, tolerance=2):
    return (inner["x"] >= outer["x"] - tolerance
            and inner["y"] >= outer["y"] - tolerance
            and inner["x"] + inner["width"] <= outer["x"] + outer["width"] + tolerance
            and inner["y"] + inner["height"] <= outer["y"] + outer["height"] + tolerance)


def overlap(a, b):
    return (min(a["x"] + a["width"], b["x"] + b["width"]) - max(a["x"], b["x"]) > 2
            and min(a["y"] + a["height"], b["y"] + b["height"]) - max(a["y"], b["y"]) > 2)


def native_positioned(sample, title):
    banners = [b for b in sample["native"] if title in b["description"]]
    if len(banners) != 1 or sample["overlays"]:
        return False
    b = banners[0]["frame"]
    return any(contains(s["visible"], b) and abs(b["x"] - s["visible"]["x"] - 8) <= 12
               and abs(b["y"] + b["height"] - s["visible"]["y"] - s["visible"]["height"] + 8) <= 12
               for s in sample["screens"])


def custom_stacked(sample, titles, scale=1.25):
    overlays = sample["overlays"]
    if len(overlays) != len(titles) or not all(any(t in b["texts"] for b in overlays) for t in titles):
        return False
    # The AX window includes the transparent close button margin.
    margin = 8 * scale
    frames = [{"x": b["frame"]["x"] + margin, "y": b["frame"]["y"] + margin,
               "width": b["frame"]["width"] - 2 * margin, "height": b["frame"]["height"] - 2 * margin} for b in overlays]
    return (all(f["width"] > 0 and f["height"] > 0 for f in frames)
            and any(all(contains(s["visible"], f) for f in frames) for s in sample["screens"])
            and not any(overlap(a, b) for i, a in enumerate(frames) for b in frames[i + 1:]))


def response_received(lines, title):
    return any(line.partition(" title=")[0].endswith(" Lab Alpha action=archive")
               and line.partition(" title=")[2] == title for line in lines)


def check_environment(status):
    problems = []
    if not status["trusted"]:
        problems.append("grant Accessibility to the terminal/runner launching this command")
    if status["locked"]:
        problems.append("unlock the desktop")
    if not status["notificationCenter"] or not status["screens"]:
        problems.append("run in a logged-in graphical macOS session with Notification Center")
    if status["runningApps"]:
        problems.append("NotificationNanny is already running; it will be left untouched")
    if problems:
        raise Unavailable("; ".join(problems))


def check_senders():
    for app in ["Alpha", "Bravo", "Charlie"]:
        sender = ROOT / "build/notify-lab" / f"Lab {app}.app/Contents/MacOS/notifier"
        if not sender.is_file():
            raise Unavailable("build the Lab sender apps first; see docs/E2E.md")
        try:
            settings = json.loads(command([sender, "--status"], capture_output=True, timeout=5).stdout)
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            raise Unavailable(f"could not read Lab {app} notification settings: {error}") from error
        if not isinstance(settings, dict) or not all(settings.get(k) is True for k in ["authorized", "alertsEnabled", "persistent"]):
            raise Unavailable(f"Lab {app} needs notification permission and Persistent alerts; see docs/E2E.md")


class Smoke:
    def __init__(self, app, directory, probe):
        self.app, self.directory, self.probe = app, directory, probe
        self.process = None
        self.log = None
        self.run_directory = None
        self.token = None
        self.samples = None

    def status(self):
        try:
            return json.loads(command([self.probe, "status"], capture_output=True, timeout=5).stdout)
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            raise Unavailable(f"could not inspect the desktop: {error}") from error

    def snapshot(self):
        if self.process.poll() is not None:
            raise AssertionError(f"app exited with {self.process.returncode}; see {self.run_directory / 'app.log'}")
        sample = json.loads(command([self.probe, "snapshot", self.process.pid, self.token], capture_output=True, timeout=5).stdout)
        self.samples.write(json.dumps({"time": time.monotonic(), **sample}) + "\n")
        self.samples.flush()
        return sample

    def wait(self, predicate, message, seconds=8, stable=0.4):
        deadline = time.monotonic() + seconds
        since = None
        while time.monotonic() < deadline:
            sample = self.snapshot()
            if predicate(sample):
                since = since or time.monotonic()
                if time.monotonic() - since >= stable:
                    return sample
            else:
                since = None
            time.sleep(0.1)
        raise AssertionError(message)

    def start(self, name, scale=1, dismiss=0):
        check_environment(self.status())
        self.token = f"E2E-{uuid.uuid4()}"
        self.run_directory = self.directory / str(uuid.uuid4())
        self.run_directory.mkdir()
        screens = self.status()["screens"]
        values = {
            "isEnabled": True, "bannerScale": scale, "autoDismissSeconds": dismiss,
            "bannerAnimation": "Default", "holdWhileAsleep": False,
            "pauseDuringFocus": False, "pauseWhileStreaming": False,
            "followActiveScreen": False, "avoidNCPanel": True,
            "redactBannerContent": False, "customNotificationCenter": False,
            "placementsByDisplayID": json.dumps({s["uuid"]: {
                "position": "bottomLeft", "xOffset": 0, "yOffset": 0,
            } for s in screens}).encode(),
        }
        with (self.run_directory / "settings.plist").open("wb") as handle:
            plistlib.dump(values, handle)
        self.log = (self.run_directory / "app.log").open("w")
        self.samples = (self.run_directory / "observations.jsonl").open("w")
        env = {**os.environ, "NN_LAB": "1", "NN_E2E_DIRECTORY": str(self.run_directory),
               "NN_LOG_DIR": str(self.run_directory / "logs"), "NN_LOG_STDERR": "1"}
        self.process = subprocess.Popen([str(self.app / "Contents/MacOS/NotificationNanny")],
                                        env=env, stdout=self.log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise AssertionError("app exited during startup; see app.log")
            log = (self.run_directory / "app.log").read_text()
            if "Observer started" in log and "E2E settings isolated" in log:
                print(f"RUN  {name}", flush=True)
                return
            time.sleep(0.1)
        raise AssertionError("AX observer did not start within 8 seconds; see app.log")

    def post(self, app, actions=False):
        title = f"{self.token}-{app}"
        sender = ROOT / "build/notify-lab" / f"Lab {app}.app/Contents/MacOS/notifier"
        command([sender, title, "NotificationNanny E2E smoke"] + (["--archive-only"] if actions else []), timeout=15)
        return title

    def native_position(self):
        self.start("native-position")
        title = self.post("Alpha")

        self.wait(lambda s: native_positioned(s, title), "unique native banner never settled at bottom-left")

    def custom_stack(self):
        self.start("custom-stack-dismiss", scale=1.25, dismiss=5)
        first_post = time.monotonic()
        titles = [self.post(app) for app in ["Alpha", "Bravo", "Charlie"]]
        last_post = time.monotonic()
        self.wait(lambda s: custom_stacked(s, titles),
                  "three unique custom banners never formed a visible non-overlapping pile", seconds=4)
        while time.monotonic() < first_post + 4:
            if not custom_stacked(self.snapshot(), titles):
                raise AssertionError("custom pile disappeared or changed before the 5-second timer (1s tolerance)")
            time.sleep(0.1)
        self.wait(lambda s: not s["overlays"] and not s["native"],
                  "custom/native banners remained after the dismissal deadline",
                  seconds=max(0, last_post + 8 - time.monotonic()), stable=0.8)

    def action(self):
        self.start("custom-action", scale=1.25)
        title = self.post("Alpha", actions=True)
        self.wait(lambda s: any(title in b["texts"] for b in s["overlays"]), "custom action banner never appeared")
        command([self.probe, "press", self.process.pid, title, "Archive"], timeout=6)
        response_log = ROOT / "build/notify-lab/responses.log"

        def received(_):
            lines = response_log.read_text().splitlines() if response_log.exists() else []
            return response_received(lines, title)

        self.wait(received, "Archive never reached the notification sender", seconds=6, stable=0)

    def cleanup(self):
        if self.process is None:
            return
        errors = []
        # Clear while the observer is active, then quit normally to restore parked hosts.
        for app in ["Alpha", "Bravo", "Charlie"]:
            try:
                command([ROOT / "build/notify-lab" / f"Lab {app}.app/Contents/MacOS/notifier", "--clear"], timeout=5)
            except (subprocess.SubprocessError, OSError) as error:
                errors.append(f"clear {app}: {error}")
        if self.process.poll() is None:
            try:
                command([self.probe, "quit", self.process.pid], capture_output=True, timeout=3)
                self.process.wait(timeout=5)
            except (subprocess.SubprocessError, OSError) as error:
                errors.append(f"normal app quit failed: {error}")
                self.process.terminate()
                try:
                    self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
        self.process = None
        if self.run_directory:
            suite = f"com.notificationnanny.e2e.{self.run_directory.name}"
            result = subprocess.run(["defaults", "delete", suite], capture_output=True)
            # A failed launch may never have created the suite.
            if result.returncode and subprocess.run(["defaults", "read", suite], capture_output=True).returncode == 0:
                errors.append(f"could not delete test suite {suite}")
        for handle in [self.log, self.samples]:
            if handle:
                handle.close()
        if errors:
            raise AssertionError("cleanup failed: " + "; ".join(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check prerequisites without launching or changing settings")
    parser.add_argument("--app", type=Path, default=ROOT / "build/NotificationNanny.app")
    parser.add_argument("--only", choices=["native-position", "custom-stack-dismiss", "custom-action"])
    args = parser.parse_args()
    os.chdir(ROOT)
    probe = ROOT / "build/e2e/probe"
    if not probe.is_file():
        raise Unavailable("build the probe and Lab sender apps first; see docs/E2E.md")
    run = ROOT / "build/e2e/runs" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    smoke = Smoke(args.app.resolve(), run, probe)
    check_environment(smoke.status())
    check_senders()
    if args.check:
        print("READY: desktop, Accessibility, Notification Center; no app instance running")
        return 0
    if not (smoke.app / "Contents/MacOS/NotificationNanny").is_file():
        raise Unavailable("build NotificationNanny.app first; see docs/E2E.md")
    if b"NN_E2E_DIRECTORY" not in (smoke.app / "Contents/MacOS/NotificationNanny").read_bytes():
        raise Unavailable("this app predates isolated E2E settings; rebuild from the testing branch")
    run.mkdir(parents=True)
    # Worktrees share the desktop; lock across processes to isolate Lab notifications.
    with open("/tmp/notificationnanny-e2e.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Unavailable("another E2E suite owns the desktop")
        cases = {"native-position": smoke.native_position, "custom-stack-dismiss": smoke.custom_stack,
                 "custom-action": smoke.action}
        results = []
        for name, case in cases.items():
            if args.only and name != args.only:
                continue
            error = None
            try:
                case()
            except (AssertionError, Unavailable, subprocess.SubprocessError, OSError) as exc:
                error = str(exc)
            finally:
                try:
                    smoke.cleanup()
                except (AssertionError, OSError) as exc:
                    error = f"{error + '; ' if error else ''}{exc}"
            results.append({"name": name, "passed": error is None, "error": error,
                            "artifacts": str(smoke.run_directory)})
            print(f"{'FAIL' if error else 'PASS'} {name}" + (f": {error}" if error else ""), flush=True)
            if error:
                break
        (run / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        print(f"Artifacts: {run}")
        return int(any(not r["passed"] for r in results))


if __name__ == "__main__":
    def interrupted(signum, _frame):
        raise KeyboardInterrupt(f"signal {signum}")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        sys.exit(main())
    except Unavailable as exc:
        print(f"UNAVAILABLE: {exc}", file=sys.stderr)
        sys.exit(69)
    except KeyboardInterrupt:
        sys.exit(130)
