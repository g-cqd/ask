#!/usr/bin/env python3
"""Roadmap 0228: /loop live, against a scripted model server: `/loop 1m TASK` must send TASK about a minute later as a message, `/loop`
must list it with its run, and `/loop stop 1` must end it.

Scripts/probe-loop.py .build/release/ask   (takes about 70 s: a loop runs at most once a minute)
"""
import importlib.util, json, os, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
binary = os.path.abspath(sys.argv[1]); sys.argv = [sys.argv[0], binary]
spec = importlib.util.spec_from_file_location('pi', 'Scripts/probe-interactive.py'); pi = importlib.util.module_from_spec(spec); spec.loader.exec_module(pi)
agent = pi.agent
server = agent.Server([agent.turn([('text', 'Checked: all green.')], 'end_turn')])
screen = pi.Screen(server.url, tempfile.mkdtemp())
screen.ready()
start = time.time()
screen.type('/loop 1m check the build\r')
added = screen.until('Loop 1: every 1 min', 10)
sent = screen.until('Checked: all green.', 100)
took = time.time() - start
bodies = json.dumps([r['body'] for r in server.requests])
screen.type('/loop\r')
listed = screen.until('1 runs', 10)
screen.type('/loop stop 1\r')
stopped = screen.until('Loop 1 stopped.', 10)
screen.type('/quit\r'); screen.finish()
print(f'added {added}, sent after {took:.0f} s: {sent}, labelled: {"[loop 1, run 1] check the build" in bodies}, listed {listed}, stopped {stopped}')
passed = added and sent and 55 <= took <= 100 and '[loop 1, run 1] check the build' in bodies and listed and stopped
print('PASS' if passed else 'FAIL')
sys.exit(0 if passed else 1)
