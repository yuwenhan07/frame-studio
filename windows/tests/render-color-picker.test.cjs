const {test}=require('node:test');
const assert=require('node:assert/strict');
const {rgbToHsv,hsvToRgb,positionInPalette}=require('../.test-build/core/color-picker');
const {hex,parseHex}=require('../.test-build/core/palette');
test('HSV conversion matches independent primary, secondary and grey reference values',()=>{
  for(const [h,s,v,expected] of [[0,1,1,'#FF0000'],[60,1,1,'#FFFF00'],[120,1,1,'#00FF00'],[180,1,1,'#00FFFF'],[240,1,1,'#0000FF'],[300,1,1,'#FF00FF'],[360,1,1,'#FF0000'],[0,.5,.5,'#804040'],[0,0,.5,'#808080']])assert.equal(hex(hsvToRgb({h,s,v})),expected);
  assert.deepEqual(rgbToHsv(parseHex('#00FF00')),{h:120,s:1,v:1});assert.deepEqual(rgbToHsv(parseHex('#0000FF')),{h:240,s:1,v:1});
});
test('neutral colors preserve the last chosen hue and arbitrary RGB colors round-trip',()=>{
  assert.equal(rgbToHsv(parseHex('#000000'),230).h,230);assert.equal(rgbToHsv(parseHex('#FFFFFF'),180).h,180);
  for(const sample of ['#A9696B','#123456','#E1ACAC','#010101','#FA0001'])assert.equal(hex(hsvToRgb(rgbToHsv(parseHex(sample)))),sample);
});
test('touch geometry uses viewport coordinates and clamps outside all four sides',()=>{
  const r={left:100,top:200,width:200,height:80};assert.deepEqual(positionInPalette(150,220,r),{x:.25,y:.25});
  assert.deepEqual(positionInPalette(0,0,r),{x:0,y:0});assert.deepEqual(positionInPalette(1000,1000,r),{x:1,y:1});
  assert.equal(positionInPalette(NaN,0,r),undefined);assert.equal(positionInPalette(10,20,{...r,width:0}),undefined);
});
