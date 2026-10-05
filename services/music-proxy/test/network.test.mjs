import test from 'node:test';
import assert from 'node:assert/strict';
import {requestText,normalizeToken,responseError} from '../../../web/music/network.mjs';

test('mobile request works without static AbortSignal helpers',async()=>{
 const any=AbortSignal.any,timeout=AbortSignal.timeout;
 try {
  AbortSignal.any=undefined;AbortSignal.timeout=undefined;
  const result=await requestText('https://example.test',{},100,async()=>new Response('ok'));
  assert.equal(result.text,'ok');
 } finally {AbortSignal.any=any;AbortSignal.timeout=timeout;}
});
test('timeout covers reading the body, and external cancellation remains distinct',async()=>{
 const fetcher=async(_url,{signal})=>({text:()=>new Promise((resolve,reject)=>{
  if(signal.aborted)return reject(new DOMException('cancelled','AbortError'));
  signal.addEventListener('abort',()=>reject(new DOMException('cancelled','AbortError')),{once:true});
 })});
 await assert.rejects(()=>requestText('https://example.test',{},5,fetcher),/连接超时/);
 const controller=new AbortController();controller.abort();
 await assert.rejects(()=>requestText('https://example.test',{signal:controller.signal},100,fetcher),/请求已取消/);
});
test('mobile token copy formats normalize; network errors do not suggest wrong credentials',async()=>{
 assert.equal(normalizeToken('PROXY_TOKEN= abcd\nef12 '),'abcdef12');
 assert.equal(normalizeToken('Bearer abcdef12'),'abcdef12');
 assert.match(responseError(401),/口令不正确/);
 await assert.rejects(()=>requestText('https://example.test',{},100,async()=>{throw new TypeError('Failed to fetch');}),/当前网络无法连接/);
});
