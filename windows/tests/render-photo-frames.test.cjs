const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, loadImage, Image, GlobalFonts } = require('@napi-rs/canvas');
for (const [font, family] of [['/System/Library/Fonts/STHeiti Light.ttc','sans-serif'],['/System/Library/Fonts/Supplemental/Songti.ttc','serif']]) if (fs.existsSync(font)) GlobalFonts.registerFromPath(font,family);
const { normalizeStyle } = require('../.test-build/core/model');
const { visibleFields } = require('../.test-build/core/collection-style');
const { layout, layoutForLongEdge } = require('../.test-build/core/layout');
const { render } = require('../.test-build/core/render');
const { backgroundBlur } = require('../.test-build/core/photo-frames');
const { blurRGBA } = require('../.test-build/core/blur');
const { brandMarks } = require('../.test-build/core/brand-marks');
const { drawBrand } = require('../.test-build/core/brand');
const pixel=(ctx,x,y)=>[...ctx.getImageData(Math.round(x),Math.round(y),1,1).data].slice(0,3);
function source(width=300,height=200) {
  const image=createCanvas(width,height),c=image.getContext('2d');c.fillStyle='#00FF00';c.fillRect(0,0,width,height);
  for(const [x,y,color] of [[0,0,'#FF0000'],[.9,0,'#0000FF'],[0,.9,'#FFFF00'],[.9,.9,'#00FFFF']]) {c.fillStyle=color;c.fillRect(width*x,height*y,width*.1,height*.1);}
  return image;
}
function input(image,bg) {return {image,imageWidth:image.width,imageHeight:image.height,background:bg,backgroundWidth:bg?.width,backgroundHeight:bg?.height,palette:[],walk:{r:145,g:100,b:90,fraction:1}};}
function draw(style,iw=300,ih=200) {
  const image=source(iw,ih),bg=createCanvas(2,2);bg.getContext('2d').fillStyle='#FF00FF';bg.getContext('2d').fillRect(0,0,2,2);
  const l=layout(iw,ih,style,1000),canvas=createCanvas(l.width,l.height),ctx=canvas.getContext('2d');render(ctx,l,style,input(image,bg));return {l,canvas,ctx};
}
test('three added presets have independent known landscape and portrait geometry',()=>{
  const expected={softFrame:[28,85,944,944*2/3,905],postage:[132,132,736,736*2/3,755],classic:[0,0,1000,1000*2/3,787]};
  for(const [template,[x,y,w,h,height]] of Object.entries(expected)) {
    const l=layout(1500,1000,normalizeStyle({template}));
    for(const [got,want] of [[l.photo.x,x],[l.photo.y,y],[l.photo.w,w],[l.photo.h,h]])assert.ok(Math.abs(got-want)<1e-7,template);
    assert.equal(l.height,height,template);
  }
  const p=layout(1000,1500,normalizeStyle({template:'softFrame'}));assert.equal(p.photo.x,80);assert.equal(p.photo.w,840);assert.equal(p.height,1535);
  const caption=layout(1500,1000,normalizeStyle({template:'postage',postage:{variant:'caption'}}));assert.equal(caption.height,855);assert.equal(caption.footer.h,100);
});
test('malformed new settings normalize without changing an older template or inventing camera data',()=>{
  const s=normalizeStyle({template:'tickets',ticketTitle:'我的照片',softFrame:{blur:99,portraitMargin:NaN,brightness:-5,brand:'REMOTE',camera:123},postage:{variant:'x',place:'A\nB'},classic:{arrangement:'x',showCamera:'yes'}});
  assert.equal(s.ticketTitle,'我的照片');assert.equal(s.softFrame.blur,.085);assert.equal(s.softFrame.brightness,-.5);assert.equal(s.softFrame.portraitMargin,.08);
  assert.equal(s.softFrame.brand,'nikon');assert.equal(s.softFrame.camera,'');assert.equal(s.softFrame.parameters,'');assert.equal(s.classic.parameters,'');assert.equal(s.classic.customDate,'');
  assert.equal(s.postage.variant,'plain');assert.equal(s.postage.place,'A B');assert.equal(s.classic.arrangement,'centered');assert.equal(s.classic.showCamera,false);
  const other=normalizeStyle({});s.softFrame.camera='edited';assert.equal(other.softFrame.camera,'');
});
test('dependent template fields reveal captions, manual brand and optional camera information',()=>{
  let s=normalizeStyle({});let keys=id=>visibleFields(id,s[id]).map(f=>f.key);
  assert.ok(!keys('postage').includes('place'));assert.ok(!keys('classic').includes('camera'));assert.ok(!keys('classic').includes('brandText'));
  s=normalizeStyle({postage:{variant:'caption'},classic:{brand:'custom',showCamera:true,showDate:true}});
  assert.ok(keys('postage').includes('place'));assert.ok(keys('classic').includes('camera'));assert.ok(keys('classic').includes('customDate'));assert.ok(keys('classic').includes('brandText'));
  s=normalizeStyle({softFrame:{showBrand:false,showParameters:false}});assert.ok(!keys('softFrame').includes('brand'));assert.ok(!keys('softFrame').includes('parameters'));
});
test('background preparation requests include zero blur and keep original Tickets strength',()=>{
  for(const [template,settings,want] of [['tickets',{},.025],['softFrame',{softFrame:{blur:0}},0],['postage',{postage:{blur:.08}},.08],['classic',{},undefined],['colorWalk',{},undefined]])
    assert.equal(backgroundBlur(normalizeStyle({template,...settings})),want);
  const pixels=Uint8ClampedArray.from([255,0,0,255,0,0,255,255]);const copy=blurRGBA(pixels,2,1,0);assert.deepEqual(copy,pixels);assert.notEqual(copy,pixels);
});
test('all three frames preserve foreground corner colors and portrait proportions',()=>{
  for(const template of ['softFrame','postage','classic'])for(const [iw,ih] of [[300,200],[200,300]]) {
    const {l,ctx}=draw(normalizeStyle({template} ),iw,ih),p=l.photo;
    for(const [x,y,color]of [[.05,.05,[255,0,0]],[.95,.05,[0,0,255]],[.05,.95,[255,255,0]],[.95,.95,[0,255,255]]])assert.deepEqual(pixel(ctx,p.x+p.w*x,p.y+p.h*y),color,template);
    assert.ok(Math.abs(p.w/p.h-iw/ih)<1e-8);
    for(const edge of [1024,1920,3840]){const bounded=layoutForLongEdge(iw,ih,normalizeStyle({template}),edge);assert.ok(Math.max(bounded.width,bounded.height)<=edge+1);}
  }
});
test('soft background brightness leaves the sharp photo untouched',()=>{
  for(const [brightness,want]of [[-.5,[128,0,128]],[.5,[255,128,255]]]) {
    const {l,ctx}=draw(normalizeStyle({template:'softFrame',softFrame:{brightness,shadow:0}}));assert.ok(pixel(ctx,500,5).every((v,i)=>Math.abs(v-want[i])<=1));assert.deepEqual(pixel(ctx,500,l.photo.y+l.photo.h/2),[0,255,0]);
  }
});
test('postage has real inward holes on all edges and keeps its white paper core',()=>{
  const {l,ctx}=draw(normalizeStyle({template:'postage',postage:{shadow:0}}));
  // Fixed coordinates from the default 1000px paper: x=105..895, y=105..649.667.
  for(const [x,y]of [[180,110],[180,645],[110,177],[890,177],[107,107]])assert.deepEqual(pixel(ctx,x,y),[255,0,255],`hole ${x},${y}`);
  assert.deepEqual(pixel(ctx,150,125),[255,254,252]);assert.deepEqual(pixel(ctx,500,l.photo.y+200),[0,255,0]);
});
test('eight offline brand marks have visible curves, authentic colors and enclosed letter counters',()=>{
  assert.equal(Object.keys(brandMarks).length,8);
  for(const [id,m]of Object.entries(brandMarks)) {
    assert.ok(m.bounds[2]>0&&m.bounds[3]>0,id);
    for(const mode of ['color','black','white']) {
      const canvas=createCanvas(500,180),c=canvas.getContext('2d');c.fillStyle=mode==='white'?'#222222':'#FFFFFF';c.fillRect(0,0,500,180);
      drawBrand(c,{x:15,y:15,w:470,h:150},id,'',normalizeStyle({}),mode);const data=c.getImageData(0,0,500,180).data;
      const bg=mode==='white'?34:255;let changed=0;for(let i=0;i<data.length;i+=4)if(data[i]!==bg||data[i+1]!==bg||data[i+2]!==bg)changed++;
      assert.ok(changed>300,id+' '+mode);assert.deepEqual(pixel(c,3,3),[bg,bg,bg]);
      if(id==='leica'&&mode==='color'){assert.ok(data.some((v,i)=>i%4===0&&v>180&&data[i+1]<80));assert.ok(data.some((v,i)=>i%4===0&&v>240&&data[i+1]>240&&data[i+2]>240));}
    }
  }
  const c=createCanvas(250,250).getContext('2d');c.fillStyle='#FFFFFF';c.fillRect(0,0,250,250);drawBrand(c,{x:15,y:15,w:220,h:220},'leica','',normalizeStyle({}));
  assert.deepEqual(pixel(c,15,15),[255,255,255]);assert.ok(pixel(c,125,40)[0]>150&&pixel(c,125,40)[1]<80);
});
test('all classic layouts and extreme frame settings remain finite and keep text in the footer',()=>{
  for(const template of ['softFrame','postage','classic'])for(const arrangement of ['centered','split','inline']) {
    const s=normalizeStyle({template,signature:'摄影师 Mixed '.repeat(12),softFrame:{margin:.15,portraitMargin:.15,footer:.13,textScale:1.5,brand:'leica',camera:'很长的型号 '.repeat(15),parameters:'24mm f/2.8 1/100 ISO200 '.repeat(8)},postage:{variant:'caption',border:.014,perforation:.022,footer:.07,textScale:2,place:'很长的地点 '.repeat(20),customDate:'2026/10/23'},classic:{arrangement,footer:.06,brand:'hasselblad',brandScale:2,infoScale:2,showCamera:true,camera:'CAMERA '.repeat(30),parameters:'24mm f/2.8 1/100 ISO200 '.repeat(10),showDate:true,customDate:'2026/10/23',showSignature:true}});
    const {l,ctx}=draw(s,200,300);assert.ok(Number.isFinite(l.height));assert.deepEqual(pixel(ctx,l.photo.x+l.photo.w/2,l.photo.y+l.photo.h-15),[0,255,0],template+' '+arrangement);
  }
});
