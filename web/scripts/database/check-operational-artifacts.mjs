import {execFileSync} from 'node:child_process';
import {readFileSync,existsSync} from 'node:fs';
import path from 'node:path';
const names=new Set([...execFileSync('git',['diff','--name-only','--relative'],{encoding:'utf8'}).trim().split('\n'),...execFileSync('git',['ls-files','--others','--exclude-standard'],{encoding:'utf8'}).trim().split('\n')]);
let checked=0;
for(const file of names){
 if(!file||!existsSync(file)||!/[.](md|json|sql|mjs|ts|js)$/.test(file))continue;
 const source=readFileSync(file,'utf8');checked++;
 if(/(?:sb_secret_|sbp_)[a-zA-Z0-9]{20,}|eyJ[a-zA-Z0-9_-]{25,}\.[a-zA-Z0-9_-]{20,}\.|-----BEGIN (?:RSA |OPENSSH )?PRIVATE KEY-----/.test(source))throw Error('Review credential pattern in '+file+'; values intentionally not printed.');
 if(/[\t ]+\r?$/m.test(source))throw Error('Trailing whitespace in '+file);
 if(file.endsWith('.md')){
  if((source.match(/^```/gm)||[]).length%2)throw Error('Unclosed Markdown fence: '+file);
  for(const match of source.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)){
   const target=match[1].replace(/^<|>$/g,'').split('#')[0];
   if(target&&!/^(?:https?:|mailto:|\/)/.test(target)&&!existsSync(path.resolve(path.dirname(file),target)))throw Error('Missing local link in '+file+': '+target);
  }
 }
}
if(execFileSync('git',['ls-files','.env.local'],{encoding:'utf8'}).trim())throw Error('Environment file is tracked');
console.log(`PASS ${checked} changed text artifacts: links/fences/whitespace and credential-pattern scan; environment file untracked.`);
