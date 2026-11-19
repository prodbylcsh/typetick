shader_type spatial;
render_mode cull_disabled;
uniform int codes[8];
uniform sampler2D fibres : repeat_enable,filter_linear_mipmap;
varying vec2 strip;
void vertex() {
	strip=VERTEX.xz;
	// Continue the sheet around the feed and take-up rollers.
	float over=max(abs(strip.y)-.47,0.);
	float angle=over/.157;
	VERTEX.y=.393+.157*(cos(angle)-1.);
	VERTEX.z=sign(strip.y)*(min(abs(strip.y),.47)+.157*sin(angle));
	NORMAL=vec3(0.,cos(angle),sign(strip.y)*sin(angle));
}
void fragment() {
	vec2 pitch=vec2(.057,.116);
	vec2 coords=strip/pitch+vec2(4.);
	ivec2 cell=ivec2(floor(coords));
	float d=1.;
	if(all(greaterThanEqual(cell,ivec2(0))) && all(lessThan(cell,ivec2(8)))) {
		if((codes[cell.y] & (1<<cell.x))!=0) {
			d=length((fract(coords)-.5)*pitch)-.018;
		}
	}
	float guide=length(vec2(abs(strip.x)-.251,(fract(coords.y)-.5)*pitch.y))-.009;
	float openness=min(d,guide);
	ALPHA=smoothstep(-fwidth(openness),max(fwidth(openness),.0001),openness);
	ALPHA_SCISSOR_THRESHOLD=.5;
	ALBEDO=vec3(.62,.47,.25)*(.90+.15*texture(fibres,strip*3.).g);
	ROUGHNESS=.86;
	SPECULAR=.18;
}
