extends Node
const Document=preload("res://scripts/document.gd")
const Machine=preload("res://scripts/machine.gd")
const Sound=preload("res://scripts/sound.gd")
const SANS=preload("res://fonts/DejaVuSans.ttf")
const SERIF=preload("res://fonts/DejaVuSerif.ttf")
const MONO=preload("res://fonts/DejaVuSansMono.ttf")
const CREAM=Color("#f2ecdf")
const MUTED=Color("#bdb7a8")
const BRASS=Color("#d9b482")
const DARK=Color("#242924")
const CONFIG="user://studio.json"
var doc=Document.new()
var machine=Machine.new()
var sfx=Sound.new()
var prefs={"parts":{},"paper":"eee4cb","surface":"Matte","hardness":"Soft","ink":"282722","finish":"Plain","bleed":0.08,"font":"Typewriter","desk":"Walnut","light":"Day","lamp_color":"ffe0a2","mute":false}
var notes={}
var active_id=""
var title=""
var root=Control.new()
var header:PanelContainer
var footer:PanelContainer
var sidebar:PanelContainer
var title_label:Label
var status:Label
var stats:Label
var lens_button:Button
var mute_button:Button
var nav={}
var mode="Write"
var panel_kind="Parts"
var scroll_body:VBoxContainer
var selection_drag:=false
var orbit_drag:=false
var dragging_stop := -1
var stop_mouse_x := 0.0
var stop_initial := 0
var clip=""
var busy:=false
var pending_save:=false
var timer=Timer.new()
var dialog:Window
var native_menus:Array[RID]=[]
var seq_token:=0
var msg_clock:=0
var disk_error:=false
var load_error:=false
var io_dialog:FileDialog

func _ready():
	get_window().min_size=Vector2i(980,680)
	get_window().title="TypeTick — Mechanical Writing Studio"
	load_state()
	add_child(sfx)
	sfx.muted=prefs.mute
	add_child(machine)
	machine.setup(doc,prefs,sfx)
	add_child(timer)
	timer.one_shot=true
	timer.wait_time=.45
	timer.timeout.connect(save_state)
	var layer=CanvasLayer.new()
	add_child(layer)
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.theme=make_theme()
	build_chrome()
	build_native_menu()
	set_mode("Write")
	machine.insert_sheet()
	if load_error:message("Recovery copy opened · original file preserved")
	get_tree().auto_accept_quit=false
	get_viewport().size_changed.connect(frame_camera)

func make_theme():
	var th=Theme.new()
	th.default_font=SANS
	th.default_font_size=15
	for typ in ["Label","Button","OptionButton","CheckButton","LineEdit","TextEdit","PopupMenu"]:
		th.set_color("font_color",typ,CREAM)
	for typ in ["Button","OptionButton","CheckButton"]:
		for state in ["normal","hover","pressed","focus"]:
			var bg=Color("#343b34") if state=="normal" else Color("#475247")
			var st=style(bg if state!="focus" else Color.TRANSPARENT,5,9,6)
			if state=="focus":st.set_border_width_all(1);st.border_color=BRASS
			th.set_stylebox(state,typ,st)
	th.set_stylebox("panel","PanelContainer",style(DARK,0,0,0))
	return th

func style(bg:Color,r:int,h:int,v:int):
	var st=StyleBoxFlat.new()
	st.bg_color=bg
	st.set_corner_radius_all(r)
	st.content_margin_left=h
	st.content_margin_right=h
	st.content_margin_top=v
	st.content_margin_bottom=v
	return st

func lab(parent,caption:String,font:Font=SANS,sz:int=16,col:Color=CREAM):
	var l=Label.new()
	parent.add_child(l)
	l.text=caption
	l.add_theme_font_override("font",font)
	l.add_theme_font_size_override("font_size",sz)
	l.modulate=col
	return l

func button(parent,caption:String,fn:Callable,tip:String=""):
	var b=Button.new()
	parent.add_child(b)
	b.text=caption
	b.tooltip_text=tip
	b.focus_mode=Control.FOCUS_NONE
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	b.pressed.connect(fn)
	return b

func stretch(parent):
	var c=Control.new()
	c.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	c.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)

func row(parent,gap:=10):
	var r=HBoxContainer.new()
	r.add_theme_constant_override("separation",gap)
	parent.add_child(r)
	return r

func build_chrome():
	header=PanelContainer.new()
	root.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom=71
	header.add_theme_stylebox_override("panel",style(DARK,0,24,12))
	var bar=row(header,14)
	var icon=TextureRect.new()
	icon.texture=preload("res://icon.svg")
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size=Vector2(44,41)
	bar.add_child(icon)
	lab(bar,"TypeTick",SERIF,28)
	bar.add_child(VSeparator.new())
	for tab in ["Write","Workshop","Folio"]:
		var b=button(bar,tab,func():set_mode(tab))
		b.custom_minimum_size.x=85
		nav[tab]=b
	stretch(bar)
	lens_button=button(bar,"Reading lens",toggle_lens,"Enlarge the printed sheet")
	mute_button=button(bar,"",toggle_sound)
	button(bar,"?",show_help,"Keyboard guide")
	var note_card=PanelContainer.new()
	root.add_child(note_card)
	note_card.position=Vector2(24,94)
	note_card.add_theme_stylebox_override("panel",style(Color("#262923ed"),6,16,10))
	var line=row(note_card,10)
	title_label=lab(line,title,SERIF,20)
	title_label.clip_text=false
	button(line,"···",rename_note,"Rename sheet")
	footer=PanelContainer.new()
	root.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top=-48
	footer.add_theme_stylebox_override("panel",style(DARK,0,22,7))
	var foot=row(footer,12)
	lab(foot,"●",SANS,14,Color("afbe91"))
	status=lab(foot,"",SANS,14)
	stretch(foot)
	stats=lab(foot,"",MONO,13,MUTED)
	sidebar=PanelContainer.new()
	root.add_child(sidebar)
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	sidebar.offset_left=-335
	sidebar.offset_top=71
	sidebar.offset_bottom=-48
	sidebar.add_theme_stylebox_override("panel",style(Color("#282d27"),0,17,18))
	update_status()

func update_status():
	if not status:return
	title_label.text=title.left(32)+("…" if title.length()>32 else "")
	var words=doc.text.replace("\n"," ").replace("\t"," ").split(" ",false).size()
	var p:Vector2i=doc.points[doc.caret]
	stats.text="%d words   ·   Line %d   Col %d"%[words,p.y+1,p.x-doc.left+1]
	mute_button.text="Sound off" if sfx.muted else "Sound on"
	if msg_clock==0:
		status.text="Save failed" if disk_error else ("Saving…" if pending_save else "Saved locally")

func message(s:String):
	status.text=s
	msg_clock+=1
	var ticket=msg_clock
	get_tree().create_timer(2.2).timeout.connect(func():
		if msg_clock==ticket:
			msg_clock=0
			update_status())

func toggle_lens():
	machine.lens=not machine.lens
	lens_button.text="Desk view" if machine.lens else "Reading lens"
	frame_camera()

func toggle_sound():
	prefs.mute=not prefs.mute
	sfx.muted=prefs.mute
	sfx.play("stop")
	changed()

func load_state():
	var data={}
	for path in [CONFIG,CONFIG+".bak"]:
		if not FileAccess.file_exists(path):continue
		var file=FileAccess.open(path,FileAccess.READ)
		if file:
			var parsed=JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and parsed.get("notes") is Dictionary and not parsed.notes.is_empty():
				data=parsed
				break
		load_error=true
	if load_error and FileAccess.file_exists(CONFIG):
		DirAccess.copy_absolute(CONFIG,CONFIG+".damaged-"+str(Time.get_unix_time_from_system()))
	prefs.merge(data.get("prefs",{}),true)
	notes=data.get("notes",{})
	clip=str(data.get("clip",""))
	active_id=str(data.get("active",""))
	if notes.is_empty():
		active_id="first"
		notes[active_id]={"title":"Untitled sheet"}
	if not notes.has(active_id):active_id=notes.keys()[0]
	open_data()

func open_data():
	var data=notes[active_id]
	title=data.get("title","Untitled sheet")
	doc.left=clampi(int(data.get("left",4)),0,48)
	doc.right=clampi(int(data.get("right",68)),doc.left+8,74)
	doc.tab_width=clampi(int(data.get("tab",4)),2,12)
	doc.restore(data)
	doc.tape=str(data.get("tape",doc.text))
	doc.undo_stack.clear()
	doc.redo_stack.clear()

func cache_note():
	var data=doc.snapshot()
	data.merge({"title":title,"left":doc.left,"right":doc.right,"tab":doc.tab_width,"tape":doc.tape})
	notes[active_id]=data

func save_state():
	cache_note()
	var f=FileAccess.open(CONFIG+".tmp",FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version":1,"notes":notes,"active":active_id,"prefs":prefs,"clip":clip}))
		f.flush()
		var ok=f.get_error()==OK
		f.close()
		if ok:
			if FileAccess.file_exists(CONFIG):DirAccess.copy_absolute(CONFIG,CONFIG+".bak")
			disk_error=DirAccess.rename_absolute(CONFIG+".tmp",CONFIG)!=OK
		else:disk_error=true
	else:disk_error=true
	pending_save=disk_error
	update_status()

func changed():
	pending_save=true
	timer.start()
	update_status()

func _notification(what):
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		save_state()
		if not disk_error:get_tree().quit()
		else:message("Could not save · export your sheet from Folio")

func frame_camera():
	if not machine.camera.is_inside_tree():return
	var sz=get_viewport().get_visible_rect().size
	var inset=335.0 if mode!="Write" else 0.0
	machine.update_camera()
	machine.camera.size=maxf(machine.camera.size,(5.6 if machine.lens and mode=="Write" else 10.6)*sz.y/maxf(1,sz.x-inset))
	machine.camera.h_offset=machine.camera.size*inset/sz.y*.5
	# Shift the machine to the unobstructed side of the viewport.
	machine.camera.v_offset=.14
	var distance=Vector3(0,1.8,14).length() if machine.lens else 16.0
	machine.camera.fov=rad_to_deg(2*atan(machine.camera.size/(2*distance)))

func set_mode(tab:String):
	mode=tab
	for k in nav:
		nav[k].add_theme_stylebox_override("normal",style(Color("#516151") if k==tab else DARK,5,12,7))
		nav[k].modulate=Color.WHITE if k==tab else MUTED
	sidebar.visible=tab!="Write"
	lens_button.visible=tab=="Write"
	if tab!="Write":machine.lens=false; lens_button.text="Reading lens"
	machine.workshop=tab=="Workshop"
	if tab=="Write":
		machine.yaw=.15
		machine.pitch=.57
		machine.zoom=12
	else:build_panel()
	frame_camera()

func build_panel():
	for child in sidebar.get_children():
		sidebar.remove_child(child)
		child.queue_free()
	var v=VBoxContainer.new()
	v.add_theme_constant_override("separation",13)
	sidebar.add_child(v)
	var heading=row(v)
	lab(heading,mode,SERIF,26)
	stretch(heading)
	button(heading,"×",func():set_mode("Write"),"Return to writing")
	if mode=="Workshop":
		var segments=row(v,4)
		for k in ["Parts","Materials","Desk"]:
			var b=button(segments,k,func():panel_kind=k;build_panel())
			b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			if k==panel_kind:b.modulate=BRASS
	var scroll=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	scroll_body=VBoxContainer.new()
	scroll_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll_body.add_theme_constant_override("separation",10)
	scroll.add_child(scroll_body)
	if mode=="Workshop":
		match panel_kind:
			"Parts":
				lab(scroll_body,"Drag to orbit  ·  Scroll to zoom",SANS,13,MUTED)
				for k in Machine.GROUPS:
					option(k,Machine.DESIGNS,Machine.DESIGNS[machine.variant(k)],func(val):
						prefs.parts[k]=Machine.DESIGNS.find(val)
						machine.rebuild()
						frame_camera()
						sfx.play("stop",machine.variant(k))
						changed())
			"Materials":
				lab(scroll_body,"Paper stock",SERIF,20,BRASS)
				palette("Paper shade","paper",["fffdf4","f5f1e6","e9e7e2","f6ebc9","eee4cb","d6c08c","bd9d64","43403e","2d3033","191b1d"])
				setting_option("Surface","surface",["Matte","Linen","Gloss","Rough","Crumpled"])
				setting_option("Hardness","hardness",["Soft","Firm"])
				scroll_body.add_child(HSeparator.new())
				lab(scroll_body,"Ink ribbon",SERIF,20,BRASS)
				palette("Ink shade","ink",["171818","282722","574638","37445c","7b303e","685773","a88641","d1c9bb","f5efdf","ffffff"])
				setting_option("Finish","finish",["Plain","Pearlescent","Flaked"])
				slider("Ink bleed",0,1,.05,float(prefs.bleed),func(val):prefs.bleed=val;materials_changed())
				setting_option("Typeface","font",["Typewriter","Book serif","Grotesque"])
			"Desk":
				setting_option("Desk surface","desk",["Walnut","Oak","Ebony","Ash"])
				setting_option("Time of day","light",["Day","Night"])
				option("Desk lamp",Machine.DESIGNS,Machine.DESIGNS[machine.variant("Lamp")],func(val):
					prefs.parts.Lamp=Machine.DESIGNS.find(val)
					machine.rebuild()
					frame_camera()
					changed())
				palette("Lamp temperature","lamp_color",["ffbe77","ffe0a2","fff1d6","e4ecff","aabafb","d6b4cf"])
				button(scroll_body,"Reset view",func():machine.yaw=.15;machine.pitch=.57;machine.zoom=12;frame_camera())
	else:
		button(scroll_body,"+  New sheet",new_note)
		button(scroll_body,"Read & select text",read_sheet)
		button(scroll_body,"Export plain text…",export_sheet)
		lab(scroll_body,"Carriage settings",SERIF,20,BRASS)
		slider("Left stop",0,doc.right-8,1,doc.left,func(val):doc.left=int(val);margins_changed())
		slider("Right stop",doc.left+8,74,1,doc.right,func(val):doc.right=int(val);margins_changed())
		slider("Tab spacing",2,12,1,doc.tab_width,func(val):doc.tab_width=int(val);margins_changed())
		lab(scroll_body,"Local sheets",SERIF,20,BRASS)
		cache_note()
		for id in notes:
			var b=button(scroll_body,("●  " if id==active_id else "")+str(notes[id].title),func():switch_note(id))
			b.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS

func option(caption,opts,current,fn):
	lab(scroll_body,caption,SANS,14,MUTED)
	var pick=OptionButton.new()
	scroll_body.add_child(pick)
	for it in opts:pick.add_item(it)
	pick.select(maxi(0,opts.find(current)))
	pick.item_selected.connect(func(i):fn.call(opts[i]))
	return pick
func setting_option(caption,k,opts):
	option(caption,opts,prefs[k],func(val):prefs[k]=val;materials_changed())
func palette(caption,k,opts):
	lab(scroll_body,caption,SANS,14,MUTED)
	var flow=HFlowContainer.new()
	scroll_body.add_child(flow)
	for hex in opts:
		var b=button(flow,"",func():prefs[k]=hex;materials_changed();build_panel(),hex)
		b.custom_minimum_size=Vector2(24,24)
		var st=style(Color(hex),12,0,0)
		st.set_border_width_all(2 if prefs[k]==hex else 1)
		st.border_color=BRASS if prefs[k]==hex else Color("#716e61")
		b.add_theme_stylebox_override("normal",st)
		b.add_theme_stylebox_override("hover",st)
	var picker=ColorPickerButton.new()
	picker.color=Color(prefs[k])
	picker.edit_alpha=false
	picker.custom_minimum_size=Vector2(34,24)
	picker.tooltip_text="Mix a custom shade"
	flow.add_child(picker)
	picker.color_changed.connect(func(c):prefs[k]=c.to_html(false);materials_changed())
func slider(caption,minval,maxval,step,value,fn):
	var r=row(scroll_body)
	lab(r,caption,SANS,14,MUTED)
	stretch(r)
	var l=lab(r,str(value),MONO,13)
	var h=HSlider.new()
	scroll_body.add_child(h)
	h.min_value=minval;h.max_value=maxval;h.step=step;h.value=value
	h.value_changed.connect(func(val):l.text=str(snappedf(val,step));fn.call(val))
	if mode=="Folio":h.drag_ended.connect(func(_changed):build_panel.call_deferred())
func margins_changed():
	doc.left=mini(doc.left,doc.right-8)
	doc.right=maxi(doc.right,doc.left+8)
	doc.layout()
	machine.refresh()
	sfx.play("stop",machine.variant("Stops"))
	changed()
func materials_changed():
	machine.update_materials()
	changed()
func new_note():
	cache_note()
	active_id=str(Time.get_unix_time_from_system())+"-"+str(randi())
	notes[active_id]={"title":"Untitled sheet"}
	switch_note(active_id,false)
	rename_note()
func switch_note(id,keep:=true):
	cancel_replay()
	if keep:cache_note()
	active_id=id
	open_data()
	machine.refresh(false)
	machine.insert_sheet()
	changed()
	set_mode("Write")

func pop(title_:String,sz:Vector2i):
	if is_instance_valid(dialog):dialog.queue_free()
	dialog=Window.new()
	dialog.title=title_
	dialog.size=sz
	dialog.transient=true
	dialog.exclusive=true
	dialog.theme=root.theme
	root.add_child(dialog)
	dialog.close_requested.connect(close_pop)
	var bg=PanelContainer.new()
	dialog.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel",style(DARK,0,22,20))
	var body=VBoxContainer.new()
	body.add_theme_constant_override("separation",14)
	bg.add_child(body)
	dialog.popup_centered()
	return body
func close_pop():
	if is_instance_valid(dialog):dialog.hide();dialog.queue_free();dialog=null
func rename_note():
	var v=pop("Rename sheet",Vector2i(420,160))
	lab(v,"Sheet title",SERIF,21)
	var field=LineEdit.new()
	v.add_child(field)
	field.text=title
	field.max_length=96
	field.select_all()
	var done=func():
		title=field.text.strip_edges() if not field.text.strip_edges().is_empty() else "Untitled sheet"
		close_pop()
		changed()
		if mode=="Folio":build_panel()
	button(v,"Save title",done)
	field.text_submitted.connect(func(_s):done.call())
	field.grab_focus()
func show_help():
	var v=pop("Writing guide",Vector2i(580,460))
	lab(v,"At the typewriter",SERIF,30)
	for info in ["Type to strike a key. Return advances the platen.","Tab jumps to the next stop. Backspace lifts the correction ribbon.","Click the sheet to place the carriage. Drag or hold Shift with","the arrow keys to select a passage. ⌘A selects the whole sheet.","⌘/Ctrl C locks the selection on the punched tape.","⌘/Ctrl X overstrikes the selection with correction tape.","⌘/Ctrl V drives the reader. Escape stops playback.","⌘Z rewinds an edit. ⇧⌘Z restores it. ⌘N inserts a new sheet.","In Folio, adjust margins, read longer text, or export a sheet."]:
		lab(v,info,SANS,14)
	var buttons=row(v)
	button(buttons,"Back to studio",close_pop)
	button(buttons,"Licences",show_licenses)
func read_sheet():
	var v=pop(title,Vector2i(780,590))
	lab(v,title,SERIF,25)
	var reader=TextEdit.new()
	reader.editable=false
	reader.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	reader.text=doc.text
	reader.add_theme_font_override("font",MONO)
	reader.size_flags_vertical=Control.SIZE_EXPAND_FILL
	v.add_child(reader)
	var actions=row(v)
	for action in ["Set carriage","Copy selection","Cut selection"]:
		button(actions,action,func():
			var a=0
			var b=0
			if reader.has_selection():
				a=reader.get_selection_from_column()
				b=reader.get_selection_to_column()
				for i in reader.get_selection_from_line():a+=reader.get_line(i).length()+1
				for i in reader.get_selection_to_line():b+=reader.get_line(i).length()+1
			else:
				b=reader.get_caret_column()
				for i in reader.get_caret_line():b+=reader.get_line(i).length()+1
				a=b
			doc.anchor=a;doc.caret=b
			close_pop();set_mode("Write");machine.refresh()
			if action!="Set carriage":clipboard_action(action=="Cut selection"))
func export_sheet():
	io_dialog=FileDialog.new()
	io_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE
	io_dialog.access=FileDialog.ACCESS_FILESYSTEM
	io_dialog.use_native_dialog=true
	io_dialog.filters=PackedStringArray(["*.txt ; Plain text"])
	io_dialog.current_file=title.validate_filename()+".txt"
	root.add_child(io_dialog)
	io_dialog.file_selected.connect(func(path):
		var f=FileAccess.open(path,FileAccess.WRITE)
		if f:f.store_string(doc.text);f.close();message("Sheet exported")
		else:message("Could not write the selected file")
		io_dialog.queue_free())
	io_dialog.canceled.connect(func():io_dialog.queue_free())
	io_dialog.popup_centered_ratio(.65)

func cancel_replay():
	seq_token+=1
	busy=false
	machine.reader_cursor=-1
	if machine.page:machine.page.mask_from=-1
func clipboard_action(cut:bool):
	var r=doc.span()
	if r.x==r.y:
		message("Select a passage on the sheet first")
		return
	clip=doc.text.substr(r.x,r.y-r.x)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):DisplayServer.clipboard_set(clip)
	sfx.play("rewind",machine.variant("Punch"))
	changed()
	if not cut:
		message("Tape locked · %d characters"%clip.length())
		return
	doc.checkpoint()
	busy=true
	seq_token+=1
	var token=seq_token
	machine.tape_window=clip
	machine.reader_cursor=0
	doc.move_to(r.x,false)
	machine.refresh()
	await get_tree().create_timer(.22).timeout
	for i in range(r.x,r.y):
		if token!=seq_token:return
		machine.reader_cursor=i-r.x+1
		doc.move_to(i,false)
		machine.page.mask_from=r.x
		machine.page.mask_end=i+1
		machine.strike(doc.text[i],true)
		machine.refresh()
		await get_tree().create_timer(.055).timeout
	if token!=seq_token:return
	machine.page.mask_from=-1
	machine.reader_cursor=-1
	doc.anchor=r.x;doc.caret=r.y
	doc.replace("")
	busy=false
	machine.refresh()
	changed()
	message("Passage lifted · tape ready")
func paste_tape():
	var src=DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) and DisplayServer.clipboard_has() else clip
	src=src.replace("\r\n","\n").replace("\r","\n")
	if src.is_empty():message("Tape is empty");return
	busy=true
	seq_token+=1
	var token=seq_token
	doc.checkpoint()
	sfx.play("spring",machine.variant("Escapement"))
	machine.tape_window=src
	machine.reader_cursor=0
	for ch in src:
		if token!=seq_token:return
		machine.reader_cursor+=1
		sfx.play("reader",machine.variant("Punch"))
		write_char(ch,false)
		await get_tree().create_timer(.060+machine.variant("Punch")*.003).timeout
	busy=false
	machine.reader_cursor=-1
	machine.refresh(false)
	message("Tape playback complete")
func write_char(ch:String,checkpoint:=true):
	var prev:Vector2i=doc.points[doc.caret]
	if checkpoint:doc.checkpoint()
	machine.strike(ch)
	doc.replace(ch)
	var next:Vector2i=doc.points[doc.caret]
	if next.y!=prev.y and ch!="\n":machine.line_feed()
	if next.y==prev.y and prev.x<doc.right-6 and next.x>=doc.right-6:machine.ring_bell()
	machine.refresh(true,true)
	changed()
func erase(back:bool):
	if doc.span().x==doc.span().y:
		if (back and doc.caret==0) or (not back and doc.caret==doc.text.length()):return
		doc.checkpoint()
		doc.anchor=doc.caret+(-1 if back else 1)
	else:doc.checkpoint()
	machine.strike(doc.text[doc.span().x],true)
	doc.replace("")
	machine.refresh()
	changed()
func history(back:bool):
	var old=doc.text
	if doc.history(back):
		var last=0
		while last<mini(old.length(),doc.text.length()) and old[last]==doc.text[last]:last+=1
		if last<old.length() and old.length()>doc.text.length():machine.strike(old[last],true)
		elif last<doc.text.length():machine.strike(doc.text[last])
		sfx.play("rewind",machine.variant("Punch"))
		machine.line_feed()
		machine.refresh()
		changed()
		message("Tape rewound" if back else "Tape advanced")
func _unhandled_input(event):
	if is_instance_valid(dialog) or is_instance_valid(io_dialog):return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if not event.pressed:
				if selection_drag:
					machine.page.lock_row=false
					machine.refresh()
				selection_drag=false
				orbit_drag=false
				dragging_stop=-1
			elif mode=="Workshop":
				orbit_drag=true
			elif not busy:
				if mode=="Write" and mechanical_click(event):return
				var hit=machine.hit_sheet(event.position)
				if hit>=0:
					doc.move_to(hit,event.shift_pressed)
					selection_drag=true
					machine.page.lock_row=true
					machine.repaint()
					update_status()
		elif mode=="Workshop" and event.pressed:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
				machine.zoom=clampf(machine.zoom+(-.65 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .65),7,18)
				frame_camera()
	elif event is InputEventMouseMotion:
		if dragging_stop>=0 and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
			var unit=machine.camera.unproject_position(machine.carriage.to_global(Vector3(machine.col_x(1),0,0))).x-machine.camera.unproject_position(machine.carriage.to_global(Vector3(machine.col_x(0),0,0))).x
			var stop=stop_initial+roundi((event.position.x-stop_mouse_x)/maxf(1,unit))
			if dragging_stop==0:doc.left=clampi(stop,0,doc.right-8)
			else:doc.right=clampi(stop,doc.left+8,74)
			margins_changed()
		elif orbit_drag and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
			machine.yaw-=event.relative.x*.007
			machine.pitch=clampf(machine.pitch+event.relative.y*.006,.13,1.34)
			frame_camera()
		elif selection_drag and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
			var hit=machine.hit_sheet(event.position)
			if hit>=0:doc.move_to(hit,true);machine.repaint();update_status()
	if not event is InputEventKey or not event.pressed:return
	if event.keycode==KEY_ESCAPE:
		if busy:cancel_replay();machine.refresh();changed();message("Reader stopped")
		else:set_mode("Write")
		return
	if busy:return
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_A:doc.anchor=0;doc.caret=doc.text.length();machine.refresh();update_status()
			KEY_C:clipboard_action(false)
			KEY_X:clipboard_action(true)
			KEY_V:paste_tape()
			KEY_Z:history(not event.shift_pressed)
			KEY_Y:history(false)
			KEY_N:new_note()
			KEY_S:save_state();message("Saved locally" if not disk_error else "Save failed")
			KEY_O:set_mode("Folio")
			_:return
		get_viewport().set_input_as_handled()
		return
	if mode!="Write":return
	var p:Vector2i=doc.points[doc.caret]
	match event.keycode:
		KEY_BACKSPACE:erase(true)
		KEY_DELETE:erase(false)
		KEY_ENTER,KEY_KP_ENTER:write_char("\n")
		KEY_TAB:write_char("\t")
		KEY_LEFT:doc.move_to(doc.caret-1,event.shift_pressed)
		KEY_RIGHT:doc.move_to(doc.caret+1,event.shift_pressed)
		KEY_UP:doc.move_to(doc.nearest(p.x,maxi(0,p.y-1)),event.shift_pressed)
		KEY_DOWN:doc.move_to(doc.nearest(p.x,p.y+1),event.shift_pressed)
		KEY_HOME:doc.move_to(doc.nearest(doc.left,p.y),event.shift_pressed)
		KEY_END:doc.move_to(doc.nearest(doc.right,p.y),event.shift_pressed)
		KEY_SHIFT:machine.key_dip("Shift")
		_:
			if event.unicode<32:return
			write_char(String.chr(event.unicode))
	if event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_HOME,KEY_END]:
		sfx.play("slide",machine.variant("Housing"))
		machine.refresh()
		update_status()
	get_viewport().set_input_as_handled()

func mechanical_click(e:InputEventMouseButton)->bool:
	var at=e.position
	var cam=machine.camera
	for i in 2:
		if cam.unproject_position(machine.stop_nodes[i].global_position).distance_to(at)<12:
			dragging_stop=i
			stop_mouse_x=at.x
			stop_initial=doc.left if i==0 else doc.right
			sfx.play("stop",machine.variant("Stops"))
			return true
	for wheel in machine.wheels:
		if cam.unproject_position(wheel.global_position).distance_to(at)<22:
			var p:Vector2i=doc.points[doc.caret]
			doc.move_to(doc.nearest(p.x,maxi(0,p.y+(-1 if e.shift_pressed else 1))),false)
			machine.line_feed()
			machine.refresh()
			update_status()
			return true
	var pad=machine.handle.to_global(Vector3(-.43-.06*machine.variant("Return"),.36,.64+.03*machine.variant("Return")))
	if cam.unproject_position(pad).distance_to(at)<16:
		write_char("\n")
		return true
	for name_ in machine.keys:
		var k=machine.keys[name_]
		var center=cam.unproject_position(k.to_global(Vector3(0,.14,0)))
		var diff=at-center
		var radius=cam.unproject_position(k.to_global(Vector3(.22,.14,0))).distance_to(center)
		if absf(diff.x)>radius*(6 if name_==" " else 1) or absf(diff.y)>radius*.75:continue
		match name_:
			"Enter":write_char("\n")
			"Tab":write_char("\t")
			"Backspace":erase(true)
			"Shift":machine.key_dip("Shift")
			_:write_char(name_ if e.shift_pressed else name_.to_lower())
		return true
	return false

func build_native_menu():
	if OS.get_name()!="macOS" or not NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU):return
	var menubar=NativeMenu.get_system_menu(NativeMenu.MAIN_MENU_ID)
	var commands={
		"Sheet":{"New Sheet":new_note,"Rename Sheet…":rename_note,"Open Folio":func():set_mode("Folio"),"Export Plain Text…":export_sheet,"Save":save_state},
		"Machine":{"Copy to Tape":func():clipboard_action(false),"Cut to Tape":func():clipboard_action(true),"Play Tape":paste_tape,"Stop Reader":cancel_replay,"Rewind Edit":func():history(true),"Restore Edit":func():history(false)},
		"View":{"Writing Desk":func():set_mode("Write"),"Workshop":func():set_mode("Workshop"),"Reading Lens":func():set_mode("Write");toggle_lens(),"Writing Guide":show_help}}
	for section in commands:
		var menu=NativeMenu.create_menu()
		native_menus.append(menu)
		for caption in commands[section]:
			var action=commands[section][caption]
			NativeMenu.add_item(menu,caption,func(_tag):
				if not is_instance_valid(dialog) and (not busy or caption=="Stop Reader"):action.call())
		NativeMenu.add_submenu_item(menubar,section,menu)

func show_licenses():
	var body=pop("Licences",Vector2i(720,560))
	var reader=TextEdit.new()
	reader.editable=false
	reader.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	reader.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(reader)
	var notices=Engine.get_license_info()
	var documents=PackedStringArray([Engine.get_license_text()])
	for component in Engine.get_copyright_info():
		documents.append(component.name)
		for part in component.parts:
			documents.append("\n".join(part.copyright))
			documents.append(part.license)
	for name_ in notices:documents.append(name_+"\n"+notices[name_])
	if FileAccess.file_exists("res://fonts/LICENSE.txt"):
		documents.append(FileAccess.get_file_as_string("res://fonts/LICENSE.txt"))
	reader.text="\n\n".join(documents)
	button(body,"Close",close_pop)
