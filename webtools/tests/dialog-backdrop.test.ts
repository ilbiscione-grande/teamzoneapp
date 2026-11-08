import test from 'node:test';
import assert from 'node:assert/strict';
import { dialogBackdropHandlers } from '../lib/dialog-backdrop.ts';
import type { MouseEvent, PointerEvent } from 'react';

function fixture() {
  let closed=0,prevented=0,stopped=0;
  const dialog={getBoundingClientRect:()=>({left:100,right:500,top:100,bottom:500}),close:()=>closed++};
  const event=(x:number,y:number,target:unknown=dialog)=>({currentTarget:dialog,target,clientX:x,clientY:y,button:0,preventDefault:()=>prevented++,stopPropagation:()=>stopped++});
  const handlers=dialogBackdropHandlers();
  return {down:(x:number,y:number,target?:unknown)=>handlers.onPointerDown(event(x,y,target) as unknown as PointerEvent<HTMLDialogElement>),click:(x:number,y:number,target?:unknown)=>handlers.onClick(event(x,y,target) as unknown as MouseEvent<HTMLDialogElement>),cancel:handlers.onPointerCancel,result:()=>({closed,prevented,stopped})};
}
test('a backdrop click closes once without passing the click to the calendar',()=>{
  const f=fixture();f.down(20,20);f.click(20,20);f.click(20,20);
  assert.deepEqual(f.result(),{closed:1,prevented:1,stopped:1});
});
test('dialog padding and content clicks keep the dialog open',()=>{
  const f=fixture();f.down(105,105);f.click(105,105);f.down(200,200,{});f.click(200,200,{});
  assert.equal(f.result().closed,0);
});
test('dragging from inside to outside or from outside to inside does not dismiss',()=>{
  const f=fixture();f.down(200,200);f.click(20,20);f.down(20,20);f.click(200,200);
  assert.equal(f.result().closed,0);
});
test('cancelled pointer gestures and clicks without pointer-down do not dismiss',()=>{
  const f=fixture();f.click(20,20);f.down(20,20);f.cancel();f.click(20,20);
  assert.equal(f.result().closed,0);
});
