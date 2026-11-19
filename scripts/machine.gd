extends Node3D
const DESIGNS=["Atelier","Continental","Courier","Executive","Studio","Metropolitan","Traveller","Foundry"]
const GROUPS=["Housing","Keys","Spacebar","Typebars","Platen","Knobs","Return","Bail","Spools","Correction","Guides","Escapement","Bell","Stops","Punch","Lamp"]
const SHEET_W=5.25
const SHEET_H=3.20
var settings:Dictionary
var doc
var sound
var camera=Camera3D.new()
var assembly:Node3D
var carriage:Node3D
var sheet:MeshInstance3D
var page
var paper_vp=SubViewport.new()
var impression=Timer.new()
var light=DirectionalLight3D.new()
var bulb=OmniLight3D.new()
var desk:MeshInstance3D
var env=Environment.new()
var keys={}
var bars=[]
var spools=[]
var guides:Node3D
var stop_nodes=[]
var ratchet:Node3D
var roller:Node3D
var wheels=[]
var bail:Node3D
var handle:Node3D
var tape_head:Node3D
var strip_material:ShaderMaterial
var bell:Node3D
var punch_wheels=[]
var corrector:MeshInstance3D
var correct_reels=[]
var tape_window: String = ""
var reader_cursor := -1
var badge:Label3D
var yaw:=.15
var pitch:=.57
var zoom:=12.0
var workshop:=false
var lens:=false
var anims:Dictionary={}
var carriage_tween:Tween
var loading_paper:Tween
var serial:=0
var current_page_row:=0
var parts:Dictionary
var slots={}
var finish_cache={}
const FINISH_SHADER=preload("res://scripts/finish.gdshader")
const FINISH_MAP=preload("res://surfaces/workshop-finish.png")
const VENEER=preload("res://surfaces/veneer.png")
const STUDIO_HDR=preload("res://surfaces/studio_small_03.hdr")
var shader=preload("res://scripts/wood.gdshader")

func node(parent,p:=Vector3.ZERO) -> Node3D:
	var n=Node3D.new()
	parent.add_child(n)
	n.position=p
	return n

func model(group:String,parent,p:=Vector3.ZERO) -> Node3D:
	var path="res://models/%s/%s.glb"%[group,DESIGNS[int(parts.get(group,0))]]
	var inst=load(path).instantiate()
	for part in inst.find_children("*","MeshInstance3D",true,false):
		for i in part.mesh.get_surface_count():
			var source=part.mesh.surface_get_material(i)
			if source is StandardMaterial3D:
				part.set_surface_override_material(i,physical_finish(source))
	parent.add_child(inst)
	inst.position=p
	return inst

func physical_finish(source:StandardMaterial3D) -> Material:
	var key=source.get_instance_id()
	if finish_cache.has(key):return finish_cache[key]
	var label=source.resource_name.to_lower()
	var m=ShaderMaterial.new()
	m.shader=FINISH_SHADER
	m.set_shader_parameter("finish_map",FINISH_MAP)
	m.set_shader_parameter("tint",source.albedo_color)
	m.set_shader_parameter("metal",source.metallic)
	m.set_shader_parameter("rough",source.roughness)
	m.set_shader_parameter("micro_depth",.00022)
	if "enamel" in label:
		m.set_shader_parameter("metal",.14)
		m.set_shader_parameter("polish",.35)
		m.set_shader_parameter("rough",.29)
		m.set_shader_parameter("micro_depth",.00055)
	elif "nickel" in label or "brass" in label:
		m.set_shader_parameter("metal",.92)
		m.set_shader_parameter("brushed",.84)
	elif "insert" in label:
		m.set_shader_parameter("polish",.32)
	elif "rubber" in label or "ribbon" in label:
		m.set_shader_parameter("micro_depth",.001)
	finish_cache[key]=m
	return m

func mesh(parent,geo,p:Vector3,color:Color,metal:=0.0) -> MeshInstance3D:
	var n=MeshInstance3D.new()
	n.mesh=geo
	var mat=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.metallic=metal
	mat.roughness=.45
	n.material_override=mat
	parent.add_child(n)
	n.position=p
	return n

func box(parent,p:Vector3,size:Vector3,color:Color,metal:=0.0):
	var geo=BoxMesh.new()
	geo.size=size
	return mesh(parent,geo,p,color,metal)

func label3(parent,caption,p,pt,px,col):
	var l=Label3D.new()
	l.text=caption
	l.font=preload("res://fonts/DejaVuSerif.ttf")
	l.font_size=pt
	l.pixel_size=px
	l.outline_size=0
	l.shaded=true
	l.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.modulate=Color(col)
	l.double_sided=false
	parent.add_child(l)
	l.position=p
	return l

func setup(d,s,a):
	doc=d
	settings=s
	parts=settings.parts
	sound=a
	var world=WorldEnvironment.new()
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.tonemap_white=5.5
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("51473a")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("fff2dd")
	env.ambient_light_energy=.75
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	var sky=Sky.new()
	var panorama=PanoramaSkyMaterial.new()
	panorama.panorama=STUDIO_HDR
	sky.sky_material=panorama
	sky.radiance_size=Sky.RADIANCE_SIZE_256
	env.sky_rotation.y=.68
	env.ssao_enabled=true
	env.ssao_radius=.42
	env.ssao_intensity=2.15
	env.ssao_detail=1.25
	env.ssao_light_affect=.36
	env.sky=sky
	world.environment=env
	add_child(world)
	add_child(camera)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.near=.35
	camera.far=36
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	add_child(light)
	light.rotation_degrees=Vector3(-47,-53,0)
	light.light_angular_distance=1.1
	light.shadow_bias=.028
	light.shadow_normal_bias=.48
	light.shadow_enabled=true
	light.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance=34
	add_child(bulb)
	bulb.omni_range=14
	bulb.shadow_enabled=true
	bulb.light_size=.075
	bulb.shadow_bias=.025
	desk=box(self,Vector3(0,-.14,0),Vector3(130,.25,120),Color.WHITE)
	var mat=ShaderMaterial.new()
	mat.shader=shader
	mat.set_shader_parameter("veneer",VENEER)
	mat.set_shader_parameter("figure",preload("res://surfaces/walnut.jpg"))
	desk.material_override=mat
	paper_vp.size=Vector2i(1080,690)
	paper_vp.disable_3d=true
	paper_vp.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(paper_vp)
	impression.one_shot=true
	impression.wait_time=.035
	add_child(impression)
	impression.timeout.connect(repaint)
	page=preload("res://scripts/paper.gd").new()
	page.size=paper_vp.size
	page.doc=doc
	page.settings=settings
	page.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	paper_vp.add_child(page)
	rebuild()

func rebuild():
	if loading_paper:loading_paper.kill()
	for tw in anims.values():
		if tw:tw.kill()
	anims.clear()
	if carriage_tween:carriage_tween.kill()
	if assembly:
		remove_child(assembly)
		assembly.queue_free()
	assembly=node(self)
	keys.clear()
	bars.clear()
	spools.clear()
	stop_nodes.clear()
	wheels.clear()
	correct_reels.clear()
	punch_wheels.clear()
	slots.clear()
	model("Housing",assembly)
	badge=label3(assembly,"TypeTick",Vector3(-2.03,.74,2.207),48,.00335,"d6c19c")
	var key_legend="e6dbbb" if variant("Keys")%2==0 else "252b28"
	for r in 4:
		var row:String=["1234567890-=","QWERTYUIOP[]","ASDFGHJKL;'","ZXCVBNM,./"][r]
		var z=.02+r*.49
		for c in row.length():
			var p=Vector3((c-(row.length()-1)*.5)*.475,1.30-r*.092,z)
			var key=model("Keys",assembly,p)
			var linkage=box(key,Vector3(0,-.16,-.24),Vector3(.046,.080,.49),Color("444642"),.79)
			linkage.rotation.x=-.17
			var cap=label3(key,row[c],Vector3(0,.149,0),34,.0053,key_legend)
			cap.rotation.x=-PI/2
			keys[row[c]]=key
	for spec in [["Tab",-3.03,.51,"⇥"],["Backspace",3.12,.02,"⌫"],["Enter",2.97,1.0,"↵"],["Shift",-2.93,1.49,"⇧"]]:
		var k=model("Keys",assembly,Vector3(spec[1],1.30-(float(spec[2])+.25)*.178,spec[2]))
		var cap=label3(k,spec[3],Vector3(0,.15,0),32,.0045,key_legend)
		cap.rotation.x=-PI/2
		keys[spec[0]]=k
	keys[" "]=model("Spacebar",assembly,Vector3(0,.9,1.94))
	var steel=Color("b7b5a2")
	for sg in [-1,1]:
		spools.append(model("Spools",assembly,Vector3(sg*1.95,1.32,-.87)))
		var ribbon=box(assembly,Vector3(sg*.99,1.51,-1.13),Vector3(1.98,.088,.015),Color("342c35"))
		ribbon.rotation.y=sg*.14
		var cr=model("Correction",assembly,Vector3(sg*.79,1.27,-.80))
		cr.scale=Vector3(.48,.75,.48)
		correct_reels.append(cr)
		var white_band=box(assembly,Vector3(sg*.475,1.43,-.99),Vector3(.81,.050,.013),Color("ddcfab"))
		white_band.rotation.y=-sg*.34
	var legends="1234567890-=QWERTYUIOP[]ASDFGHJKL;'ZXCVBNM,./"
	for i in legends.length():
		var a=lerpf(-1.23,1.23,float(i)/(legends.length()-1))
		var pivot=node(assembly,Vector3(sin(a)*.35,1.10,-1.27+cos(a)*.35))
		pivot.rotation.y=a
		var bar=model("Typebars",pivot)
		bar.scale.z=1.29
		bar.rotation.x=2.82
		var face=label3(bar,legends[i],Vector3(0,.106,-.79),26,.0013,"39352c")
		face.rotation.x=-PI/2
		bars.append(bar)
	guides=model("Guides",assembly,Vector3(0,1.70,-1.15))
	corrector=box(guides,Vector3(0,.11,.025),Vector3(.40,.095,.013),Color("e6e1d3"))
	corrector.visible=false
	carriage=node(assembly,Vector3(0,1.75,-1.48))
	box(carriage,Vector3(0,-.18,0),Vector3(6.52,.13,.29),steel,.8)
	roller=model("Platen",carriage)
	for sg in [-1,1]:
		wheels.append(model("Knobs",carriage,Vector3(sg*3.20,0,0)))
	handle=model("Return",carriage,Vector3(-2.93,.03,.05))
	bail=model("Bail",carriage,Vector3(0,-.15,0))
	var quad=QuadMesh.new()
	quad.size=Vector2(SHEET_W,SHEET_H)
	quad.subdivide_width=32
	quad.subdivide_depth=20
	sheet=MeshInstance3D.new()
	sheet.mesh=quad
	carriage.add_child(sheet)
	sheet.position=Vector3(0,1.56,.07)
	sheet.rotation.x=-.145
	var pm=ShaderMaterial.new()
	pm.shader=preload("res://scripts/stock.gdshader")
	pm.set_shader_parameter("impressions",paper_vp.get_texture())
	pm.set_shader_parameter("fibres",FINISH_MAP)
	sheet.material_override=pm
	# A metal scale and sliding stops share the carriage's paper coordinates.
	box(carriage,Vector3(0,.10,.285),Vector3(5.65,.13,.045),Color("373e38"),.38)
	for i in 76:
		var x=col_x(i)
		box(carriage,Vector3(x,.115,.312),Vector3(.009,.062 if i%5==0 else .026,.005),Color("d8c9a7"))
	for column in range(10,71,10):
		label3(carriage,str(column),Vector3(col_x(column),.081,.315),24,.0018,"d1c7af")
	for i in 2:stop_nodes.append(model("Stops",carriage))
	bell=model("Bell",assembly,Vector3(2.67,1.38,-.90))
	ratchet=model("Escapement",assembly,Vector3(3.44,1.02,-.43))
	box(assembly,Vector3(0,1.54,-1.52),Vector3(6.22,.11,.13),steel,.85)
	var deck=model("Punch",assembly,Vector3(3.89,.82,.14))
	for sg in [-1,1]:
		var gear=model("Escapement",deck,Vector3(.48,.20,sg*.47))
		gear.rotation.z=PI/2
		gear.scale=Vector3(.72,.72,.72)
		punch_wheels.append(gear)
	var strip=PlaneMesh.new()
	strip.size=Vector2(.57,1.40)
	strip.subdivide_depth=56
	var tape=MeshInstance3D.new()
	tape.mesh=strip
	tape.extra_cull_margin=.45
	deck.add_child(tape)
	strip_material=ShaderMaterial.new()
	strip_material.shader=preload("res://scripts/perforated_tape.gdshader")
	strip_material.set_shader_parameter("fibres",FINISH_MAP)
	tape.material_override=strip_material
	tape_head=box(deck,Vector3(0,.48,-.11),Vector3(.57,.06,.10),Color("8d8170"),.72)
	var lamp=model("Lamp",assembly,Vector3(-4.65,0,-.30))
	lamp.scale=Vector3.ONE*1.24
	lamp.rotation.y=.23
	bulb.global_position=lamp.to_global(Vector3(.36,1.56+.08*variant("Lamp"),.31))
	update_materials()
	refresh(false)
	update_camera()

func col_x(col:int) -> float:return ((26+14.0*col)/1080.0-.5)*SHEET_W

func repaint():
	page.queue_redraw()
	paper_vp.render_target_update_mode=SubViewport.UPDATE_ONCE
	
func refresh(motion:=true,at_impact:=false):
	if at_impact:
		if impression.is_stopped():impression.start()
	else:repaint()
	if not carriage:return
	var p:Vector2i=doc.points[doc.caret]
	var goal=-col_x(p.x)
	if carriage_tween:carriage_tween.kill()
	if motion:
		carriage_tween=create_tween()
		if at_impact:carriage_tween.tween_interval(.035)
		carriage_tween.tween_property(carriage,"position:x",goal,.105 if p.y==current_page_row else .23).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:carriage.position.x=goal
	current_page_row=p.y
	for i in 2:
		stop_nodes[i].position=Vector3(col_x(doc.left if i==0 else doc.right),.17,.32)
	var source:String=doc.tape if reader_cursor<0 else tape_window
	var tail:int=source.length() if reader_cursor<0 else reader_cursor
	var codes=PackedInt32Array()
	for i in 8:
		var pos=tail-8+i
		codes.append(source.unicode_at(pos)&255 if pos>=0 and pos<source.length() else 0)
	strip_material.set_shader_parameter("codes",codes)

func update_materials():
	var woods={"Walnut":["36251d","6f5039"],"Oak":["92724f","b69a72"],"Ebony":["222425","423d38"],"Ash":["aca695","d1c9b4"]}
	var colors=woods.get(settings.desk,woods.Walnut)
	desk.material_override.set_shader_parameter("dark",Color(colors[0]))
	desk.material_override.set_shader_parameter("pale",Color(colors[1]))
	var night=settings.light=="Night"
	env.ambient_light_energy=.065 if night else .18
	env.sky.sky_material.energy_multiplier=.065 if night else .23
	env.background_energy_multiplier=.42 if night else .80
	light.light_energy=.22 if night else 1.46
	light.light_color=Color("c2d1e5") if night else Color("fff3e1")
	bulb.light_color=Color(settings.lamp_color)
	bulb.light_energy=11.0 if night else 1.7
	sheet.material_override.set_shader_parameter("finish_roughness",.30 if settings.surface=="Gloss" else .83)
	sheet.material_override.set_shader_parameter("crumple",1.0 if settings.surface=="Crumpled" else 0.0)
	page.queue_redraw()
	paper_vp.render_target_update_mode=SubViewport.UPDATE_ONCE

func update_camera():
	if lens:
		var target=Vector3(carriage.position.x,2.95,-1.36)
		camera.position=target+Vector3(0,1.8,14)
		camera.look_at(target)
		camera.size=3.6
		return
	var center=Vector3(.36,2.00,-.15)
	camera.position=center+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*16
	camera.look_at(center,Vector3.UP)
	camera.size=zoom*.69

func pulse(target:Node3D,property:String,base:float,peak:float,duration:float):
	var id=str(target.get_instance_id())+property
	if anims.has(id):anims[id].kill()
	target.set_indexed(NodePath(property),base)
	var t=create_tween()
	anims[id]=t
	t.tween_property(target,property,peak,duration*.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(target,property,base,duration*.66).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func key_dip(name_:String):
	if not keys.has(name_):return
	var k=keys[name_]
	if not k.has_meta("rest"):k.set_meta("rest",k.position.y)
	pulse(k,"position:y",k.get_meta("rest"),float(k.get_meta("rest"))-.085,.115)

func strike(ch:String,correction:=false):
	finish_loading()
	serial+=1
	if ch.length()==1 and ch!=ch.to_lower():key_dip("Shift")
	var name_=ch.to_upper()
	var shifted="!@#$%^&*()_+{}:\"<>?"
	var base="1234567890-=[];',./"
	if shifted.contains(ch) and ch.length()==1:name_=base[shifted.find(ch)]
	if ch=="\n":name_="Enter"
	if ch=="\t":name_="Tab"
	key_dip(name_)
	if correction:key_dip("Backspace")
	if ch=="\n":
		line_feed()
	elif ch=="\t":sound.play("tab",variant("Stops"))
	else:
		sound.play("space" if ch==" " else "key",variant("Keys"))
		if ch!=" ":
			var index="1234567890-=QWERTYUIOP[]ASDFGHJKL;'ZXCVBNM,./".find(name_)
			var bar=bars[(index if index>=0 else absi(ch.hash()))%bars.size()]
			var t=.115+variant("Typebars")*.006
			pulse(bar,"rotation:x",2.82,1.19,t)
			pulse(guides,"position:y",1.70,1.91,t)
			pulse(sheet,"rotation:x",-.145,-.145-(.013 if settings.hardness=="Firm" else .034),t)
			sound.play("bar",variant("Typebars"))
			sound.play("paper",2 if settings.hardness=="Firm" else 6)
			sound.play("guide",variant("Guides"))
		for i in 2:spools[i].rotate_y((1 if i==0 else -1)*.045)
		sound.play("spool",variant("Spools"))
	corrector.visible=correction
	if correction:
		for r in correct_reels:r.rotate_y(.12)
		sound.play("patch",variant("Correction"))
		var token=serial
		get_tree().create_timer(.19).timeout.connect(func():
			if serial==token and is_instance_valid(corrector):corrector.hide())
	ratchet.rotate_y(.27)
	for gear in punch_wheels:gear.rotate_object_local(Vector3.UP,.24)
	sound.play("step",variant("Escapement"))
	pulse(tape_head,"position:y",.48,.399,.12)
	sound.play("punch",variant("Punch"))

func variant(k:String)->int:return int(parts.get(k,0))
func line_feed():
	pulse(handle,"rotation:y",0,-.37,.31)
	pulse(sheet,"position:y",1.56,1.56+(.11+variant("Platen")*.002),.23)
	for wheel in wheels:wheel.rotate_x(.33)
	roller.rotate_x(.33)
	sound.play("return",variant("Return"))
	sound.play("feed",variant("Platen"))
	sound.play("knob",variant("Knobs"))
func insert_sheet():
	if loading_paper:loading_paper.kill()
	var target=-col_x(doc.points[doc.caret].x)
	carriage.position.x=target-.38
	sheet.position.y=2.27
	sheet.visible=false
	loading_paper=create_tween()
	sound.play("bail",variant("Bail"))
	loading_paper.tween_property(bail,"rotation:x",-1.03,.16)
	loading_paper.tween_callback(sheet.show)
	loading_paper.tween_callback(func():sound.play("knob",variant("Knobs"));sound.play("feed",variant("Platen")))
	loading_paper.tween_property(sheet,"position:y",1.56,.41).set_trans(Tween.TRANS_SINE)
	for wheel in wheels:loading_paper.parallel().tween_property(wheel,"rotation:x",wheel.rotation.x+1.58,.41)
	loading_paper.parallel().tween_property(roller,"rotation:x",roller.rotation.x+1.58,.41)
	loading_paper.tween_property(bail,"rotation:x",0,.14)
	loading_paper.tween_callback(func():sound.play("slide",variant("Housing")))
	loading_paper.tween_property(carriage,"position:x",target,.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func finish_loading():
	if loading_paper and loading_paper.is_running():
		loading_paper.kill()
		sheet.show()
		sheet.position.y=1.56
		bail.rotation.x=0
		refresh(false)

func ring_bell():
	pulse(bell,"rotation:z",0,.10,.21)
	sound.play("bell",variant("Bell"))

func hit_sheet(at:Vector2):
	var origin=sheet.to_local(camera.project_ray_origin(at))
	var dir=sheet.global_transform.basis.inverse()*camera.project_ray_normal(at)
	if absf(dir.z)<.0001:return -1
	var t=-origin.z/dir.z
	var p=origin+t*dir
	if t<0 or absf(p.x)>SHEET_W/2 or absf(p.y)>SHEET_H/2:return -1
	var x=(p.x/SHEET_W+.5)*1080
	var y=(.5-p.y/SHEET_H)*690
	return doc.nearest(roundi((x-26)/14),page.start_row+roundi((y-608)/34))

func _process(_delta):
	if lens and carriage:
		camera.position.x=carriage.position.x
