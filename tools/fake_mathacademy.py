#!/usr/bin/env python3
"""A local stand-in for mathacademy.com, for testing MathGate's real network path.

Serves the two endpoints the app uses:
  POST /login                     -> 302 + session cookies (any credentials are accepted)
  GET  /api/previous-tasks/{date} -> a JSON array of completed tasks

Usage:
  python3 tools/fake_mathacademy.py --port 8799 --tasks 0     # nothing done today -> app blocks
  python3 tools/fake_mathacademy.py --port 8799 --tasks 3     # three tasks today  -> app unlocks

Point a debug build at it with:
  adb reverse tcp:8799 tcp:8799
  # then set the "debug_base_url" pref to http://127.0.0.1:8799
"""
import argparse
import datetime
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

TASK_TYPES = ["Lesson", "Review", "Quiz", "Multistep"]


def build_tasks(count_today, zone_offset_hours=0):
    """`count_today` tasks completed a few minutes ago, plus older ones from previous days."""
    now = datetime.datetime.now(datetime.timezone.utc)
    tasks = []
    for i in range(count_today):
        tasks.append(_task(i, now - datetime.timedelta(minutes=5 + i * 20), 7 + i * 2))
    for i in range(4):
        tasks.append(_task(100 + i, now - datetime.timedelta(days=3 + i, hours=2), 6 + i))
    return tasks


def _task(idx, completed, points):
    return {
        "id": 900000 + idx,
        "type": TASK_TYPES[idx % len(TASK_TYPES)],
        "topicCourseId": 99,
        "progress": 1,
        "points": points,
        "pointsAwarded": points,
        "topic": {"id": 3000 + idx, "name": f"Sample Topic {idx}", "course": {"id": 99, "name": "Mathematical Foundations III"}},
        "started": (completed - datetime.timedelta(minutes=12)).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "completed": completed.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "test": {"id": None, "name": None, "course": {"id": 99, "name": "Mathematical Foundations III"}},
        "progressStr": "100%",
    }


class Handler(BaseHTTPRequestHandler):
    tasks_today = 0

    def log_message(self, fmt, *args):
        print(f"  fake-ma: {self.command} {self.path.split('?')[0][:60]} -> {args[1] if len(args) > 1 else ''}")

    def do_POST(self):
        if self.path != "/login":
            return self._send(404, "text/html", b"not found")
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        expires = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=30)).strftime(
            "%a, %d %b %Y %H:%M:%S GMT"
        )
        self.send_response(302)
        self.send_header("Set-Cookie", f"session=fake-session; path=/; expires={expires}; httponly")
        self.send_header("Set-Cookie", f"session.sig=fake-sig; path=/; expires={expires}; httponly")
        self.send_header("Location", "/learn")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if not self.path.startswith("/api/previous-tasks/"):
            return self._send(404, "text/html", b"not found")
        cookie = self.headers.get("Cookie") or ""
        if "session=fake-session" not in cookie:
            self.send_response(302)
            self.send_header("Location", "/session-expired")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = json.dumps(build_tasks(self.tasks_today)).encode()
        self._send(200, "application/json; charset=utf-8", body)

    def _send(self, code, content_type, body):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=8799)
    p.add_argument("--tasks", type=int, default=0, help="tasks completed today")
    args = p.parse_args()
    Handler.tasks_today = args.tasks
    print(f"fake mathacademy.com on http://127.0.0.1:{args.port} ({args.tasks} task(s) completed today)")
    HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
