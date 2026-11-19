shader_type spatial;
uniform vec4 tint : source_color;
uniform sampler2D finish_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float metal = 0.0;
uniform float rough = 0.42;
uniform float micro_depth = 0.02;
uniform float polish = 0.0;
uniform float brushed = 0.0;
varying vec3 local_pos;
varying vec3 local_normal;
void vertex(){
	local_pos=VERTEX;
	local_normal=NORMAL;
}
void fragment(){
	vec3 weights=pow(abs(normalize(local_normal)),vec3(4.));
	weights/=max(dot(weights,vec3(1.)),.001);
	vec3 p=local_pos*2.2;
	vec3 grain=texture(finish_map,p.yz).rgb*weights.x+texture(finish_map,p.xz).rgb*weights.y+texture(finish_map,p.xy).rgb*weights.z;
	float structure=mix(grain.r,grain.g,brushed);
	ALBEDO=tint.rgb*(.93+.14*grain.b);
	ROUGHNESS=clamp(rough+(structure-.5)*.19+(grain.b-.5)*.115,.105,.96);
	METALLIC=metal;
	CLEARCOAT=polish;
	CLEARCOAT_ROUGHNESS=.3;
	// Bump in screen-space from the local, filtered surface height. This
	// follows the part as it moves and fades naturally below a pixel.
	vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
	vec3 tx=cross(dy,NORMAL),ty=cross(NORMAL,dx);
	float det=dot(dx,tx);
	vec3 gradient=(tx*dFdx(structure)+ty*dFdy(structure))*sign(det);
	NORMAL=normalize(max(abs(det),1e-8)*NORMAL-gradient*micro_depth);
}
