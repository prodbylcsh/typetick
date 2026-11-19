"""Generate editable glTF 2.0 assemblies in metres (one scene unit per key pitch pair)."""
from math import sin, cos, pi, sqrt
from pathlib import Path
import json, struct
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[1] / "models"
NAMES = ["Atelier", "Continental", "Courier", "Executive", "Studio", "Metropolitan", "Traveller", "Foundry"]
def rgb(s):
    return [((int(s[i:i+2],16)/255+.055)/1.055)**2.4 for i in (0,2,4)] + [1]
def mat(name, color, metal=0, rough=.45):
    return dict(name=name,pbrMetallicRoughness=dict(baseColorFactor=rgb(color),metallicFactor=metal,roughnessFactor=rough),doubleSided=True)
class Model:
    def __init__(self,v):
        self.buf=bytearray()
        self.doc=dict(asset=dict(version="2.0",generator="TypeTick Workshop"),scene=0,scenes=[dict(nodes=[])],nodes=[],meshes=[],accessors=[],bufferViews=[],materials=[
            mat("Stove enamel",["274a40","673d34","324759","797664","4d595d","443d42","636d52","493c30"][v],.34,.30),
            mat("Burnished nickel","b5b2a1",.8,.25), mat("Machined brass","c49c5c",.69,.28),mat("Graphite","282c2b",.26,.39),mat("Key insert","242321" if v%2==0 else "d2c3a2",.0,.29),mat("Vulcanised rubber","292929",.04,.82),mat("Ribbon","382e35",.03,.89),mat("Punched stock","cfad76",0,.81)])
    def attr(self,data):
        off=len(self.buf)
        for p in data:self.buf.extend(struct.pack("<3f",*p))
        d=self.doc
        d["bufferViews"].append(dict(buffer=0,byteOffset=off,byteLength=len(self.buf)-off,target=34962))
        d["accessors"].append(dict(bufferView=len(d["bufferViews"])-1,componentType=5126,count=len(data),type="VEC3",min=list(map(min,zip(*data))),max=list(map(max,zip(*data)))))
        return len(d["accessors"])-1
    def faces(self,name,faces,m):
        pts=[]; normals=[]
        for face in faces:
            for i in range(1,len(face)-1):
                a,b,c=face[0],face[i],face[i+1]
                u=[b[k]-a[k] for k in range(3)]; w=[c[k]-a[k] for k in range(3)]
                n=[u[1]*w[2]-u[2]*w[1],u[2]*w[0]-u[0]*w[2],u[0]*w[1]-u[1]*w[0]]
                l=sqrt(sum(x*x for x in n))
                if l<1e-9:continue
                pts.extend([a,b,c]);normals.extend([[x/l for x in n]]*3)
        # Weld normals across gently curving faces. Keep the rims of machined
        # parts crisp where the bevel meets a perpendicular face.
        around=defaultdict(set)
        for pt,norm in zip(pts,normals):
            around[pt].add(tuple(round(t,6) for t in norm))
        smooth={}
        for idx,(pt,norm) in enumerate(zip(pts,normals)):
            key=(pt,tuple(round(t,6) for t in norm))
            if key not in smooth:
                neighbours=[v for v in around[pt] if sum(x*y for x,y in zip(v,norm))>.61]
                total=list(map(sum,zip(*neighbours)))
                length=sqrt(sum(x*x for x in total))
                smooth[key]=[x/length for x in total]
            normals[idx]=smooth[key]
        d=self.doc
        unique={}
        positions=[]; directions=[]; indices=[]
        for point,normal in zip(pts,normals):
            vertex=(point,tuple(normal))
            if vertex not in unique:
                unique[vertex]=len(positions)
                positions.append(point); directions.append(normal)
            indices.append(unique[vertex])
        attributes=dict(POSITION=self.attr(positions),NORMAL=self.attr(directions))
        start=len(self.buf)
        self.buf.extend(struct.pack("<%dH"%len(indices),*indices))
        d["bufferViews"].append(dict(buffer=0,byteOffset=start,byteLength=len(indices)*2,target=34963))
        self.buf.extend(bytes(-len(self.buf)%4))
        d["accessors"].append(dict(bufferView=len(d["bufferViews"])-1,componentType=5123,count=len(indices),type="SCALAR"))
        d["meshes"].append(dict(name=name,primitives=[dict(attributes=attributes,indices=len(d["accessors"])-1,material=m)]))
        d["scenes"][0]["nodes"].append(len(d["nodes"]))
        d["nodes"].append(dict(name=name,mesh=len(d["meshes"])-1))
    def rings(self,name,rings,m):
        f=[rings[0],rings[-1][::-1]]
        for a,b in zip(rings,rings[1:]):
            for i in range(len(a)):
                j=(i+1)%len(a); f.append([a[i],b[i],b[j],a[j]])
        self.faces(name,f,m)
    def box(self,name,p,size,m,r=.05,tilt=0):
        x,y,z=p; w,h,d=size; r=min(r,w*.23,d*.23); rings=[]
        for Y,f in [(-h/2,.947),(-h*.46,.976),(-h*.39,.994),(-h*.30,1),(h*.27,1),(h*.39,.994),(h*.47,.974),(h/2,.95)]:
            ring=[]
            for cx,cz,start in [(w/2-r,d/2-r,0),(-w/2+r,d/2-r,90),(-w/2+r,-d/2+r,180),(w/2-r,-d/2+r,270)]:
                for j in range(9):
                    a=(start+j*11.25)*pi/180; Z=(cz+r*sin(a))*f
                    ring.append((x+(cx+r*cos(a))*f,y+Y+tilt*Z,z+Z))
            rings.append(ring)
        self.rings(name,rings,m)
    def rod(self,name,a,b,r,m,n=16,r2=None):
        n=max(48,n) if r>.10 and n>=10 else n
        v=[b[i]-a[i] for i in range(3)]
        l=sqrt(sum(x*x for x in v)); x,y,z=[h/l for h in v]
        h=sqrt(x*x+z*z); u=(z/h,0,-x/h) if h>.0001 else (1,0,0)
        w=(y*u[2]-z*u[1],z*u[0]-x*u[2],x*u[1]-y*u[0])
        rings=[]
        for p,R in [(a,r),(b,r if r2 is None else r2)]:
            rings.append([tuple(p[i]+R*(u[i]*cos(j*2*pi/n)-w[i]*sin(j*2*pi/n)) for i in range(3)) for j in range(n)])
        # polygon first face points opposite the axis for box-style ring order
        self.rings(name,rings,m)
    def lathe(self,name,cx,cz,profile,material,segments=64):
        rings=[[(cx+r*cos(i*2*pi/segments),y,cz+r*sin(i*2*pi/segments))
                for i in range(segments)] for y,r in profile]
        self.rings(name,rings,material)
    def hoop(self,name,y,outer,inner,h,material):
        faces=[]
        for i in range(64):
            a=i*2*pi/64; b=(i+1)*2*pi/64
            def pt(angle,r,height):return (r*cos(angle),height,r*sin(angle))
            for r1,y1,r2,y2 in [(outer,y,outer,y+h),(outer,y+h,inner,y+h),(inner,y+h,inner,y),(inner,y,outer,y)]:
                faces.append([pt(a,r1,y1),pt(a,r2,y2),pt(b,r2,y2),pt(b,r1,y1)])
        self.faces(name,faces,material)
    def save(self,path):
        self.doc["buffers"]=[dict(byteLength=len(self.buf))]
        j=json.dumps(self.doc,separators=(",",":")).encode();j+=b' '*(-len(j)%4)
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(b'glTF'+struct.pack("<IIII",2,28+len(j)+len(self.buf),len(j),0x4e4f534a)+j+struct.pack("<II",len(self.buf),0x004e4942)+self.buf)
def build(k,v):
    s=Model(v); box=s.box; rod=s.rod; f=v/7; count=3+v
    if k=="Housing":
        for x in [-2.78,2.78]:
            for z in [-1.37,1.61]:
                s.lathe("Shock mount",x,z,[(-.013,.19),(.018,.24),(.16,.24),(.19,.20)],5)
        box("Rolled lower pan",(0,.20,.12),(6.77,.21,4.02),3,.34)
        box("Chassis parting seam",(0,.305,.12),(6.86,.048,4.04),1,.32)
        box("Cast chassis",(0,.53,.12),(7-.24*f,.68,4.15),0,.18+.48*f,-.10)
        box("Keyboard well",(0,.83,.78),(6.34,.12,2.57),3,.18,-.16)
        for sign in [-1,1]:
            box("Enamel cheek",(sign*3.17,.94,.55),(.55,.52,3.38),0,.23,-.16)
            box("Carriage bearing",(sign*2.91,1.32,-1.37),(.51,.75,1.01),0,.17,-.21)
        box("Front fascia",(0,.69,2),(6.52,.52,.33),0,.15)
        box("Badge surround",(-2.03,.74,2.169),(1.37,.259,.044),1,.12)
        box("Maker plate",(-2.03,.74,2.191),(1.32,.22,.016),3,.1)
        for x in [-2.59,-1.47]:
            rod("Badge pin",(x,.74,2.196),(x,.74,2.208),.017,2,16)
        for j in range(count):
            box("Chrome fluting",((j-(count-1)/2)*.15,.72,2.171),(.054,.18,.014),2,.01)
    elif k=="Keys":
        rod("Keystem",(0,-.21,0),(0,.06,0),.047,1)
        if v in [1,3,5,7]:
            box("Key bezel",(0,.045,0),(.46,.105,.44),1,.026+.016*v)
            box("Inset keytop",(0,.109,0),(.416,.064,.398),4,.023+.017*v)
        else:
            s.lathe("Nickel retaining cup",0,0,[(.0,.132),(.032,.147),(.085,.204),(.111,.224),(.121,.225),(.125,.216)],1)
            s.lathe("Inset legend disc",0,0,[(.126,.209),(.139,.205),(.142,.190)],4)
            s.hoop("Rolled bright rim",.125,.220,.204,.020,1)
    elif k=="Platen":
        rod("Rubber platen",(-2.99,0,0),(2.99,0,0),.222+.022*f,5,48)
        for sign in [-1,1]:
            for j in range(2+v):
                x=sign*(2.76+j*.026)
                rod("End ferrule",(x,0,0),(x+.016,0,0),.247,1,32)
    elif k=="Knobs":
        rod("Hub",(-.2,0,0),(.2,0,0),.13,1)
        rod("Handwheel",(-.15,0,0),(.15,0,0),.265+.05*f,3,12+v*4)
        for i in range(10+v*2):
            a=i*2*pi/(10+v*2); y=(.25+.05*f)*cos(a);z=(.25+.05*f)*sin(a)
            rod("Flute",(-.115,y,z),(.115,y,z),.029,1 if v%3==1 else 3,6)
    elif k=="Return":
        rod("Return arm",(0,0,0),(-.43-.06*v,.35,.64+.03*v),.039+.016*f,1)
        box("Palm pad",(-.43-.06*v,.36,.64+.03*v),(.34+.02*v,.074,.21+.08*f),3,.09)
    elif k=="Bail":
        for sg in [-1,1]:
            rod("Bail link",(sg*2.55,0,0),(sg*2.55,.29,.24+.04*f),.032+.01*f,1)
        rod("Paper bail",(-2.6,.29,.24),(2.6,.29,.24),.03,1)
        for i in range(2+v%4):
            x=-1.68+i*(3.36/(1+v%4))
            rod("Feed wheel",(x-.10-.04*f,.29,.24),(x+.10+.04*f,.29,.24),.085+.025*f,5)
    elif k in ["Spools","Correction"]:
        rod("Wound correction stock" if k=="Correction" else "Wound silk",(0,.025,0),(0,.14,0),.365,4 if k=="Correction" else 6,40)
        for y in [0,.15]:
            s.hoop("Stamped outer rim",y-.012,.425,.35,.028,3)
            s.hoop("Pressed lip",y+.012,.42,.409,.009,1)
            rod("Spool hub",(0,y,0),(0,y+.023,0),.135,3,32)
            for j in range(count+2):
                a=j*2*pi/(count+2)
                rod("Pressed web",(.115*cos(a),y+.010,.115*sin(a)),(.375*cos(a+.21),y+.010,.375*sin(a+.21)),.043,3,8)
        rod("Spindle",(0,.16,0),(0,.22,0),.067,2,20)
        for j in range(count):
            a=2*pi*j/count
            rod("Raised spoke",(.09*cos(a),.171,.09*sin(a)),(.37*cos(a),.171,.37*sin(a)),.018+.007*f,1,8)
    elif k=="Typebars":
        rod("Steel shank",(0,0,0),(0,.035+.028*f,-.77),.014+.005*f,1,4+v)
        box("Type slug",(0,.045,-.79),(.078+.018*f,.084,.093),3,.012)
        box("Type face",(0,.095,-.79),(.050,.017,.049+.013*f),1,.006)
    elif k=="Punch":
        box("Recorder casing",(0,0,0),(.89+.08*f,.32,1.30),0,.08+.1*f)
        for z in [-.47,.45]:
            rod("Tape axle",(-.46,.20,z),(.46,.20,z),.107+.024*f,2,16+v*2)
        box("Reader throat",(0,.28,.015),(.85,.09,.145+.06*f),1,.04)
        for j in range(3+v):
            box("Reader spring",((j-(2+v)/2)*.052,.35,0),(.025,.115,.035),2,.003)
    elif k=="Bell":
        rod("Bell skirt",(0,0,0),(0,.15+.065*f,0),.21+.02*f,2,20+2*v,.075)
        rod("Crown",(0,.15,0),(0,.22+.06*f,0),.04,1)
    elif k=="Stops":
        box("Stop clamp",(0,0,0),(.12+.035*f,.12,.15),1,.025)
        box("Stop thumb",(0,.07,0),(.13+.055*f,.057+.015*f,.17),2,.015+.016*f)
    elif k=="Escapement":
        rod("Ratchet hub",(0,0,0),(0,.047,0),.17,2,32)
        for j in range(10+v):
            a=2*pi*j/(10+v)
            rod("Ratchet tooth",(.15*cos(a),.021,.15*sin(a)),(.204*cos(a+.05),.021,.204*sin(a+.05)),.026,2,4)
    elif k=="Guides":
        for sg in [-1,1]:
            rod("Vibrator fork",(sg*.21,0,0),(sg*(.15+.035*f),.17+.03*f,0),.021+.006*f,1)
        box("Ribbon window",(0,.09,0),(.39,.084+.018*f,.025),6,.005)
    elif k=="Spacebar":
        box("Space key",(0,0,0),(2.8+.32*f,.14,.34+.08*f),4,.09+.04*f)
        for sg in [-1,1]:
            rod("Stabilizer",(sg*.9,-.21,0),(sg*.9,-.03,0),.039+.008*f,1)
    elif k=="Lamp":
        s.lathe("Weighted base",0,0,[(-.01,.4),(.025,.46),(.065,.47),(.09,.455),(.11,.41),(.135,.39),(.16,.20),(.20,.125)],2)
        s.lathe("Turned stem collar",0,0,[(.16,.13),(.24,.13),(.27,.089),(.31,.075)],2)
        rod("Post",(0,.1,0),(.01,1.6+.09*v,0),.04+.01*f,2)
        rod("Arm",(.01,1.6+.09*v,0),(.42,1.83+.08*v,.21),.037,2)
        # An open-backed enamel shade with a pale inner reflector and rolled lip.
        faces=[]; inside=[]
        base=1.72+.08*v
        for j in range(40):
            a=-.21+j*(pi+.42)/40; b=-.21+(j+1)*(pi+.42)/40
            def shade(t,x,r):return (.35+x,base+r*sin(t),.28+r*cos(t))
            for x1,x2,r1,r2 in [(-.64,-.59,.25,.31),(-.59,-.5,.31,.345),(-.5,.5,.345,.345),(.5,.59,.345,.31),(.59,.64,.31,.25)]:
                faces.append([shade(a,x1,r1),shade(b,x1,r1),shade(b,x2,r2),shade(a,x2,r2)])
                inside.append([shade(a,x1,r1-.012),shade(a,x2,r2-.012),shade(b,x2,r2-.012),shade(b,x1,r1-.012)])
        s.faces("Enamel gallery",[face[::-1] for face in faces],0);s.faces("Porcelain lining",[face[::-1] for face in inside],7)
        for sg in [-1,1]:
            rod("Shade beading",(-.26,base-.062,.28+sg*.327),(.96,base-.062,.28+sg*.327),.013,2)
            rod("Suspension arm",(.012,1.52+.08*v,0),(.35+sg*.64,base+.07,.28),.026,2)
            rod("Swivel screw",(.35+sg*.62,base+.07,.28),(.35+sg*.69,base+.07,.28),.054,2,32)
        rod("Socket tube",(-.18,base+.045,.28),(.84,base+.045,.28),.071,7,32)
        for side in [-1,1]:
            cap=[(.35+side*.643,base+.25*sin(-.21+j*(pi+.42)/40),.28+.25*cos(-.21+j*(pi+.42)/40)) for j in range(41)]
            s.faces("Shade end",[cap if side<0 else cap[::-1]],0)
        # The pull hangs vertically and the power lead lies flat on the desk.
        for j in range(14):
            y=base-.03-j*.025
            rod("Ball chain",(.77,y,.22),(.77,y-.018,.22),.011,2,8)
        rod("Pull finial",(.77,base-.38,.22),(.77,base-.47,.22),.032,2,16,.020)
        cord=[(-.22,.024,-.32),(-.43,.020,-.55),(-.72,.018,-.61),(-1.14,.017,-.58),(-1.52,.017,-.66),(-1.96,.017,-1.00),(-2.38,.017,-1.29),(-3.2,.017,-1.45),(-6,.017,-1.62)]
        for a,b in zip(cord,cord[1:]):rod("Power lead",a,b,.015,5,10)

    # The mounts are common; handles, stampings, guards and actuators differ.
    if k=="Housing":
        for sg in [-1,1]:
            x=sg*3.27
            if v in [0,3,6]:
                for j in range(2+v//3):
                    rod("Side moulding",(x,.65+j*.066,1.86),(x,.81+j*.066,-.23),.025,2 if v==0 else 1,10)
            if v in [1,4]:
                box("Travel bumper",(sg*3.38,.60,1.12),(.24,.42,1.7),5,.15,-.12)
                rod("Carry handle",(sg*2.5,.38,2.22),(sg*1.7,.38,2.22),.064,1)
            if v in [2,5,7]:
                for j in range(3+v%3):
                    box("Pressed vent",(sg*(2.12+j*.16),.77,2.17),(.072,.19,.032),3,.02)
                box("Coachwork flange",(sg*3.41,.66,.27),(.13,.58,2.80),1,.06,-.12)
            if v in [3,7]:
                rod("External frame stay",(sg*2.94,.36,1.98),(sg*3.36,1.48,-1.06),.08,2 if v==3 else 3,12)
    if k=="Keys" and v in [2,3,5,6,7]:
        for sg in [-1,1]:
            rod("Key support",(.10*sg,-.185,0),(.14*sg,.04,0),.025,2 if v==5 else 1,6)
    if k=="Knobs":
        for sg in [-1,1]:
            rod("Hub cap",(sg*.146,0,0),(sg*.172,0,0),.132,2 if v%2==0 else 1,10+3*v)
            if v in [2,4,6]:rod("Winding stud",(sg*.16,.156,0),(sg*.24,.156,0),.046,2,12)
    if k=="Return" and v>0:
        a=(-.43-.06*v,.35,.64+.03*v)
        if v%2:rod("Counter lever",(0,.005,.12),a,.022,2,8)
        if v>=4:rod("Swivel grip",(a[0]-.16,a[1]+.06,a[2]),(a[0]+.16,a[1]+.06,a[2]),.071,4,16)
    if k=="Typebars" and v in [2,3,5,7]:
        for sg in [-1,1]:
            rod("Forked type arm",(0,0,0),(sg*.027,.03,-.49),.009,2 if v==5 else 1,5)
            rod("Shoulder",(sg*.027,.03,-.49),(0,.04,-.74),.009,1,5)
    if k=="Punch" and v>0:
        for side in [-1,1]:
            box("Ribbon guard",(side*.395,.25,.28),(.064,.17,.47),1 if v%2 else 3,.022)
        if v in [3,4,7]:
            rod("Winding crank",(.44,.2,-.47),(.52,.33,-.47),.022,1)
            rod("Crank grip",(.52,.33,-.47),(.60,.33,-.47),.038,3)
    if k=="Spools" and v in [1,3,5,7]:
        for j in range(4+v):
            a=2*pi*j/(4+v)
            rod("Spool window",(.22*cos(a),.17,.22*sin(a)),(.22*cos(a),.18,.22*sin(a)),.050,6,12)
    if k=="Spacebar" and v in [1,3,4,6,7]:
        for j in range(1+v%3):
            box("Grip rib",(0,.069,-.084+j*.061),(2.26,.018,.023),2 if v==3 else 4,.01)
    if k=="Lamp" and v in [2,3,6,7]:
        rod("Anglepoise link",(.17,.12,0),(.18,1.58+.09*v,0),.026,1)
        rod("Shade hinge",(-.07,1.58+.09*v,0),(.24,1.58+.09*v,0),.079,2)
    if k=="Bell":
        if v in [1,3,6]:
            rod("Dome lip",(0,-.02,0),(0,.025,0),.236+.018*f,1,32)
        if v in [2,4,7]:
            rod("Suspension yoke",(-.25,-.04,0),(-.25,.31,0),.024,1)
            rod("Hanger",(-.25,.31,0),(0,.28,0),.023,1)
            rod("Suspension pin",(0,.19,0),(0,.29,0),.019,3)
        angle=(v+1)*.49
        rod("Striker spring",(.26*cos(angle),-.05,.26*sin(angle)),(.25*cos(angle),.14+.009*v,.25*sin(angle)),.011,1,8)
        rod("Clapper",(.23*cos(angle),.13,.23*sin(angle)),(.26*cos(angle),.16,.26*sin(angle)),.036,3)
    if k=="Stops":
        if v in [0,3,6]:
            for j in range(2+v//3):
                box("Grip knurl",((j-(1+v//3)/2)*.028,.10,.01),(.012,.023,.11),1,.003)
        elif v in [2,5,7]:
            rod("Cam lock",(0,.09,0),(.025,.16,.02),.021,1)
            box("Cam paddle",(.035,.16,.025),(.083,.026,.11+.009*v),3,.02)
        else:rod("Screw adjuster",(0,.08,0),(0,.13+.005*v,0),.044,3,10)
    if k=="Platen":
        for sg in [-1,1]:
            if v in [1,3,5]:
                rod("Drum shoulder",(sg*2.91,0,0),(sg*3.0,0,0),.251,2,16+v*2)
            if v in [2,4,6,7]:
                for j in range(4+v):
                    a=j*2*pi/(4+v)
                    rod("Index tooth",(sg*2.86,.24*cos(a),.24*sin(a)),(sg*2.94,.24*cos(a),.24*sin(a)),.021,2,6)
    if k=="Guides":
        if v%2:
            box("Lift bridge",(0,-.018,0),(.43,.035,.05),2,.01)
        for j in range(1+v//2):
            rod("Eyelet",(-.16+j*.07,.16,0),(-.16+j*.07,.185+.005*v,0),.012,1,8)
    if k=="Housing":
        # Curved typebasket comb and cast cheeks around the ribbon spindles.
        for j in range(20):
            a=(j/20-.5)*2.48; b=((j+1)/20-.5)*2.48
            rod("Basket comb",(1.03*sin(a),1.43,-1.34+1.03*cos(a)),(1.03*sin(b),1.43,-1.34+1.03*cos(b)),.045,3,8)
        for sg in [-1,1]:
            box("Spool platform",(sg*2.12,1.25,-.92),(1.87,.17,1.04),0,.26)
            for x,z in [(sg*3.16,1.48),(sg*2.74,-.62)]:
                rod("Slotted fastener",(x,1.031 if z>0 else 1.331,z),(x,1.056 if z>0 else 1.356,z),.038,1,12)
    if k=="Correction":
        for j in range(2+v):
            a=j*2*pi/(2+v)
            rod("Take-up pin",(.31*cos(a),.169,.31*sin(a)),(.31*cos(a),.19+.003*v,.31*sin(a)),.023,4,10)
    if k=="Punch":
        for sg in [-1,1]:
            for x in [-.31,.31]:
                rod("Feed reel lip",(x-.013,.23,sg*.48),(x+.013,.23,sg*.48),.165+.008*f,1,24)
            rod("Wound paper",(-.28,.23,sg*.48),(.28,.23,sg*.48),.145+.009*f,7,32)
    s.save(ROOT/k/(NAMES[v]+".glb"))
if __name__=="__main__":
    for k in "Housing Keys Platen Knobs Return Bail Spools Correction Typebars Punch Bell Stops Escapement Guides Spacebar Lamp".split():
        for v in range(8):build(k,v)
