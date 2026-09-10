const fs=require('fs'),path=require('path'),cp=require('child_process');
const root=path.resolve(__dirname,'..');
const [kind,sourceArg,destArg]=process.argv.slice(2);
if(!['platformer','shooter'].includes(kind)||!sourceArg||!destArg)throw Error('Usage: node tools/prepare_external_game.cjs platformer|shooter source empty-destination');
const source=path.resolve(sourceArg),dest=path.resolve(destArg);
if(dest===source||dest.startsWith(source+path.sep))throw Error('Destination must be outside source.');
if(fs.existsSync(dest)&&fs.readdirSync(dest).length)throw Error('Destination must be empty.');
const revision=cp.execFileSync('git',['-c','safe.directory='+source.replaceAll(String.fromCharCode(92),'/'),'-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).trim();
const expected={platformer:'8a776826a6c6af92ff9ad3a4cfd29f344a49a47d',shooter:'8415c266dd809b17da1cd9b829be89ad04083c4b'};
if(revision!==expected[kind])throw Error('Unreviewed upstream revision: '+revision);
const skip=new Set(['.git','.godot','.github','.artifacts','builds','media']);
fs.cpSync(source,dest,{recursive:true,filter:p=>!skip.has(path.basename(p))});
fs.mkdirSync(path.join(dest,'streamer_integration'),{recursive:true});
fs.cpSync(path.join(root,'addons/streamer_mode'),path.join(dest,'addons/streamer_mode'),{recursive:true});
fs.copyFileSync(path.join(root,'examples/external_games/check.gd'),path.join(dest,'streamer_integration/check.gd'));
fs.copyFileSync(path.join(root,'examples/external_games/streamer_integration.gd'),path.join(dest,'streamer_integration/host.gd'));
for(const name of ['quiet_orbit.wav','neon_run.wav'])fs.copyFileSync(path.join(root,'demo/assets/audio',name),path.join(dest,'streamer_integration',name));
let project=fs.readFileSync(path.join(dest,'project.godot'),'utf8');
project=project.replace('[autoload]','[autoload]\n\nStreamerIntegration="*res://streamer_integration/host.gd"');
project=project.replace(/^enabled=PackedStringArray\(.*\)$/m,'enabled=PackedStringArray()');
project=project.replace('run/disable_stderr=true','run/disable_stderr=false').replace('run/print_header=false','run/print_header=true');
if(!project.includes('[rendering]'))project+='\n[rendering]\n';
project=project.replace('[rendering]','[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"');
project=project.replace('"Forward Plus"','"GL Compatibility"');
fs.writeFileSync(path.join(dest,'project.godot'),project);
if(kind==='platformer'){
 fs.writeFileSync(path.join(dest,'default_bus_layout.tres'),'[gd_resource type="AudioBusLayout" format=3]\n\n[resource]\nbus/1/name = &"Music"\nbus/1/send = &"Master"\nbus/2/name = &"StreamOriginalMusic"\nbus/2/send = &"Music"\n');
 for(const level of [1,2,3]){
 const p=path.join(dest,'level_'+level+'.tscn');
 fs.writeFileSync(p,fs.readFileSync(p,'utf8').replace('[node name="Music" type="AudioStreamPlayer" parent="."]','[node name="Music" type="AudioStreamPlayer" parent="."]\nbus = &"StreamOriginalMusic"'));
 }
}else{
 const bus=path.join(dest,'resources/audio_bus/default_bus_layout.tres');
 fs.appendFileSync(bus,'\nbus/3/name = &"StreamOriginalMusic"\nbus/3/send = &"Music"\n');
 for(const scene of ['game','menu']){
 const p=path.join(dest,'scenes',scene,scene+'.tscn');
 fs.writeFileSync(p,fs.readFileSync(p,'utf8').replaceAll('bus = &"Music"','bus = &"StreamOriginalMusic"'));
 }
}
fs.writeFileSync(path.join(dest,'STREAMER-INTEGRATION.md'),'# Local integration test\n\nUpstream: '+({platformer:'https://github.com/brettchalupa/godot_2d_platformer',shooter:'https://github.com/juan-medina/godot-shootem-up'}[kind])+'\nRevision: '+revision+'\n\nF8 opens streamer settings. Enable mode, select Quiet Orbit, Neon Run or Silence, then Resume. F8 keeps the original game Escape controls intact. Original music routes through StreamOriginalMusic; replacement goes through Music so host volume remains effective. SFX routes are unchanged. Settings persist across scenes within this run, not across restarts.\n\nOriginal README/credits and licenses are preserved. These are local modified test copies, not our original games. Platformer is a third-party playable starter kit; shooter is an independent example game. No artificial private fields were added. Privacy and chat are unavailable in this audio-focused adapter.\n\nChanges: addon and host autoload added; music routes changed; Compatibility renderer selected; upstream editor-only plugins disabled in the test copy.\n');
fs.writeFileSync(path.join(dest,'integration-origin.json'),JSON.stringify({kind,revision,source,modified:true},null,2));
console.log('Prepared '+kind+': '+dest);
