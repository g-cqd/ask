#!/usr/bin/env python3
"""Measure what one request spends on tool definitions (roadmap 0137).

    python3 Scripts/measure-request-size.py [.build/release/ask] [--mcp-from CONFIG]

Runs `ask -p hi` against probe-agent-run's fake Anthropic server on 127.0.0.1 and reports the first request body in compact UTF-8
bytes: the whole body, the tools, ask's own tools and the MCP tools, each tool's description and schema, and properties repeated
across tools. Nothing leaves the machine but what MCP servers do; no credential is read. `--mcp-from` copies only the `mcp` section
of a config file (read, never written) into the run's throwaway config, to measure a person's servers. Bytes, not tokens: tokens
depend on the provider's tokenizer, and a JSON schema runs at roughly three bytes a token.
"""
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

MCP_PREFIX = 'mcp__'


def compact(value):
    """The bytes `value` takes as compact JSON, as an encoder without spaces writes it."""
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False).encode()


def sizes(body):
    """Bytes of each part of a request body, and one row per tool."""
    tools = body.get('tools', [])
    rows = [{'name': tool['name'], 'total': len(compact(tool)),
             'description': len(tool.get('description', '').encode()),
             'schema': len(compact(tool.get('input_schema', {})))} for tool in tools]
    return {'total': len(compact(body)), 'tools': len(compact(tools)), 'system': len(compact(body.get('system', ''))),
            'messages': len(compact(body.get('messages', []))),
            'mcp': sum(row['total'] for row in rows if row['name'].startswith(MCP_PREFIX)), 'rows': rows}


def repeated(body):
    """Properties whose schema is the same in more than one tool: (name, tools carrying it, bytes of one copy), largest first."""
    seen = {}
    for tool in body.get('tools', []):
        for name, schema in tool.get('input_schema', {}).get('properties', {}).items():
            key = (name, compact(schema))
            seen[key] = seen.get(key, 0) + 1
    found = [(name, count, len(compact({name: json.loads(schema)})) - 2)
             for (name, schema), count in seen.items() if count > 1]
    return sorted(found, key=lambda entry: -(entry[1] - 1) * entry[2])


def capture(binary, mcp_from=None):
    """The first request body `ask -p hi` sends, run in throwaway directories."""
    scripts = pathlib.Path(__file__).resolve().parent
    sys.path.insert(0, str(scripts))
    spec = importlib.util.spec_from_file_location('probe_agent_run', scripts / 'probe-agent-run.py')
    probe = importlib.util.module_from_spec(spec)
    arguments, sys.argv = sys.argv, [sys.argv[0], binary]
    try:
        spec.loader.exec_module(probe)
    finally:
        sys.argv = arguments
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    config = os.path.join(state, 'config')
    os.makedirs(os.path.join(config, 'ask'))
    if mcp_from:
        with open(os.path.expanduser(mcp_from)) as source:
            servers = json.load(source).get('mcp', {})
        with open(os.path.join(config, 'ask', 'config.json'), 'w') as target:
            json.dump({'mcp': servers}, target)
    server = probe.Server([probe.turn([('text', 'ok')], 'end_turn')])
    run = subprocess.run([binary, '-p', 'hi'], cwd=project, env=probe.environment(state, server.url, config),
                         capture_output=True, text=True, timeout=180)
    if not server.requests:
        sys.exit(f'ask sent no request (exit {run.returncode}): {run.stderr[-400:]}')
    return server.requests[0]['body'], run.stderr


def report(body):
    measured = sizes(body)
    own = measured['tools'] - measured['mcp']
    print(f"request {measured['total']} bytes: tools {measured['tools']} (ask's {own}, MCP {measured['mcp']}), "
          f"system {measured['system']}, messages {measured['messages']}")
    print(f"  {'tool':44} {'total':>6} {'desc':>6} {'schema':>6}")
    for row in measured['rows']:
        print(f"  {row['name'][:44]:44} {row['total']:6} {row['description']:6} {row['schema']:6}")
    for name, count, size in repeated(body):
        print(f"  repeated: {name} in {count} tools, {size} bytes each ({(count - 1) * size} bytes beyond one)")


def main():
    arguments = sys.argv[1:]
    mcp_from = None
    if '--mcp-from' in arguments:
        index = arguments.index('--mcp-from')
        mcp_from = arguments[index + 1]
        del arguments[index:index + 2]
    binary = str(pathlib.Path(arguments[0] if arguments else '.build/release/ask').resolve())
    body, stderr = capture(binary, mcp_from)
    for line in stderr.splitlines():
        if 'MCP server' in line:
            print(line)
    report(body)


if __name__ == '__main__':
    main()
