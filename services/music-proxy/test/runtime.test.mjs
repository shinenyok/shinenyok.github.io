import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {sourceWorker, SourceRuntime} from '../../../web/music/runtime.mjs';
function sandbox() {
  const messages=[];
  const context=vm.createContext({TextEncoder,TextDecoder,Uint8Array,atob,btoa,crypto,console});
  context.self=context; context.postMessage=message=>messages.push(message);
  vm.runInContext(`(${sourceWorker.toString()})()`,context,{timeout:1000});
  return {messages,send:data=>context.onmessage({data})};
}

test('LX script initializes, receives track and resolves through brokered HTTP',async()=>{
  const {messages,send}=sandbox();
  await send({type:'load',name:'fixture',script:`
    lx.on(lx.EVENT_NAMES.request, ({info}) => new Promise((resolve,reject)=>{
      lx.request('https://source.example/'+info.musicInfo.songmid, {headers:{'X-Request-Key':'fixture'}}, (err,resp)=>err?reject(err):resolve(resp.body.url));
    }));
    lx.send(lx.EVENT_NAMES.inited,{status:true,sources:{kw:{actions:['musicUrl'],qualitys:['128k']}}});
  `});
  assert.equal(messages[0].type,'init');
  const action=send({type:'action',id:4,data:{source:'kw',action:'musicUrl',info:{musicInfo:{songmid:'228908'}}}});
  assert.equal(messages[1].url,'https://source.example/228908');
  await send({type:'httpResult',id:messages[1].id,response:{body:{url:'https://audio.example/song.mp3'}}});
  await action;
  assert.equal(messages[2].result,'https://audio.example/song.mp3');
});

test('upstream failures are delivered as LX action errors',async()=>{
 const {messages,send}=sandbox();
 await send({type:'load',script:`lx.on('request',()=>new Promise((resolve,reject)=>lx.request('https://source.example',{},err=>reject(err))));`});
 const action=send({type:'action',id:7,data:{}});
 await send({type:'httpResult',id:messages[0].id,error:'upstream unavailable'});
 await action; assert.equal(messages.at(-1).error,'upstream unavailable');
});

test('unsupported crypto fails explicitly rather than returning corrupt data',async()=>{
 const {messages,send}=sandbox();
 await send({type:'load',script:`lx.utils.crypto.md5('test')`});
 assert.match(messages[0].error,/尚未适配/);
});

test('playback rejects insecure or invalid source output',async()=>{
 for(const url of ['http://audio.example/a.mp3','javascript:alert(1)','not-url','https://user:pass@audio.example/a.mp3']){
  const runtime=new SourceRuntime(()=>{});runtime.capabilities={kw:{}};
  runtime.wait=async()=>url;runtime.send=()=>{};
  await assert.rejects(()=>runtime.musicUrl({},'128k'));
 }
});

test('only the verified Kuwo media host is upgraded to HTTPS',async()=>{
 const runtime=new SourceRuntime(()=>{});runtime.capabilities={kw:{}};
 runtime.wait=async()=> 'http://bd-er.kuwo.cn/path/song.mp3?key=example';runtime.send=()=>{};
 assert.equal(await runtime.musicUrl({},'128k'),'https://bd-er.kuwo.cn/path/song.mp3?key=example');
});
