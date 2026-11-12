// Decodes local audio through Chromium's codec into stereo float32 PCM.
const fs = require('node:fs');
const path = require('node:path');
const {withLocalMediaPage} = require('../local_media.cjs');
async function main() {
 const [input, output] = process.argv.slice(2);
 if (!input || !output) throw Error('Usage: node decode_audio.cjs input.mp3 output.pcm');
 await withLocalMediaPage(input, async (page,url) => {
  const meta = await page.evaluate(async url=>{
   const response=await fetch(url,{signal:AbortSignal.timeout(180000)});
   if(!response.ok)throw Error('The local audio file could not be read');
   const bytes=await response.arrayBuffer();
   const ctx=new OfflineAudioContext(2,1,24000);
   const decoded=await ctx.decodeAudioData(bytes);
   if(!Number.isFinite(decoded.duration)||decoded.duration<=0||decoded.duration>3600)throw Error('Audio must be between 0 and 3600 seconds');
   globalThis.decodedAudio=decoded;
   return {sampleRate:decoded.sampleRate,frames:decoded.length,channels:2,duration:decoded.duration};
  },url);
  fs.mkdirSync(path.dirname(path.resolve(output)),{recursive:true});
  const fd=fs.openSync(output,'w');
  try {
   for(let first=0;first<meta.frames;first+=240000){
    const encoded=await page.evaluate(({first,count})=>{
     const decoded=globalThis.decodedAudio;
     const end=Math.min(first+count,decoded.length);
     const stereo=new Float32Array((end-first)*2);
     const left=decoded.getChannelData(0),right=decoded.getChannelData(Math.min(1,decoded.numberOfChannels-1));
     for(let i=first;i<end;i++){stereo[(i-first)*2]=left[i];stereo[(i-first)*2+1]=right[i];}
     const bytes=new Uint8Array(stereo.buffer);let binary='';
     for(let i=0;i<bytes.length;i+=32768) binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
     return btoa(binary);
    },{first,count:240000});
    fs.writeSync(fd,Buffer.from(encoded,'base64'));
   }
  } finally {fs.closeSync(fd);}
  fs.writeFileSync(output+'.json',JSON.stringify(meta,null,2));
  console.log(JSON.stringify(meta));
 });
}
main().catch(error=>{console.error(error.message);process.exit(1)});
