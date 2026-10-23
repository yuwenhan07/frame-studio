const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const { defaultStyle: defaults, normalizeStyle, effectivePalette } = require('../.test-build/core/model');
const { parseHex, hex, extractPalette, walkColor, contrastInk } = require('../.test-build/core/palette');
const { layout, layoutForLongEdge } = require('../.test-build/core/layout');
const { blurRGBA } = require('../.test-build/core/blur');
const { encodeCode128, barcodeGeometry } = require('../.test-build/core/barcode');
const { render } = require('../.test-build/core/render');
const red = { r: 255, g: 0, b: 0, fraction: .75 }, blue = { r: 0, g: 0, b: 255, fraction: .25 };
test('HEX accepts only six hexadecimal digits and keeps RGB in sync', () => {
  assert.deepEqual(parseHex(' #a9696b '), { r: 169, g: 105, b: 107, fraction: 0 });
  assert.equal(hex(parseHex('#a9696b')), '#A9696B');
  for (const value of ['#FFF', '#FFA9696B', 'blue', '#12345Z', '']) assert.equal(parseHex(value), undefined);
});
test('independent 3:1 red/blue input yields exact colors and proportions', () => {
  const colors = extractPalette(Uint8ClampedArray.from([255,0,0,255, 255,0,0,255, 0,0,255,255, 255,0,0,255]), 2, 'dominance');
  assert.deepEqual(colors, [red, blue]);
});
test('transparent source pixels composite over white; empty samples are safe', () => {
  assert.equal(hex(extractPalette([255,0,0,0], 8)[0]), '#FFFFFF');
  assert.deepEqual(extractPalette([], 5), []); assert.throws(() => extractPalette([1,2,3], 5));
});
test('palette is deterministic, sorted by luminance and never invents colors for a flat photo', () => {
  const input = [255,0,0,255, 0,0,255,255];
  assert.deepEqual(extractPalette(input, 5).map(hex), ['#0000FF', '#FF0000']);
  assert.deepEqual(extractPalette(input, 5), extractPalette(input, 5));
  assert.equal(extractPalette([30,60,90,255], 8).length, 1);
});
test('Color Walk preserves neutral tones and applies the bounded matte adjustment', () => {
  assert.equal(hex(walkColor([{r:0,g:0,b:0,fraction:1}])), '#090909');
  assert.equal(hex(walkColor([{r:255,g:255,b:255,fraction:1}])), '#FFFFFF');
  assert.equal(hex(walkColor([{r:255,g:0,b:0,fraction:1}])), '#F31E1E');
  const selected = walkColor([{r:0,g:0,b:0,fraction:.7}, {r:80,g:140,b:60,fraction:.3}]);
  assert.ok(selected.g > selected.r && selected.r > selected.b);
});
test('manual empty palette remains empty rather than reverting to automatic', () => {
  assert.deepEqual(effectivePalette({palette:[red], manualPalette:[]}), []);
  assert.deepEqual(effectivePalette({palette:[red]}), [red]);
});
test('automatic ink uses linear luminance and empty Color Walk input has a muted neutral fallback',()=>{
  assert.equal(contrastInk(red),'#232623');assert.equal(contrastInk(blue),'#FFFFFF');
  assert.equal(hex(walkColor([])),'#898989');
});
test('safe style restore validates enums, text, fonts and bounds', () => {
  const s = normalizeStyle({ template:'unknown', walkTextPosition:4, paletteCount:-8, ticketTitle:undefined, chineseFont:'missing-font', showHex:'yes' });
  assert.equal(s.template,'colorWalk'); assert.equal(s.walkTextPosition,.85); assert.equal(s.paletteCount,2);
  assert.equal(s.ticketTitle,'TICKETS'); assert.equal(s.chineseFont,'sans-serif'); assert.equal(s.showHex,true);
  assert.equal(defaults.walkTextPosition,.5);
});
test('independent landscape palette layout matches the specified margins', () => {
  const l = layout(1500,1000,{...defaults,template:'colorCircles'},1000);
  assert.deepEqual(l.photo,{x:20,y:20,w:960,h:640});
  assert.deepEqual(l.footer,{x:20,y:660,w:960,h:160}); assert.equal(l.height,820);
});
test('Color Walk unit layout preserves the whole image and 58.5 percent header', () => {
  const l = layout(1500,1000,defaults,1000);
  assert.equal(l.header.h,585); assert.equal(l.photo.y,585); assert.equal(l.height,1252);
  assert.equal(l.photo.w/l.photo.h,1.5);
});
test('all four templates respect the requested output long edge for portrait/landscape/square', () => {
  for (const template of ['colorWalk','colorCircles','colorSquares','tickets']) {
    for (const [w,h] of [[1500,1000],[1000,1500],[1000,1000]]) {
      const l = layoutForLongEdge(w,h,{...defaults,template},1920);
      assert.ok(Math.max(l.width,l.height)<=1920); assert.ok(l.photo.x>=0 && l.photo.y>=0);
      assert.ok(l.photo.x+l.photo.w<=l.width && l.photo.y+l.photo.h<=l.height);
      assert.ok(Math.abs(l.photo.w/l.photo.h-w/h)<.000001);
    }
  }
  assert.throws(()=>layoutForLongEdge(1,10000,defaults,1920));
});
test('Tickets independent geometry preserves a 604 pixel photo at 1000 canvas width', () => {
  const l = layout(1500,1000,{...defaults,template:'tickets'},1000);
  assert.deepEqual({x:l.photo.x,y:l.photo.y,w:l.photo.w},{x:198,y:147,w:604});
  assert.equal(l.card.x,170); assert.ok(Math.abs(l.card.y-119)<1e-9); assert.equal(l.height,902);
});
test('blur preserves constant colors and does not mutate its input', () => {
  const source = Uint8ClampedArray.from(Array.from({length:25},()=>[12,56,92,255]).flat());
  const result = blurRGBA(source,5,5,2); assert.deepEqual(result,source); assert.notEqual(result,source);
});
test('blur spreads an impulse symmetrically and validates dimensions', () => {
  const data = new Uint8ClampedArray(9*9*4); for(let i=0;i<81;i++)data[i*4+3]=255;
  data[(4*9+4)*4]=255; const b=blurRGBA(data,9,9,1);
  assert.ok(b[(4*9+4)*4]>0); assert.equal(b[(4*9+3)*4],b[(4*9+5)*4]);
  assert.throws(()=>blurRGBA(data,2,3,1));
});
test('Code 128 B has independently known start, checksum and stop symbols', () => {
  // A maps to 33; (start 104 + 33) modulo 103 = checksum 34.
  assert.equal(encodeCode128('A'),'0000000000'+'11010010000'+'10100011000'+'10001011000'+'1100011101011'+'0000000000');
  for(const invalid of ['','中文','x'.repeat(49),'A\nB'])assert.throws(()=>encodeCode128(invalid));
  assert.equal(encodeCode128(' A '),encodeCode128('A'));
  assert.throws(()=>barcodeGeometry('FRAMESTUDIO',100,2));
});
test('actual canvas pixels show whole photo, manual color and white palette footer', () => {
  const source=createCanvas(300,200), sc=source.getContext('2d'); sc.fillStyle='#00FF00';sc.fillRect(0,0,300,200);
  for(const [x,y,color] of [[0,0,'#FF0000'],[270,0,'#0000FF'],[0,170,'#FFFF00'],[270,170,'#00FFFF']]){sc.fillStyle=color;sc.fillRect(x,y,30,30);}
  for(const template of ['colorWalk','colorCircles','colorSquares','tickets']) {
    const s={...defaults,template}, l=layout(300,200,s,1000), c=createCanvas(l.width,l.height), ctx=c.getContext('2d');
    render(ctx,l,s,{image:source,imageWidth:300,imageHeight:200,palette:[red],walk:{r:169,g:105,b:107,fraction:1}});
    const p=l.photo;
    for(const [x,y,expected] of [[p.x+p.w*.05,p.y+p.h*.05,[255,0,0]], [p.x+p.w*.95,p.y+p.h*.05,[0,0,255]], [p.x+p.w*.05,p.y+p.h*.95,[255,255,0]], [p.x+p.w*.95,p.y+p.h*.95,[0,255,255]]]) {
      assert.deepEqual([...ctx.getImageData(Math.round(x),Math.round(y),1,1).data].slice(0,3),expected,template);
    }
    if(template==='colorWalk')assert.deepEqual([...ctx.getImageData(4,4,1,1).data].slice(0,3),[169,105,107]);
    if(template==='colorCircles')assert.deepEqual([...ctx.getImageData(1,l.height-3,1,1).data].slice(0,3),[255,255,255]);
  }
});
test('rendered Tickets has inward top perforations and side tear notch', () => {
  const source=createCanvas(300,200),sc=source.getContext('2d');sc.fillStyle='#004400';sc.fillRect(0,0,300,200);
  const s={...defaults,template:'tickets',ticketMark:'none'},l=layout(300,200,s,1000),c=createCanvas(l.width,l.height),ctx=c.getContext('2d');
  render(ctx,l,s,{image:source,imageWidth:300,imageHeight:200,palette:[],walk:red});
  const card=l.card, r=6.5, count=Math.floor(card.w/(r*4.4))|1, center=card.x+card.w/(count+1);
  assert.ok(ctx.getImageData(Math.round(center),card.y+2,1,1).data[1]<200);
  assert.ok(ctx.getImageData(card.x+3,card.y+2,1,1).data[0]>240);
  const separator=l.photo.y+l.photo.h+l.border*.5;
  assert.ok(ctx.getImageData(card.x+2,Math.round(separator),1,1).data[0]<150);
});
