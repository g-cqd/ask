import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
if (!process.argv[2]) throw new Error('usage: node pi-thinking.mjs /path/to/pi-ai/dist');
const root = pathToFileURL(resolve(process.argv[2]) + '/').href;
const { THINKING_LEVELS } = await import(root + 'providers/model-schema.js');
const cases = [
 ['anthropic','anthropic-messages.js','anthropic.models.js','ANTHROPIC_MODELS','claude-sonnet-5-5'],
 ['anthropic-older','anthropic-messages.js','anthropic.models.js','ANTHROPIC_MODELS','claude-sonnet-4-6'],
 ['codex','openai-codex-responses.js','openai-codex.models.js','OPENAI_CODEX_MODELS','gpt-6.1-sol'],
];
for (const [name,api,file,key,id] of cases) {
 const table=(await import(root+'providers/'+file))[key];
 const model=Object.values(table).find(m=>m.id===id); assert(model);
 const {streamSimple}=await import(root+'api/'+api);
 for (const reasoning of [undefined,'off','low','medium','high','max','ultra','invalid']) {
  let captured;
  const events=streamSimple(model,{messages:[{role:'user',content:'hi',timestamp:0}]},{
   apiKey:name==='codex' ? ['e30',Buffer.from(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'fixture-account'}})).toString('base64url'),'fixture'].join('.') : 'probe-not-a-real-key',reasoning,maxTokens:1024,
   onPayload(payload){captured=payload;throw new Error('stop after payload: no request');},
   fetch(){throw new Error('UNEXPECTED NETWORK');},
  });
  const result=await events.result();
  assert(captured, `${name} ${reasoning} never reached onPayload: ${result.errorMessage}`);
  console.log(JSON.stringify({provider:name,model:id,requested:reasoning??'unset',withinDeclaredType:reasoning===undefined||THINKING_LEVELS.includes(reasoning),thinking:captured.thinking,reasoning:captured.reasoning,output_config:captured.output_config,max_tokens:captured.max_tokens,
   effort_messages:captured.messages?.filter(m=>m.role==='system').map(m=>({role:m.role,type:m.content?.[0]?.type,output_config:m.output_config})),
  }));
 }
}
