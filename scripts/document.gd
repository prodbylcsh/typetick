extends RefCounted

var text := ""
var caret := 0
var anchor := 0
var tape := ""
var patches := {}
var left := 4
var right := 68
var tab_width := 4
var points := []
var glyphs := []
var gaps := {}
var undo_stack := []
var redo_stack := []

func layout():
	points.clear()
	glyphs.clear()
	var at := Vector2i(left,0)
	for i in text.length():
		points.append(at)
		for spacer in str(gaps.get(str(i),"")):at=advance(at,spacer)
		glyphs.append(at)
		at=advance(at,text[i])
	points.append(at)

func advance(at:Vector2i,ch:String)->Vector2i:
	if ch=="\n":return Vector2i(left,at.y+1)
	at.x+=tab_width-(at.x-left)%tab_width if ch=="\t" else 1
	return Vector2i(left,at.y+1) if at.x>=right else at

func span() -> Vector2i:
	return Vector2i(mini(anchor,caret), maxi(anchor,caret))

func snapshot() -> Dictionary:
	return {"text":text,"caret":caret,"anchor":anchor,"patches":patches.duplicate(),"gaps":gaps.duplicate()}

func restore(data):
	text = str(data.get("text",""))
	caret = clampi(int(data.get("caret",text.length())),0,text.length())
	anchor = clampi(int(data.get("anchor",caret)),0,text.length())
	gaps = data.get("gaps",{}).duplicate()
	patches = data.get("patches",{}).duplicate()
	layout()

func checkpoint():
	undo_stack.append(snapshot())
	if undo_stack.size()>120: undo_stack.pop_front()
	redo_stack.clear()

func replace(s:String):
	var r := span()
	var gap=""
	for i in range(r.x,r.y):
		patches[str(glyphs[i])]=true
		gap+=str(gaps.get(str(i),""))+(text[i] if text[i] in ["\n","\t"] else " ")
	gap+=str(gaps.get(str(r.y),""))
	var updated={}
	for key in gaps:
		var index=int(key)
		if index<r.x:updated[key]=gaps[key]
		elif index>r.y:updated[str(index+s.length()-(r.y-r.x))]=gaps[key]
	var remainder=gap.substr(mini(s.length(),gap.length()))
	if not remainder.is_empty():updated[str(r.x+s.length())]=remainder
	gaps=updated
	text = text.left(r.x)+s+text.substr(r.y)
	caret = r.x+s.length()
	anchor = caret
	tape += s
	layout()

func move_to(idx:int, extend:bool):
	caret = clampi(idx,0,text.length())
	if not extend: anchor=caret

func nearest(col:int,row:int) -> int:
	var best := 0
	var score := 2147483647
	for i in points.size():
		var p:Vector2i=points[i]
		var d := absi(p.y-row)*128+absi(p.x-col)
		if d<score:
			score=d
			best=i
	return best

func history(backward:bool) -> bool:
	var source=undo_stack if backward else redo_stack
	var target=redo_stack if backward else undo_stack
	if source.is_empty(): return false
	target.append(snapshot())
	restore(source.pop_back())
	return true
