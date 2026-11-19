extends Node
var muted := false
var cache := {}
var players := []
var index := 0
const DATA = {"key":[950,.048,.48],"bar":[1880,.055,.36],"paper":[380,.062,.25],"step":[1270,.042,.28],"spool":[620,.052,.18],"bell":[1830,.76,.07],"return":[195,.31,.65],"feed":[510,.17,.45],"bail":[770,.16,.38],"knob":[355,.095,.45],"punch":[1350,.067,.48],"reader":[680,.083,.55],"patch":[700,.11,.78],"rewind":[420,.23,.6],"spring":[250,.17,.30],"stop":[1080,.08,.45],"slide":[330,.15,.69],"space":[480,.085,.52],"tab":[870,.135,.43],"guide":[1440,.048,.25]}
func _ready():
	for i in 20:
		var p=AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
func play(kind:String,v:int=0):
	if muted:return
	var id=kind+str(v)
	if not cache.has(id):
		var d=DATA[kind]
		var hz:float=d[0]*(.91+v*.035)
		var dur:float=d[1]*(1+v*.022)
		var noise:float=d[2]
		var rate:=22050
		var bytes=PackedByteArray()
		bytes.resize(int(rate*dur)*2)
		var rng=RandomNumberGenerator.new()
		rng.seed=abs(id.hash())
		var prev:=0.0
		for i in bytes.size()/2:
			var t=float(i)/rate
			prev=lerpf(prev,rng.randf_range(-1,1),.65)
			var hit=sin(TAU*hz*t)+.43*sin(TAU*hz*2.61*t)
			var sample=(hit*(1-noise)*.46+prev*noise)*exp(-6*t/dur)*minf(1,t*1200)
			if kind in ["rewind","return","reader","feed"]:sample*=.35+.65*absf(sin(TAU*42*t))
			bytes.encode_s16(i*2,int(sample*21000))
		var wave=AudioStreamWAV.new()
		wave.format=AudioStreamWAV.FORMAT_16_BITS
		wave.mix_rate=rate
		wave.data=bytes
		cache[id]=wave
	var p=players[index%players.size()]
	index+=1
	p.stream=cache[id]
	p.volume_db=-8 if kind!="bell" else -4
	p.play()

func _exit_tree():
	for p in players:
		if is_instance_valid(p):
			p.stop()
			p.stream=null
	cache.clear()
