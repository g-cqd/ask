#!/usr/bin/env python3
"""Roadmap 0227: /goal live, against a scripted model server whose judge answers NOT YET then MET; the judge must be the catalog's cheap
model, the first verdict must continue the run, the second end the goal.

Scripts/probe-goal.py .build/release/ask
"""
import importlib.util, json, os, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
binary = os.path.abspath(sys.argv[1]); sys.argv = [sys.argv[0], binary]
spec = importlib.util.spec_from_file_location('pi', 'Scripts/probe-interactive.py'); pi = importlib.util.module_from_spec(spec); spec.loader.exec_module(pi)
agent = pi.agent
verdicts = ['NOT YET: the file says draft, it should say final', 'MET: the agent showed the file says final']
judged = []
def route(body):
    text = json.dumps(body.get('messages', []))
    if 'You judge whether a coding agent has met a goal' in text:
        judged.append(body.get('model'))
        return agent.turn([('text', verdicts.pop(0) if verdicts else 'MET')], 'end_turn')
    return None
catalog = [{"id": "claude-big-1", "display_name": "big", "type": "model"}, {"id": "claude-haiku-9", "display_name": "haiku", "type": "model"}]
server = agent.Server([agent.turn([('text', 'I wrote draft.')], 'end_turn'), agent.turn([('text', 'Now it says final.')], 'end_turn')],
                      catalog=catalog, route=route)
project = tempfile.mkdtemp()
screen = pi.Screen(server.url, project)
screen.ready()
screen.type('/goal the file says final\r')
ok = screen.until('Goal met', 60)
text = screen.screen.text()
print('goal met shown:', ok)
print('judge requests:', len(judged), 'models:', judged)
print('main requests:', len(server.requests) - len(judged))
print('continue sent:', 'Goal not met yet (1 of 10)' in json.dumps([r['body'] for r in server.requests]))
screen.type('/goal\r'); screen.until('turns judged', 10)
print('status:', [l.strip() for l in screen.screen.text().split('\n') if 'Goal (' in l or 'turns judged' in l][-1:])
screen.type('/quit\r'); screen.finish()
passed = ok and judged == ['claude-haiku-9', 'claude-haiku-9'] and 'Goal not met yet (1 of 10)' in json.dumps([r['body'] for r in server.requests])
print('PASS' if passed else 'FAIL')
sys.exit(0 if passed else 1)
