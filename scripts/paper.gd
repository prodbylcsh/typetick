extends Control
var doc
var settings:Dictionary
var mask_from := -1
var mask_end := -1
var lock_row := false
var start_row := 0
const CW := 14.0
const LH := 34.0
const BASE := 618.0
const X0 := 26.0
const MONO = preload("res://fonts/DejaVuSansMono.ttf")
const SERIF = preload("res://fonts/DejaVuSerif.ttf")
const SANS = preload("res://fonts/DejaVuSans.ttf")
var grain_tex:ImageTexture
var seen_surface := ""

func cell_x(col:int) -> float: return X0+CW*col
func baseline(row:int) -> float: return BASE+(row-start_row)*LH

func _draw():
	if doc==null or doc.points.is_empty(): return
	var paper:Color=Color(settings.paper)
	var ink:Color=Color(settings.ink)
	var surface:String=settings.surface
	draw_rect(Rect2(Vector2.ZERO,size),paper)
	if seen_surface != surface:
		seen_surface=surface
		var im=Image.create(128,128,false,Image.FORMAT_RGBA8)
		var rng=RandomNumberGenerator.new()
		rng.seed=1786
		for y in 128:
			for x in 128:
				var strength:float=rng.randf_range(0,.12 if surface in ["Rough","Linen","Crumpled"] else .032)
				if surface=="Linen" and (x%4==0 or y%5==0): strength+=.058
				if surface=="Crumpled": strength+=.10*pow(absf(sin(x*.032+sin(y*.054))),14)
				im.set_pixel(x,y,Color(.33,.26,.19,strength))
		grain_tex=ImageTexture.create_from_image(im)
	draw_texture_rect(grain_tex,Rect2(Vector2.ZERO,size),true)
	var rule=Color(paper.darkened(.18),.32)
	for col in [doc.left,doc.right]:draw_line(Vector2(cell_x(col)-3,20),Vector2(cell_x(col)-3,size.y-10),rule,1)
	if not lock_row:start_row=doc.points[doc.caret].y
	var sel:Vector2i=doc.span()
	var font:Font=MONO if settings.font=="Typewriter" else (SERIF if settings.font=="Book serif" else SANS)
	for row in range(maxi(0,start_row-18),start_row+2):
		for col in range(doc.left,doc.right):
			if doc.patches.has(str(Vector2i(col,row))):
				draw_rect(Rect2(cell_x(col)-1,baseline(row)-23,CW+1,27),paper.lightened(.16) if paper.v<.9 else paper.darkened(.045))
	for i in doc.text.length():
		var p:Vector2i=doc.glyphs[i]
		if p.y<start_row-18 or p.y>start_row+1:continue
		var pos=Vector2(cell_x(p.x),baseline(p.y))
		if i>=sel.x and i<sel.y:draw_rect(Rect2(pos-Vector2(0,23),Vector2(CW,31)),Color(.36,.65,.63,.48))
		if mask_from>=0 and i>=mask_from and i<mask_end:
			draw_rect(Rect2(pos-Vector2(1,23),Vector2(CW+1,28)),paper.lightened(.16) if paper.v<.9 else paper.darkened(.045))
			continue
		var ch:String=doc.text[i]
		if ch in ["\n","\t"]:continue
		var dye=ink
		if settings.finish=="Pearlescent":dye=ink.lerp(Color("a8bacc"),.25+sin(float(i)*.9)*.17)
		if settings.finish=="Flaked" and i%5==0:dye=ink.lerp(paper,.31)
		var bleed:float=settings.bleed
		if surface=="Rough" or settings.hardness=="Soft":bleed=minf(1,bleed*1.18)
		if bleed>.01:draw_string_outline(font,pos,ch,HORIZONTAL_ALIGNMENT_LEFT,-1,22,1+int(bleed*2),Color(dye,bleed*.5))
		draw_string(font,pos,ch,HORIZONTAL_ALIGNMENT_LEFT,-1,22,dye)
		if settings.finish=="Flaked" or surface=="Rough":
			for j in (9 if settings.finish=="Flaked" else 4):
				var bit=absi(hash(Vector2i(i,j)))
				draw_rect(Rect2(pos.x+bit%13,pos.y-2-(bit/13)%17,1,1.6),Color(paper,.72))
	var cp:Vector2i=doc.points[doc.caret]
	draw_line(Vector2(cell_x(cp.x),baseline(cp.y)+5),Vector2(cell_x(cp.x)+CW-2,baseline(cp.y)+5),Color("ad683b"),3)
