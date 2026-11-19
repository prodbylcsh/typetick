"""Produce repeatable mipmappable grain and finish maps, including pore relief."""
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

root=Path(__file__).resolve().parents[1]/"surfaces"
rng=np.random.default_rng(917)
def field(n, sy, sx):
    f=gaussian_filter(rng.standard_normal((n,n)),(sy,sx),mode="wrap")
    return (f-f.mean())/max(f.std(),.00001)
def save(name,channels):
    Image.fromarray(np.uint8(np.clip(np.stack(channels,axis=-1),0,1)*255)).save(root/name,optimize=True)
n=1536
y,x=np.mgrid[:n,:n]
# Slice growth rings at a shallow angle. Vary the cut depth independently
# of the smaller open pores to form cathedral grain in a long veneer sheet.
broad=field(n,98,147)
warp=field(n,35,120)*12+field(n,82,220)*17
coord=(y+warp+13*np.sin(x*2*np.pi/n+1.1))%n
phase=coord/33.391304348 + .8*np.sin(2*np.pi*coord/n+1.1)*np.cos(2*np.pi*x/n)
ring=(.5+.5*np.cos(phase*2*np.pi))**3
def warped(f):
    return map_coordinates(f,[coord,x],order=1,mode="grid-wrap",prefilter=False)
fibres=warped(field(n,1.2,41))
pores=np.clip((warped(field(n,.65,6))-.92)*.58,0,1)
grain=.51+.073*broad+.067*fibres-.164*ring-.172*pores+.035*warped(field(n,7,125))
save("veneer.png",[grain,.52+.055*fibres+.21*pores+.045*ring,.52-.19*pores-.08*ring+.035*fibres])
n=512
save("workshop-finish.png",[.5+.15*field(n,1,1),.5+.15*field(n,.6,24),.5+.14*field(n,8,8)])
