const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, loadImage, GlobalFonts } = require('@napi-rs/canvas');
// Optional local font fixtures; Windows uses its installed system fonts.
const cjkFixture = '/System/Library/Fonts/STHeiti Light.ttc';
if (fs.existsSync(cjkFixture)) GlobalFonts.registerFromPath(cjkFixture, 'sans-serif');
const serifFixture = '/System/Library/Fonts/Supplemental/Songti.ttc';
if (fs.existsSync(serifFixture)) GlobalFonts.registerFromPath(serifFixture, 'serif');
const { normalizeStyle, templates, activePaletteCount } = require('../.test-build/core/model');
const { collectionDefaults, collectionFields } = require('../.test-build/core/collection-style');
const { layout, layoutForLongEdge } = require('../.test-build/core/layout');
const { render } = require('../.test-build/core/render');
const { tornPoints } = require('../.test-build/core/paper-edge');
const { extractPalette, walkColor } = require('../.test-build/core/palette');
const newer = ['walkTicket','film35','gallery','editorial','instant','cinema','receipt','tornPaper'];
const red = {r:255,g:0,b:0,fraction:.5}, blue = {r:0,g:0,b:255,fraction:.5};
const input = image => ({image,imageWidth:image.width,imageHeight:image.height,palette:[red,blue],walk:red});
const pixel = (ctx,x,y) => [...ctx.getImageData(Math.round(x),Math.round(y),1,1).data].slice(0,3);
function source(width=300,height=200) {
  const image=createCanvas(width,height),ctx=image.getContext('2d');ctx.fillStyle='#00FF00';ctx.fillRect(0,0,width,height);
  for(const [x,y,c] of [[0,0,'#FF0000'],[.9,0,'#0000FF'],[0,.9,'#FFFF00'],[.9,.9,'#00FFFF']]){ctx.fillStyle=c;ctx.fillRect(x*width,y*height,width*.1,height*.1);}
  return image;
}
function draw(s,iw=300,ih=200,width=1000) {
  const image=source(iw,ih),l=layout(iw,ih,s,width),canvas=createCanvas(l.width,l.height),ctx=canvas.getContext('2d');
  render(ctx,l,s,input(image));return {l,canvas,ctx};
}
test('fifteen templates include the renamed film frame and omit the retired contact sheet',()=>{
  assert.equal(templates.length,15);assert.equal(templates.find(t=>t.id==='film35').name,'胶片相框');assert.equal(templates.some(t=>t.id==='contactSheet'),false);
  assert.equal(normalizeStyle({template:'contactSheet'}).template,'film35');
});
test('new defaults match the current Mac presets and never alias one another',()=>{
  const a=normalizeStyle({}),b=normalizeStyle({});
  assert.equal(a.walkStripeCount,4);assert.equal(a.walkTicket.title,'COLOR WALK');assert.equal(a.walkTicket.photoMode,'fit');
  assert.equal(a.film35.label,'FILM');assert.equal(a.tornPaper.showCaptionArea,false);assert.equal(a.tornPaper.border,.009);assert.equal(a.tornPaper.roughness,.0035);
  a.gallery.title='edited';assert.equal(b.gallery.title,'');assert.equal(collectionDefaults.gallery.title,'');
});
test('old four-template styles gain safe nested defaults while malformed fields are rejected',()=>{
  const s=normalizeStyle({template:'tickets',ticketTitle:'Beijing',gallery:{title:'作品',paper:'unknown',margin:99},tornPaper:{roughness:NaN,shadow:Infinity,showCaptionArea:'yes'},walkTicket:null});
  assert.equal(s.ticketTitle,'Beijing');assert.equal(s.gallery.title,'作品');assert.equal(s.gallery.paper,'ivory');assert.equal(s.gallery.margin,.18);
  assert.equal(s.tornPaper.roughness,.0035);assert.equal(s.tornPaper.shadow,.18);assert.equal(s.tornPaper.showCaptionArea,false);assert.equal(s.walkTicket.theme,'charcoal');
  assert.equal(normalizeStyle({film35:{label:'FRAME 35'}}).film35.label,'FILM');
  assert.equal(normalizeStyle({tornPaper:{border:.04}}).tornPaper.border,.009);
  assert.equal(normalizeStyle({tornPaper:{border:.04,showCaptionArea:true}}).tornPaper.border,.04);
});
test('nested HEX, fonts, flags and text are constrained independently',()=>{
  const s=normalizeStyle({editorial:{customHex:'abcdef',accent:'custom',title:'A\nB',titleFont:'Remote Font',notes:'x'.repeat(500)},walkTicket:{paletteCount:7.9,theme:'custom',customHex:'#fFA969'}});
  assert.equal(s.editorial.customHex,'#ABCDEF');assert.equal(s.editorial.title,'A B');assert.equal(s.editorial.titleFont,'serif');assert.equal(s.editorial.notes.length,200);
  assert.equal(s.walkTicket.paletteCount,8);assert.equal(s.walkTicket.customHex,'#FFA969');
});
test('palette requests follow the active template without erasing other counts',()=>{
  const s=normalizeStyle({paletteCount:7,walkStripeCount:3,walkTicket:{paletteCount:6}});
  assert.equal(activePaletteCount({...s,template:'colorCircles'}),7);
  assert.equal(activePaletteCount({...s,template:'colorWalk',walkBackground:'horizontalStripes'}),3);
  assert.equal(activePaletteCount({...s,template:'walkTicket'}),6);
});
test('independent new layout examples preserve specified borders and footer sizes',()=>{
  const shapes={film35:[65,85,870,580,750],gallery:[100,100,800,800*2/3,794],editorial:[55,230,890,890*2/3,944],
    instant:[105,105,790,790*2/3,847],cinema:[0,65,1000,1000*2/3,902],receipt:[135,250,730,730*2/3,1097],tornPaper:[79,79,842,842*2/3,720]};
  for(const [template,[x,y,w,h,height]] of Object.entries(shapes)) {
    const l=layout(1500,1000,normalizeStyle({template}),1000);
    for(const [got,expected] of [[l.photo.x,x],[l.photo.y,y],[l.photo.w,w],[l.photo.h,h]])assert.ok(Math.abs(got-expected)<1e-8,template);
    assert.equal(l.height,height,template);
  }
  const portrait=layout(1000,1500,normalizeStyle({template:'gallery'}),1000);assert.ok(Math.abs(portrait.photo.x-120)<1e-9);
  const ticket=layout(1000,1500,normalizeStyle({template:'walkTicket'}),1000);
  assert.equal(ticket.height,536);assert.equal(ticket.card.x,90);assert.ok(Math.abs(ticket.photoSlot.w-250.1)<1e-9);assert.ok(Math.abs(ticket.photo.w/ticket.photo.h-2/3)<1e-9);
});
test('all fifteen templates retain aspect and canvas bounds at three photo orientations',()=>{
  for(const {id:template} of templates)for(const [iw,ih] of [[1500,1000],[1000,1500],[1000,1000]]) {
    const l=layoutForLongEdge(iw,ih,normalizeStyle({template}),1920),p=l.photo;
    assert.ok(Math.max(l.width,l.height)<=1920,template);assert.ok(p.x>=0&&p.y>=0&&p.x+p.w<=l.width&&p.y+p.h<=l.height,template);
    assert.ok(Math.abs(p.w/p.h-iw/ih)<1e-8,template);
  }
});
test('Walk Ticket fit and explicit fill have different photo bounds without changing the card',()=>{
  const fit=layout(1500,1000,normalizeStyle({template:'walkTicket'}),1000);
  const crop=layout(1500,1000,normalizeStyle({template:'walkTicket',walkTicket:{photoMode:'fill'}}),1000);
  assert.deepEqual(crop.photo,crop.photoSlot);assert.deepEqual(fit.card,crop.card);
  assert.ok(fit.photo.h<fit.photoSlot.h);assert.ok(Math.abs(fit.photo.w-fit.photoSlot.w)<1e-9);
});
test('real canvas pixels preserve corner landmarks for all new templates and orientations',()=>{
  for(const template of newer)for(const [iw,ih] of [[300,200],[200,300],[200,200]]) {
    const {l,ctx}=draw(normalizeStyle({template}),iw,ih),p=l.photo;
    for(const [x,y,color] of [[.05,.05,[255,0,0]],[.95,.05,[0,0,255]],[.05,.95,[255,255,0]],[.95,.95,[0,255,255]]])assert.deepEqual(pixel(ctx,p.x+p.w*x,p.y+p.h*y),color,`${template} ${iw}×${ih}`);
  }
});
test('torn edges are deterministic, scale with the canvas, and have irregular depths',()=>{
  const r={x:10,y:20,w:800,h:600},points=tornPoints(r,14,2.8);
  assert.deepEqual(points,tornPoints(r,14,2.8));assert.notDeepEqual(points,tornPoints(r,14,2.8,123));
  const doubled=tornPoints({x:20,y:40,w:1600,h:1200},28,5.6);
  assert.equal(points.length,doubled.length);points.forEach((p,i)=>{assert.ok(Math.abs(p.x*2-doubled[i].x)<1e-8);assert.ok(Math.abs(p.y*2-doubled[i].y)<1e-8);});
  assert.ok(new Set(points.slice(0,80).map(p=>p.y.toFixed(3))).size>25);
  assert.ok(points.every(p=>p.x>=10&&p.x<=810&&p.y>=20&&p.y<=620));
});
test('torn paper has a narrow light core, grey exterior and an optional caption area',()=>{
  const s=normalizeStyle({template:'tornPaper'}),{l,ctx}=draw(s);
  assert.deepEqual(pixel(ctx,3,3),[106,101,93]);assert.deepEqual(pixel(ctx,l.width/2,l.height/2),[0,255,0]);
  // The straight rectangle edge exposes several background/white transitions; a sawtooth preset would repeat uniformly.
  const samples=[];for(let x=100;x<900;x+=7)samples.push(pixel(ctx,x,73).join(','));assert.ok(new Set(samples).size>3);
  const withCaption=layout(300,200,normalizeStyle({template:'tornPaper',tornPaper:{showCaptionArea:true}}),1000);
  assert.equal(withCaption.height-l.height,111);assert.equal(withCaption.photo.h,l.photo.h);
});
test('sprockets, gallery outline and receipt bottom teeth can be seen in real pixels',()=>{
  const film=draw(normalizeStyle({template:'film35'}));assert.deepEqual(pixel(film.ctx,96,15),[232,227,216]);
  const off=draw(normalizeStyle({template:'film35',film35:{showSprockets:false}}));assert.deepEqual(pixel(off.ctx,96,15),[22,23,22]);
  const gallery=draw(normalizeStyle({template:'gallery'}));assert.notDeepEqual(pixel(gallery.ctx,95,200),[247,243,234]);
  const receipt=draw(normalizeStyle({template:'receipt'})),card=receipt.l.card;
  const row=[];for(let x=card.x+10;x<card.x+100;x++)row.push(pixel(receipt.ctx,x,card.y+card.h-3).join(','));assert.ok(new Set(row).size>2);
});
test('stripe colors use exact integer bands, keep photo unchanged, and permit manual empty palettes',()=>{
  const s=normalizeStyle({walkBackground:'horizontalStripes',walkStamp:'',walkDetail:''}),image=source(),l=layout(300,200,s,1000),c=createCanvas(l.width,l.height),ctx=c.getContext('2d');
  render(ctx,l,s,input(image));assert.deepEqual(pixel(ctx,4,292),[255,0,0]);assert.deepEqual(pixel(ctx,4,293),[0,0,255]);
  assert.deepEqual(pixel(ctx,4,584),[0,0,255]);assert.deepEqual(pixel(ctx,5,590),[255,0,0]);
  render(ctx,l,s,{...input(image),palette:[]});assert.deepEqual(pixel(ctx,4,292),[255,255,255]);
});
test('automatic stamp ink changes across the dark/light stripe beneath the same glyph',()=>{
  const s=normalizeStyle({walkBackground:'horizontalStripes',walkInk:'auto',walkStamp:'MMMMMMMM',walkTextPosition:.5}),image=source(),l=layout(300,200,s,1000),c=createCanvas(l.width,l.height),ctx=c.getContext('2d');
  render(ctx,l,s,{...input(image),palette:[{r:0,g:0,b:0,fraction:.5},{r:255,g:255,b:255,fraction:.5}]});
  let white=0,dark=0;for(let y=278;y<307;y++)for(let x=300;x<700;x++) {
    const [r,g,b]=pixel(ctx,x,y);if(y<293&&r>240&&g>240&&b>240)white++;if(y>=293&&r<55&&g<55&&b<55)dark++;
  }
  assert.ok(white>100);assert.ok(dark>100);
});
test('extreme settings render finite geometry and clip long titles on actual canvases',()=>{
  for(const template of newer)for(const end of ['min','max']) {
    const v={};for(const f of collectionFields[template])if(f.type==='number')v[f.key]=f[end];else if(f.type==='text')v[f.key]='很长的中文 Mixed title '.repeat(20);
    if(template==='tornPaper')v.showCaptionArea=true;
    const s=normalizeStyle({template,[template]:v,signature:'signature '.repeat(20)}),{l,ctx}=draw(s,200,300,700);
    assert.ok(Number.isFinite(l.height));assert.ok(l.photo.w>0);assert.equal(ctx.getImageData(0,0,1,1).data[3],255);
  }
});
