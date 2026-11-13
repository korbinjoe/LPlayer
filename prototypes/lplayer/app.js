(() => {
'use strict';
const $ = id => document.getElementById(id);
const app = $('app'), video = $('video'), stage = $('stage');
const defaults = {hand:'left',theme:'dark',subtitles:true,private:false,speed:1,volume:70,motion:true,previews:true,brandFont:'manrope'};
let saved = {};
try { saved = JSON.parse(localStorage.getItem('lplayer-visual-preferences') || '{}'); } catch {}
const s = {...defaults,...saved,loaded:true,current:0,selected:0,track:'zh',delay:0,zoom:100,playlist:false,gallery:false};
s.speed = Math.max(.25, Math.min(3, Number(s.speed) || 1));
s.volume = Math.max(0, Math.min(100, Number(s.volume) || 0));
const items = [
  {title:'北岸 · 冰岛海岸',name:'North of the ordinary.mp4',note:'海岸与晨光',image:'assets/coast-cinema.png',src:'assets/coast-preview.mp4',duration:36,start:8},
  {title:'在路上 · 雾中的公路',name:'The road north.mp4',note:'往山谷深处',image:'assets/road-cinema.png',src:'assets/road-preview.mp4',duration:28,start:3},
  {title:'高地 · 瀑布与苔原',name:'Where the water falls.mp4',note:'高原的呼吸',image:'assets/falls-cinema.png',src:'assets/falls-preview.mp4',duration:32,start:4}
];
const subs = {
  zh:[['向北，直到世界安静下来。','山与海，在这里相遇。','有些风景，值得慢一点。','把时间留给眼前的风景。'],['前方，是一条没有尽头的路。','穿过雾气，慢慢走向山谷。','这一次，不必急着抵达。'],['水流落下，山谷有了回声。','苔原向远处延伸。','风景不说话，我们也安静下来。']],
  en:[['North, until the world grows quiet.','Where the mountains meet the sea.','Some views deserve a little more time.','Stay a while.'],['A road that seems to go on forever.','Through the mist, into the valley.','There is no need to hurry.'],['The valley echoes with falling water.','The highlands stretch into the distance.','A moment to be still.']]
};
const speeds = [.25,.5,.75,1,1.25,1.5,1.75,2,2.5,3];
let menu = null, anchor = null, hideTimer, hudTimer, toastTimer, stageClickTimer;
let lastVolume = s.volume || 70, qIndex = 0, pendingStart = 8, dragDepth = 0, seekBefore = null;
const icon = (name, cls = '') => `<span class="icon ${cls}" style="--icon:url('assets/icons/${name}.svg')" aria-hidden="true"></span>`;
const esc = text => String(text).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt = n => { n = Math.max(0,Math.floor(n || 0)); return `${String(Math.floor(n/60)).padStart(2,'0')}:${String(n%60).padStart(2,'0')}`; };
const helpOpen = () => Boolean(window.LPlayerDialogs?.isHelpOpen?.());
const quickRows = () => [...$('quick-panel').querySelectorAll('[data-qrow]')];
const menuButtons = el => [...el.querySelectorAll('button:not(:disabled)')].filter(button=>!button.hidden);
const keysForHand = () => s.hand === 'right' ? {up:'i',down:'k',back:'j',forward:'l',slower:'u',faster:'o',normal:'p',previous:'i',next:'k',panel:',',list:"'",help:'y',full:'h',subtitle:';',undo:'m',zoomOut:'8',zoomIn:'9',zoomFit:'7'} : {up:'w',down:'s',back:'a',forward:'d',slower:'q',faster:'e',normal:'r',previous:'w',next:'s',panel:'c',list:'t',help:'v',full:'f',subtitle:'g',undo:'z',zoomOut:'2',zoomIn:'3',zoomFit:'1'};
function hydrate(){ document.querySelectorAll('[data-icon]').forEach(el=>{el.style.setProperty('--icon',`url('assets/icons/${el.dataset.icon}.svg')`);el.setAttribute('aria-hidden','true');}); }
function changeIcon(button,name){ button.querySelector('.icon').style.setProperty('--icon',`url('assets/icons/${name}.svg')`); }
function fill(input){ const max = +input.max || 100, min = +input.min || 0; input.style.setProperty('--fill',`${100*(+input.value-min)/(max-min)}%`); }
function syncFullscreenTransport(){
  const sidebar=[s.playlist?$('playlist'):null,helpOpen()?$('lp-help-rail'):null].find(el=>el&&!el.hidden&&getComputedStyle(el).display!=='none');
  const width=document.fullscreenElement===app&&sidebar?sidebar.getBoundingClientRect().width:0;
  app.style.setProperty('--fullscreen-sidebar-width',`${width}px`);
  syncTransportLayout();
}
function syncTransportLayout(){
  const width=$('transport').getBoundingClientRect().width;
  $('previous').hidden=$('next').hidden=width<950;
  $('quick-toggle').hidden=width<600;
  $('speed-button').hidden=width<520;
  $('volume').hidden=width<700;
  $('transport').classList.toggle('compact-volume',width<700);
  $('current-time').classList.toggle('current-only',width<500);
  $('captions-button').hidden=$('fullscreen').hidden=width<420;
  $('quick-menu').hidden=width>=600;
  $('speed-control-menu').hidden=width>=520;
  $('fullscreen-menu').hidden=width>=420;
}
function toast(text){ $('toast').textContent=text;$('toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('visible'),2100); }
function hud(text){ $('hud').textContent=text;$('hud').classList.add('visible');clearTimeout(hudTimer);hudTimer=setTimeout(()=>$('hud').classList.remove('visible'),1100); }
function save(){ const prefs={};Object.keys(defaults).forEach(k=>prefs[k]=s[k]);try{localStorage.setItem('lplayer-visual-preferences',JSON.stringify(prefs));}catch{} }
function setPreference(key,value){
  if(!(key in defaults))return;
  if(key==='speed')return speed(Number(value),false);
  if(key==='volume')return volume(Number(value),false);
  s[key]=value;apply();if(key==='previews')queue();save();
}
window.LPlayerUI = {getState:()=>({...s}),setPreference,toast,openSettings:settings,onHelpChange:()=>{syncFullscreenTransport();hideLater();},prepareHelp:()=>{closeMenus();closeQuick();playlist(false);}};
function syncSpeedSelect(select){
  const options = [...speeds];
  if(!options.some(n=>Math.abs(n-s.speed)<.001))options.push(s.speed);
  options.sort((a,b)=>a-b);
  const signature = options.join('|');
  if(select.dataset.options!==signature){select.innerHTML=options.map(n=>`<option value="${n}">${n}×${n===1?' 正常':''}</option>`).join('');select.dataset.options=signature;}
  select.value=String(s.speed);
}
function apply(){
  const k=keysForHand(), pair=(a,b)=>`${a.toUpperCase()}/${b.toUpperCase()}`;
  document.body.dataset.brandFont=['manrope','outfit','space'].includes(s.brandFont)?s.brandFont:'manrope';
  document.body.dataset.theme=s.theme;document.body.classList.toggle('reduced-motion',!s.motion);
  $('rewind').title=`后退 5 秒 · ${k.back.toUpperCase()} / ← · Shift 后退 30 秒`;
  $('forward').title=`前进 5 秒 · ${k.forward.toUpperCase()} / → · Shift 前进 30 秒`;
  $('previous').title=`上一个视频 · ${k.previous.toUpperCase()} / ↑`;$('next').title=`下一个视频 · ${k.next.toUpperCase()} / ↓`;
  $('playlist-toggle').title=`播放列表 · ${k.list.toUpperCase()}`;$('quick-toggle').title=`快捷调节 · ${k.panel.toUpperCase()}`;
  $('speed-button').title=`播放速度 · 打开快捷面板首行 · ${pair(k.slower,k.faster)} 调整`;
  $('speed-menu').querySelector('.menu-hint').textContent=`${pair(k.slower,k.faster)} 调节 · ${k.normal.toUpperCase()} 恢复`;
  $('volume').title=`音量 · Shift+${pair(k.up,k.down)} / Shift+↑↓ 增大 / 减小`;
  $('quick-zoom').title=`画面缩放 · ${k.zoomOut} / ${k.zoomIn} 缩小 / 放大 · 兼容 - / = / + · 每次 25% · ${k.zoomFit} / 0 / ⌘0 复原`;
  $('reset-zoom').title=`画面适应窗口 · ${k.zoomFit} / 0 / ⌘0`;
  $('captions-button').title=`显示 / 隐藏字幕 · ${k.subtitle.toUpperCase()}`;$('captions-button').setAttribute('aria-label',s.subtitles?'隐藏字幕':'显示字幕');
  $('help-button').title=`快捷键帮助 · ${k.help.toUpperCase()}`;
  document.querySelectorAll('[data-help-shortcut]').forEach(el=>el.textContent=k.help.toUpperCase());
  document.querySelectorAll('[data-panel-shortcut]').forEach(el=>el.textContent=k.panel.toUpperCase());
  $('quick-keyhint').innerHTML=`<kbd>${pair(k.up,k.down)}</kbd> 选择 <kbd>${pair(k.back,k.forward)}</kbd> 调整`;
  $('quick-keyhint').title=`${pair(k.up,k.down)} 或 ↑↓ 选择，${pair(k.back,k.forward)} 或 ←→ 调整，Space / Enter 确认，Esc 收起`;
  $('playlist-keyhint').innerHTML=`<kbd>${pair(k.up,k.down)}</kbd> / ↑↓ 选择 · <kbd>↵</kbd> 播放`;
  $('playlist-close-hint').innerHTML=`<kbd>${k.list.toUpperCase()}</kbd> / <kbd>Esc</kbd> 收起`;
  $('playlist-keyhint').title=`${pair(k.up,k.down)} 或 ↑↓ 选择并静音预览；${pair(k.back,k.forward)} 或 ←→ 跳转当前视频 5 秒，Shift 跳转 30 秒；Space / Enter 确认；鼠标单击直接播放；Home / End 首尾；${k.list.toUpperCase()} / Esc 收起`;
  $('privacy-badge').hidden=!s.private;$('private-menu').setAttribute('aria-checked',String(s.private));$('quick-private').checked=s.private;
  $('quick-subtitles').checked=s.subtitles;$('captions-button').classList.toggle('active',s.subtitles);$('captions-button').setAttribute('aria-pressed',String(s.subtitles));
  video.volume=s.volume/100;video.muted=s.volume===0;video.playbackRate=s.speed;
  for(const id of ['volume','quick-volume']){$(id).value=s.volume;fill($(id));}
  $('quick-volume-value').textContent=`${s.volume}%`;changeIcon($('mute'),s.volume===0?'speaker-slash':'speaker-high');$('mute').setAttribute('aria-label',s.volume===0?'取消静音':'静音');
  $('speed-button').textContent=`${s.speed}×`;syncSpeedSelect($('quick-speed'));
  $('quick-track').value=s.track;$('quick-track').disabled=Boolean(items[s.current]?.local);$('quick-track').closest('[data-qrow]').setAttribute('aria-disabled',String(Boolean(items[s.current]?.local)));$('quick-hand').value=s.hand;
  $('captions-menu').querySelectorAll('[data-subtitle]').forEach(b=>b.setAttribute('aria-checked',String(b.dataset.subtitle===(s.subtitles?s.track:'off'))));
  $('previous').disabled=!s.loaded||s.current===0;$('next').disabled=!s.loaded||s.current===items.length-1;
  if(!s.previews)$('seek-preview').hidden=true;
  updateSub();window.LPlayerDialogs?.refreshHelp?.();
}
function volume(n,feedback=true){if(!Number.isFinite(n))return;s.volume=Math.max(0,Math.min(100,Math.round(n)));if(s.volume>0)lastVolume=s.volume;apply();save();if(feedback)hud(s.volume?`音量 ${s.volume}%`:'已静音');}
function mute(){volume(s.volume===0?lastVolume:0);}
function speed(n,feedback=true){if(!Number.isFinite(n))return;s.speed=Math.round(Math.max(.25,Math.min(3,n))*100)/100;apply();save();if(feedback)hud(s.speed===1?'正常速度':`${s.speed}× 速度`);}
function shiftSpeed(delta){speed(s.speed+delta*.1);}
function zoom(n){if(!Number.isFinite(n))return;s.zoom=Math.max(100,Math.min(500,n));$('media-frame').style.transform=`scale(${s.zoom/100})`;$('quick-zoom').value=s.zoom;fill($('quick-zoom'));$('quick-zoom-value').textContent=s.zoom===100?'适应':`${s.zoom}%`;$('reset-zoom').hidden=s.zoom===100;$('reset-zoom').textContent=`${s.zoom}% · 复原`;}
function updateSub(){const list=subs[s.track]?.[Math.min(s.current,2)]||subs.zh[0];$('subtitle').hidden=!s.loaded||!s.subtitles||Boolean(items[s.current]?.local);$('subtitle').firstElementChild.textContent=list[Math.floor(Math.max(0,(video.currentTime||0)-s.delay)/9)%list.length];}
function subtitles(value){s.subtitles=value;apply();save();hud(value?'字幕已开启':'字幕已关闭');}
function delay(n){s.delay=Math.round((s.delay+n)*10)/10;$('delay-value').textContent=`${s.delay>0?'+':''}${s.delay.toFixed(1)} s`;updateSub();}
function updateTime(){if(!s.loaded)return;const d=Number.isFinite(video.duration)?video.duration:items[s.current].duration;$('seek').max=d;$('seek').value=video.currentTime||0;fill($('seek'));$('current-time').innerHTML=`<span class="time-current">${fmt(video.currentTime)}</span><span class="time-total"> / ${fmt(d)}</span>`;$('current-time').setAttribute('aria-label',`${fmt(video.currentTime)}，共 ${fmt(d)}`);$('seek').setAttribute('aria-valuetext',`${fmt(video.currentTime)}，共 ${fmt(d)}`);updateSub();}
function hideLater(){clearTimeout(hideTimer);app.classList.remove('hide-chrome');if(document.fullscreenElement===app&&!video.paused&&!menu&&$('quick-panel').hidden&&!helpOpen()&&!s.playlist&&!window.LPlayerDialogs?.isOpen())hideTimer=setTimeout(()=>app.classList.add('hide-chrome'),2800);}
function updatePlay(){const playing=s.loaded&&!video.paused;changeIcon($('play'),playing?'pause-fill':'play-fill');$('play').classList.toggle('is-playing',playing);$('play').setAttribute('aria-label',playing?'暂停':'播放');$('play').title=playing?'暂停 · Space':'播放 · Space';stage.classList.toggle('playing',playing);hideLater();}
async function startPlayback(){try{await video.play();}catch(error){if(error?.name!=='AbortError')toast('当前浏览器无法播放此文件，请尝试 MP4 或 WebM。');}updatePlay();}
async function play(){if(!s.loaded)return openFiles();if(video.paused){if(video.ended)video.currentTime=0;await startPlayback();}else{video.pause();updatePlay();}}
function seek(n){if(!s.loaded)return;seekBefore=video.currentTime;video.currentTime=Math.max(0,Math.min(Number.isFinite(video.duration)?video.duration:items[s.current].duration,video.currentTime+n));updateTime();hideLater();}
function stepVideo(n){if(!s.loaded||!items.length)return;const next=s.current+n;if(next<0||next>=items.length){hud(n<0?'已经是第一个视频':'已经是最后一个视频');return;}load(next);}
function queue(){
  const list=$('queue-list');
  list.innerHTML=items.map((item,i)=>`<div class="queue-item ${i===s.current?'current':''} ${i===s.selected?'selected':''}" role="option" aria-selected="${i===s.selected}" aria-label="${esc(item.title)}${i===s.current?'，正在播放':''}，单击播放" tabindex="${i===s.selected?'0':'-1'}" data-index="${i}">${i===s.selected&&i!==s.current&&s.previews&&s.playlist?`<video class="queue-thumb queue-motion" src="${item.src}" poster="${item.image}" autoplay muted loop playsinline preload="metadata"></video>`:`<img class="queue-thumb" src="${item.image}" alt="">`}<div class="queue-text"><div class="queue-name">${esc(item.title)}</div><div class="queue-sub">${i===s.current?icon('play-fill'):''}<span>${i===s.current?'正在播放':(i===s.selected&&s.previews?'静音预览':esc(item.note))}</span><span class="queue-duration">${fmt(item.duration)}</span></div></div><button class="queue-play" aria-label="播放 ${esc(item.title)}" data-play="${i}">${icon('play-fill')}</button></div>`).join('');
  $('queue-count').textContent=items.length;$('queue-current').textContent=s.loaded?`正在播放 ${s.current+1}`:'未播放';$('selection-preview').hidden=s.selected===s.current||!s.loaded;$('selection-name').textContent=items[s.selected]?.title||'';
}
function select(i,focus=false){if(!items.length)return;s.selected=Math.max(0,Math.min(items.length-1,i));queue();const row=$('queue-list').querySelector(`[data-index="${s.selected}"]`);if(focus){row?.focus({preventScroll:true});row?.scrollIntoView({block:'nearest',behavior:'instant'});}}
function load(i,autoplay=true){
  const item=items[i];if(!item)return;
  video.pause();s.current=i;s.selected=i;s.loaded=true;pendingStart=item.start||0;seekBefore=null;
  video.src=item.src;video.poster=item.image;video.dataset.playAfterLoad=String(autoplay);video.load();
  $('file-title').textContent=item.title;$('info-name').textContent=item.name;$('info-details').textContent=item.local?'正在读取视频信息':`1280 × 720 · 25 fps · ${fmt(item.duration)}`;$('scene-pill').textContent=item.local?'本地影片':`短片 · ${item.title.split(' · ')[0]}`;$('seek-preview').querySelector('img').src=item.image;
  app.classList.remove('empty');$('empty-state').hidden=true;zoom(100);queue();updatePlay();closeMenus();apply();stage.focus({preventScroll:true});
}
function activate(i=s.selected){
  if(!items[i])return;
  s.selected=i;
  if(s.loaded&&i===s.current&&!video.error){queue();video.dataset.playAfterLoad='true';startPlayback();stage.focus({preventScroll:true});}
  else load(i,true);
}
function closeMedia(){video.pause();s.loaded=false;app.classList.add('empty');$('file-title').textContent='未打开视频';$('empty-state').hidden=false;playlist(false);closeMenus();closeQuick();window.LPlayerDialogs?.closeHelp?.();apply();updateSub();}
function openFiles(){$('file-input').click();}
function ingest(files){const valid=[...files].filter(f=>f.type.startsWith('video/')||/\.(mp4|mov|mkv|webm|m4v|avi)$/i.test(f.name));if(!valid.length)return toast('请选择视频文件。');closeQuick();const start=items.length;for(const f of valid)items.push({title:f.name.replace(/\.[^.]+$/,''),name:f.name,note:'本地视频',src:URL.createObjectURL(f),image:'assets/app-icon.png',duration:0,start:0,local:true});$('folder-label').textContent='本地视频';load(start,true);toast(`已打开 ${valid.length} 个本地视频`);}
function playlist(value=!s.playlist){
  if(value){closeQuick();window.LPlayerDialogs?.closeHelp?.();}
  const opening=value&&!s.playlist;s.playlist=value;$('playlist').hidden=!value;
  $('playlist-toggle').setAttribute('aria-label',value?'收起播放列表':'打开播放列表');$('playlist-toggle').setAttribute('aria-pressed',String(value));$('playlist-toggle').classList.toggle('active',value);
  if(opening)select(s.current,true);else if(!value){queue();if($('playlist').contains(document.activeElement))stage.focus({preventScroll:true});}
  syncFullscreenTransport();hideLater();
}
function closeMenus(restore=false){if(menu){menu.hidden=true;anchor?.setAttribute('aria-expanded','false');if(restore)anchor?.focus({preventScroll:true});}menu=null;anchor=null;hideLater();}
function showMenu(el,button){if(menu===el)return closeMenus();closeMenus();menu=el;anchor=button;el.hidden=false;button.setAttribute('aria-expanded','true');const r=button.getBoundingClientRect(),m=el.getBoundingClientRect();let x=r.right-m.width,y=r.top-m.height-9;if(r.top<100){x=r.left;y=r.bottom+8;}el.style.left=`${Math.max(8,Math.min(innerWidth-m.width-8,x))}px`;el.style.top=`${Math.max(8,Math.min(innerHeight-m.height-8,y))}px`;menuButtons(el)[0]?.focus({preventScroll:true});hideLater();}
function closeQuick(){if($('quick-panel').contains(document.activeElement))stage.focus({preventScroll:true});$('quick-panel').hidden=true;stage.classList.remove('quick-open');$('quick-toggle').classList.remove('active');$('quick-toggle').setAttribute('aria-expanded','false');$('speed-button').setAttribute('aria-expanded','false');hideLater();}
function markQuick(i){const rows=quickRows();if(!rows.length)return;qIndex=(i+rows.length)%rows.length;rows.forEach((row,index)=>{row.classList.toggle('focused',index===qIndex);row.setAttribute('aria-current',String(index===qIndex));});}
function focusQuick(i){markQuick(i);const row=quickRows()[qIndex];row?.focus({preventScroll:true});if(row?.closest('.quick-scroll'))row.scrollIntoView({block:'nearest',behavior:'instant'});}
function quick(index=null){
  if(!$('quick-panel').hidden&&index===null){closeQuick();stage.focus({preventScroll:true});return;}
  closeMenus();playlist(false);window.LPlayerDialogs?.closeHelp?.();$('quick-panel').hidden=false;stage.classList.add('quick-open');$('quick-toggle').classList.add('active');$('quick-toggle').setAttribute('aria-expanded','true');$('speed-button').setAttribute('aria-expanded','true');focusQuick(index===null?qIndex:index);hideLater();
}
function settings(tab='general'){closeMenus();closeQuick();playlist(false);window.LPlayerDialogs.closeHelp();window.LPlayerDialogs.openSettings(tab);hideLater();}
function help(){closeMenus();if(helpOpen())window.LPlayerDialogs.closeHelp();else window.LPlayerDialogs.openHelp();stage.focus({preventScroll:true});hideLater();}
async function fullscreen(){closeMenus();try{if(document.fullscreenElement)await document.exitFullscreen();else await app.requestFullscreen();}catch{toast('预览容器未允许全屏，可在独立浏览器窗口体验。');}}
function adjustQuick(n,action=false){
  const row=quickRows()[qIndex], name=row?.dataset.qrow;
  if(!row||row.getAttribute('aria-disabled')==='true')return;
  if(name==='speed')action?speed(1):shiftSpeed(n);
  else if(name==='volume')action?mute():volume(s.volume+n*5);
  else if(name==='zoom')zoom(action?100:s.zoom+n*25);
  else if(name==='subtitles')subtitles(!s.subtitles);
  else if(name==='delay'){if(action)s.delay=0;delay(action?0:n*.1);}
  else if(name==='track'){if(!items[s.current]?.local){s.track=s.track==='zh'?'en':'zh';s.subtitles=true;apply();}}
  else if(name==='hand')setPreference('hand',s.hand==='left'?'right':'left');
  else if(name==='private')setPreference('private',!s.private);
  else if(action&&name==='open')openFiles();
  else if(action&&name==='playlist')playlist(true);
  else if(action&&name==='shortcuts')settings('shortcuts');
  else if(action&&name==='settings')settings();
}
hydrate();document.querySelectorAll('input[type=range]').forEach(fill);
for(const id of ['play','center-play'])$(id).onclick=play;
for(const id of ['open-file','empty-open','add-files','quick-open'])$(id).onclick=openFiles;
$('file-input').onchange=e=>{ingest(e.target.files);e.target.value='';};
$('load-demo').onclick=$('app-demo').onclick=()=>{load(0,false);playlist(false);};$('empty-menu').onclick=closeMedia;
$('playlist-toggle').onclick=()=>playlist();$('quick-toggle').onclick=()=>quick();$('quick-close').onclick=closeQuick;
$('fullscreen').onclick=fullscreen;$('mute').onclick=mute;$('rewind').onclick=()=>seek(-5);$('forward').onclick=()=>seek(5);$('previous').onclick=()=>stepVideo(-1);$('next').onclick=()=>stepVideo(1);
$('speed-button').onclick=$('speed-control-menu').onclick=()=>quick(0);
$('quick-menu').onclick=()=>quick();$('fullscreen-menu').onclick=fullscreen;$('captions-button').onclick=()=>subtitles(!s.subtitles);
$('more-button').onclick=()=>showMenu($('more-menu'),$('more-button'));$('app-menu-button').onclick=()=>showMenu($('app-menu'),$('app-menu-button'));$('file-info-button').onclick=()=>{if(s.loaded)showMenu($('file-info'),$('file-info-button'));};
$('tracks-menu').onclick=()=>showMenu($('captions-menu'),$('more-button'));
$('settings-menu').onclick=$('app-settings').onclick=$('quick-settings').onclick=()=>settings();$('quick-shortcuts').onclick=()=>settings('shortcuts');
$('help-button').onclick=$('shortcut-menu').onclick=$('app-help').onclick=help;
$('private-menu').onclick=()=>{setPreference('private',!s.private);closeMenus();toast(s.private?'无痕标识已开启 · HTML 不保存观看记录':'无痕标识已关闭');};
$('captions-menu').onclick=e=>{const b=e.target.closest('[data-subtitle]');if(!b)return;s.subtitles=b.dataset.subtitle!=='off';if(s.subtitles)s.track=b.dataset.subtitle;apply();save();closeMenus();};
$('volume').oninput=e=>volume(+e.target.value,false);$('quick-volume').oninput=e=>volume(+e.target.value,false);$('quick-speed').onchange=e=>speed(+e.target.value);$('quick-zoom').oninput=e=>zoom(+e.target.value);$('quick-subtitles').onchange=e=>subtitles(e.target.checked);$('quick-track').onchange=e=>{s.track=e.target.value;s.subtitles=true;apply();};
$('quick-hand').onchange=e=>setPreference('hand',e.target.value);$('quick-private').onchange=e=>setPreference('private',e.target.checked);$('quick-list').onclick=()=>playlist(true);
$('delay-minus').onclick=()=>delay(-.1);$('delay-plus').onclick=()=>delay(.1);$('reset-zoom').onclick=()=>zoom(100);
for(const type of ['pointerdown','focusin'])$('quick-panel').addEventListener(type,event=>{const row=event.target.closest('[data-qrow]');if(row)markQuick(quickRows().indexOf(row));});
$('quick-panel').addEventListener('click',event=>{const row=event.target.closest('[data-qrow]');if(row?.classList.contains('quick-row')&&!event.target.closest('button,input,select,.stepper,.quick-slider')){event.preventDefault();focusQuick(quickRows().indexOf(row));adjustQuick(0,true);}});
$('seek').oninput=e=>{if(s.loaded){seekBefore=video.currentTime;video.currentTime=+e.target.value;updateTime();hideLater();}};
$('seek').onpointermove=e=>{if(!s.previews||!s.loaded)return;const r=e.currentTarget.getBoundingClientRect(),f=Math.max(0,Math.min(1,(e.clientX-r.left)/r.width));$('seek-preview').hidden=false;$('seek-preview').style.left=`${Math.max(80,Math.min(r.width-80,f*r.width))}px`;$('seek-preview-time').textContent=fmt(f*+$('seek').max);hideLater();};$('seek').onpointerleave=()=>$('seek-preview').hidden=true;
$('queue-list').onclick=e=>{const b=e.target.closest('[data-play]'),row=e.target.closest('[data-index]');if(b)activate(+b.dataset.play);else if(row)activate(+row.dataset.index);};$('play-selected').onclick=()=>activate();
function gallery(value){s.gallery=value;$('playlist').classList.toggle('gallery',value);$('compact-view').classList.toggle('selected',!value);$('gallery-view').classList.toggle('selected',value);$('compact-view').setAttribute('aria-pressed',String(!value));$('gallery-view').setAttribute('aria-pressed',String(value));syncFullscreenTransport();}
$('compact-view').onclick=()=>gallery(false);$('gallery-view').onclick=()=>gallery(true);
stage.onclick=e=>{if(e.target===stage||e.target===video||e.target===$('media-frame')){clearTimeout(stageClickTimer);stage.focus({preventScroll:true});closeMenus();if(e.detail<2)stageClickTimer=setTimeout(play,500);}};
stage.ondblclick=e=>{if(e.target===stage||e.target===video||e.target===$('media-frame')){e.preventDefault();clearTimeout(stageClickTimer);stage.focus({preventScroll:true});closeMenus();fullscreen();}};
app.onpointermove=hideLater;$('transport').onfocusin=hideLater;
document.addEventListener('pointerdown',e=>{if(menu&&!menu.contains(e.target)&&!anchor?.contains(e.target))closeMenus();});window.addEventListener('resize',()=>{closeMenus();syncFullscreenTransport();});
document.addEventListener('fullscreenchange',()=>{changeIcon($('fullscreen'),document.fullscreenElement?'arrows-in-simple':'arrows-out-simple');$('fullscreen').setAttribute('aria-label',document.fullscreenElement?'退出全屏':'进入全屏');syncFullscreenTransport();hideLater();});
video.addEventListener('loadedmetadata',()=>{const item=items[s.current];item.duration=video.duration;video.currentTime=Math.min(pendingStart,Math.max(0,video.duration-.2));video.playbackRate=s.speed;updateTime();if(item.local){$('info-details').textContent=`${video.videoWidth} × ${video.videoHeight} · ${fmt(video.duration)}`;}queue();if(video.dataset.playAfterLoad==='true')startPlayback();updatePlay();});
video.addEventListener('loadeddata',()=>{const item=items[s.current];if(item.local&&!item.thumbnail){try{const c=document.createElement('canvas');c.width=160;c.height=Math.max(1,Math.round(160*video.videoHeight/video.videoWidth));c.getContext('2d').drawImage(video,0,0,c.width,c.height);item.image=c.toDataURL('image/jpeg',.85);item.thumbnail=true;queue();}catch{}}});
video.addEventListener('timeupdate',updateTime);video.addEventListener('play',updatePlay);video.addEventListener('pause',updatePlay);video.addEventListener('ended',()=>{updatePlay();hud('播放结束');});video.addEventListener('error',()=>{toast('当前浏览器不支持此文件，请尝试 MP4、MOV 或 WebM。');hud('无法播放此文件');});
app.addEventListener('dragenter',e=>{if(e.dataTransfer?.types.includes('Files')){e.preventDefault();dragDepth++;$('drop-target').hidden=false;}});app.addEventListener('dragover',e=>{e.preventDefault();if(e.dataTransfer)e.dataTransfer.dropEffect='copy';});app.addEventListener('dragleave',e=>{e.preventDefault();if(--dragDepth<=0){dragDepth=0;$('drop-target').hidden=true;}});app.addEventListener('drop',e=>{e.preventDefault();dragDepth=0;$('drop-target').hidden=true;ingest(e.dataTransfer.files);});
document.addEventListener('keydown',e=>{
  if(window.LPlayerDialogs?.isOpen()||e.isComposing)return;
  const k=e.key.toLowerCase(), h=keysForHand(), navigation=!e.metaKey&&!e.ctrlKey&&!e.altKey;
  const consume=action=>{e.preventDefault();action?.();};
  // Esc always belongs to the topmost player surface, even after a form control.
  if(navigation&&k==='escape')return consume(()=>{if(menu)closeMenus(true);else if(!$('quick-panel').hidden)closeQuick();else if(helpOpen())window.LPlayerDialogs.closeHelp();else if(s.playlist)playlist(false);else if(document.fullscreenElement)document.exitFullscreen();});
  if(e.metaKey&&!e.ctrlKey&&!e.altKey&&!e.shiftKey){
    const actions={o:openFiles,',':()=>settings(),l:()=>playlist(),'0':()=>zoom(100),'[':()=>stepVideo(-1),']':()=>stepVideo(1),'/':help,n:()=>setPreference('private',!s.private)};
    if(actions[k])return consume(()=>{if(!e.repeat)actions[k]();});
    return;
  }
  if(e.metaKey&&e.ctrlKey&&!e.altKey&&!e.shiftKey&&k==='f')return consume(()=>{if(!e.repeat)fullscreen();});
  if(!navigation)return;
  if(e.target.matches('textarea,[contenteditable=true],input:not([type=range]):not([type=checkbox]):not([type=file])'))return;
  if(menu){
    const buttons=menuButtons(menu),index=buttons.indexOf(document.activeElement);
    if(k==='arrowdown'||k==='arrowup')return consume(()=>buttons[(index+(k==='arrowdown'?1:-1)+buttons.length)%buttons.length]?.focus());
    if(k==='home'||k==='end')return consume(()=>buttons[k==='home'?0:buttons.length-1]?.focus());
    if(k===' '||k==='enter')return consume(()=>{if(!e.repeat&&index>=0)buttons[index].click();});
    return;
  }
  const plain=!e.shiftKey;
  if(plain&&k===h.panel)return consume(()=>{if(!e.repeat)quick();});
  if(plain&&(k===h.list||(s.hand==='right'&&k==='b')))return consume(()=>{if(!e.repeat)playlist();});
  if((plain&&(k===h.help||k==='/'))||(e.shiftKey&&k==='?'))return consume(()=>{if(!e.repeat)help();});
  if(!$('quick-panel').hidden){
    if([h.up,h.down,'arrowup','arrowdown'].includes(k))return consume(()=>focusQuick(qIndex+([h.down,'arrowdown'].includes(k)?1:-1)));
    if([h.back,h.forward,'arrowleft','arrowright'].includes(k))return consume(()=>adjustQuick([h.back,'arrowleft'].includes(k)?-1:1));
    if(k===' '||k==='enter')return consume(()=>{if(!e.repeat)adjustQuick(0,true);});
  } else if(s.playlist){
    if([h.up,h.down,'arrowup','arrowdown'].includes(k))return consume(()=>select(s.selected+([h.down,'arrowdown'].includes(k)?1:-1),true));
    if(k==='home'||k==='end')return consume(()=>select(k==='home'?0:items.length-1,true));
    if(k===' '||k==='enter')return consume(()=>{if(!e.repeat)activate();});
  }
  if([h.back,'arrowleft'].includes(k))return consume(()=>seek(e.shiftKey?-30:-5));
  if([h.forward,'arrowright'].includes(k))return consume(()=>seek(e.shiftKey?30:5));
  if(e.shiftKey&&[h.up,'arrowup'].includes(k))return consume(()=>volume(s.volume+5));
  if(e.shiftKey&&[h.down,'arrowdown'].includes(k))return consume(()=>volume(s.volume-5));
  if(k==='+'||(plain&&['=','-',h.zoomIn,h.zoomOut].includes(k)))return consume(()=>{zoom(s.zoom+(['-',h.zoomOut].includes(k)?-25:25));hud(s.zoom===100?'适应窗口':`缩放 ${s.zoom}%`);});
  if(!plain)return;
  if(k===' ')return consume(()=>{if(!e.repeat)play();});
  if(k===h.previous||k==='arrowup')return consume(()=>{if(!e.repeat)stepVideo(-1);});
  if(k===h.next||k==='arrowdown')return consume(()=>{if(!e.repeat)stepVideo(1);});
  if(k===h.slower)return consume(()=>shiftSpeed(-1));if(k===h.faster)return consume(()=>shiftSpeed(1));
  if(k===h.normal)return consume(()=>{if(!e.repeat)speed(1);});
  if(k===h.full)return consume(()=>{if(!e.repeat)fullscreen();});
  if(k===h.subtitle)return consume(()=>{if(!e.repeat)subtitles(!s.subtitles);});
  if(k==='0'||k===h.zoomFit)return consume(()=>{if(!e.repeat){zoom(100);hud('适应窗口');}});
  if(k===h.undo)return consume(()=>{if(e.repeat)return;if(seekBefore===null)return hud('还没有可撤销的跳转');const current=video.currentTime;video.currentTime=seekBefore;seekBefore=current;updateTime();hideLater();});
});
queue();apply();zoom(100);updatePlay();playlist(false);
const transportObserver=new ResizeObserver(syncTransportLayout);
transportObserver.observe($('transport'));syncTransportLayout();
})();
