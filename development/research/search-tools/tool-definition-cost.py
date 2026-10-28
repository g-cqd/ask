import http.server, json, os, pathlib, subprocess, tempfile, threading
binary='/Users/me/Developer/ask/.build/release/ask'
seen={}
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        seen['b']=json.loads(self.rfile.read(int(self.headers['content-length'])))
        body=b'event: message_start\ndata: {"type":"message_start","message":{"id":"m","role":"assistant","model":"m","content":[],"usage":{"input_tokens":1,"output_tokens":0}}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n'
        self.send_response(401); self.send_header('content-length','0'); self.end_headers()
    def log_message(self,*a): pass
s=http.server.ThreadingHTTPServer(('127.0.0.1',0),H); threading.Thread(target=s.serve_forever,daemon=True).start()
root=pathlib.Path(tempfile.mkdtemp())
env={k:v for k,v in os.environ.items() if not k.startswith(('ANTHROPIC_','ASK_','XDG_'))}|{'XDG_CONFIG_HOME':str(root/'c'),'XDG_STATE_HOME':str(root/'s'),'ANTHROPIC_BASE_URL':'http://127.0.0.1:%d'%s.server_address[1],'ANTHROPIC_API_KEY':'fixture'}
subprocess.run([binary,'--provider','anthropic','--model','m','--max-turns','1','--print','hi'],cwd=root,env=env,capture_output=True,text=True,timeout=40,stdin=subprocess.DEVNULL)
tools=seen['b']['tools']; total=len(json.dumps(tools,separators=(',',':')))
print('tools',len(tools),'bytes',total,'~tokens',total//4)
for t in tools: print(' ',t['name'].ljust(14),len(json.dumps(t,separators=(',',':'))),'bytes')
sysb=len(json.dumps(seen['b'].get('system',''),separators=(',',':')))
print('system bytes',sysb)
