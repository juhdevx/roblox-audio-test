// Decodes local video frames with Chromium and writes packed RGB frames.
const fs = require('node:fs');
const path = require('node:path');
const {withLocalMediaPage} = require('./local_media.cjs');
async function main() {
  const args = process.argv.slice(2), positional = [];
  let start = 0, maximumFrames = Infinity, metadataOnly = false;
  for (let index = 0; index < args.length; index++) {
    if (args[index] === '--start') start = Number(args[++index]);
    else if (args[index] === '--max-frames') maximumFrames = Number(args[++index]);
    else if (args[index] === '--metadata') metadataOnly = true;
    else if (args[index].startsWith('--')) throw Error('Unknown decoder option: ' + args[index]);
    else positional.push(args[index]);
  }
  const [input, output, widthText, fpsText] = positional;
  if (!input || !output) throw Error('Usage: node decode_video.cjs input.mp4 output.rgb [width] [fps]');
  if (!Number.isFinite(start) || start < 0 || (maximumFrames !== Infinity && (!Number.isSafeInteger(maximumFrames) || maximumFrames < 1))) throw Error('Invalid start time or frame limit');
  await withLocalMediaPage(input, async (page, url) => {
    const metadata = await page.evaluate(async url => {
      const video=document.createElement('video'); video.muted=true; video.preload='metadata';
      const loaded=new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>reject(Error('Video metadata timed out')),30000);
        video.onloadedmetadata=()=>{clearTimeout(timer);resolve();};
        video.onerror=()=>{clearTimeout(timer);reject(Error('Chromium cannot decode this video'));};
      });
      video.src=url; document.body.append(video); await loaded;
      globalThis.videoSource=video;
      return {duration:video.duration,width:video.videoWidth,height:video.videoHeight};
    },url);
    if (!Number.isFinite(metadata.duration) || metadata.duration <= 0 || metadata.duration > 3600) throw Error('Video must be between 0 and 3600 seconds');
    if (start >= metadata.duration) throw Error('Start time must precede the end of the video');
    const fps=Number((metadataOnly ? widthText : fpsText) || 10), requestedWidth=metadataOnly ? 128 : Number(widthText || 128);
    if (!Number.isFinite(fps)||fps<1||fps>30||!Number.isFinite(requestedWidth)||requestedWidth<16||requestedWidth>1024) throw Error('Invalid size or frame rate');
    const width=Math.min(requestedWidth,metadata.width);
    const height=Math.max(1,Math.round(width*metadata.height/metadata.width));
    const frames=Math.min(Math.ceil((metadata.duration-start)*fps),maximumFrames);
    const duration=maximumFrames===Infinity ? metadata.duration-start : Math.min(metadata.duration-start,frames/fps);
    const meta={...metadata,duration,sourceWidth:metadata.width,sourceHeight:metadata.height,width,height,fps,frames};
    if(start || maximumFrames!==Infinity) Object.assign(meta,{sourceDuration:metadata.duration,start});
    fs.mkdirSync(path.dirname(path.resolve(output)),{recursive:true});
    fs.writeFileSync(output+'.json',JSON.stringify(meta,null,2));
    console.log(JSON.stringify(meta));
    if (metadataOnly) return;
    await page.evaluate(async()=>{
      const video=globalThis.videoSource;video.preload='auto';
      if(video.readyState>=2)return;
      await new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>reject(Error('Initial video frame timed out')),45000);
        video.onloadeddata=()=>{clearTimeout(timer);resolve();};
        video.onerror=()=>{clearTimeout(timer);reject(Error('Chromium cannot read the initial video frame'));};
      });
    });
    await page.evaluate(({width,height})=>{const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;globalThis.videoCanvas=canvas;},meta);
    const fd=fs.openSync(output,'w');
    try {
      for(let first=0;first<meta.frames;first+=20) {
        const encoded=await page.evaluate(async ({first,count,fps,duration,start})=>{
          const video=globalThis.videoSource, canvas=globalThis.videoCanvas,context=canvas.getContext('2d',{willReadFrequently:true});
          context.imageSmoothingEnabled=true;context.imageSmoothingQuality='high';
          const combined=new Uint8Array(count*canvas.width*canvas.height*3);
          for(let offset=0;offset<count;offset++) {
            const target=Math.min(start+(first+offset)/fps,Math.max(0,start+duration-.001));
            if(Math.abs(video.currentTime-target)>0.00001) await new Promise((resolve,reject)=>{
              const timer=setTimeout(()=>reject(Error('Video seek timed out')),30000);
              video.onseeked=()=>{clearTimeout(timer);resolve();};
              video.onerror=()=>{clearTimeout(timer);reject(Error('Video seek failed'));};video.currentTime=target;
            });
            context.drawImage(video,0,0,canvas.width,canvas.height);
            const rgba=context.getImageData(0,0,canvas.width,canvas.height).data;
            let j=offset*canvas.width*canvas.height*3;for(let i=0;i<rgba.length;i+=4){combined[j++]=rgba[i];combined[j++]=rgba[i+1];combined[j++]=rgba[i+2];}
          }
          let text='';for(let i=0;i<combined.length;i+=32768)text+=String.fromCharCode(...combined.subarray(i,i+32768));return btoa(text);
        },{first,count:Math.min(20,meta.frames-first),fps,duration:meta.duration,start});
        fs.writeSync(fd,Buffer.from(encoded,'base64'));
        if(first%200===0) console.log(`Decoded ${Math.min(first+20,meta.frames)}/${meta.frames}`);
      }
    } finally {fs.closeSync(fd);}
  });
}
main().catch(error=>{console.error(error.stack || error.message);process.exit(1);});
