shader_type spatial;
uniform vec4 dark : source_color;
uniform vec4 pale : source_color;
uniform sampler2D veneer : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D figure : source_color,repeat_enable,filter_linear_mipmap_anisotropic;
varying vec2 board_uv;
varying vec2 desk_pos;
void vertex() { desk_pos=VERTEX.xz; board_uv = VERTEX.xz / vec2(12.8, 7.2) + vec2(.23,.14); }
void fragment() {
	vec3 grain = texture(veneer, board_uv).rgb;
	vec3 sample_color=texture(figure,board_uv*vec2(1.8,2.3)).rgb;
	float natural_grain=dot(sample_color,vec3(.25,.55,.2));
	float stain=clamp(.13+(natural_grain-.028)*11.5+grain.r*.31,0.,1.);
	ALBEDO = mix(dark.rgb, pale.rgb, stain) * mix(vec3(1.),sample_color/max(natural_grain,.007),.21);
	// Small-scale indirect light blocked by the cast pan and lamp base.
	// Direct shadows still follow each movable mechanism and light source.
	vec2 pan=abs(desk_pos-vec2(0.,.12))-vec2(2.93,1.78);
	float shell_distance=length(max(pan,0.)) + min(max(pan.x,pan.y),0.)-.23;
	float lamp_distance=length(desk_pos-vec2(-4.65,-.30))-.47;
	float contact=1.-smoothstep(-.12,.45,min(shell_distance,lamp_distance));
	AO=1.-.83*contact;
	ALBEDO*=1.-.23*contact;
	ROUGHNESS = .30 + .40 * grain.g;
	SPECULAR = .32;
	vec2 pixel = 1.0 / vec2(textureSize(veneer,0));
	float dx = texture(veneer, board_uv + vec2(pixel.x,0.)).b - grain.b;
	float dy = texture(veneer, board_uv + vec2(0.,pixel.y)).b - grain.b;
	NORMAL_MAP = normalize(vec3(-dx*.58,dy*.76,1.))*.5+.5;
}
