shader_type spatial;
render_mode cull_disabled;
uniform sampler2D impressions : source_color,filter_linear,repeat_disable;
uniform sampler2D fibres : repeat_enable,filter_linear_mipmap;
uniform float finish_roughness=.82;
uniform float crumple=0.;
void vertex(){
	// The lower writing line lies against the platen; the unsupported
	// upper corners can turn away from the carriage.
	float height=smoothstep(.12,1.,1.-UV.y);
	float across=UV.x-.52;
	VERTEX.z+=height*(.09*sin(4.5*UV.x)-.29*across*across);
	VERTEX.y-=height*.025*cos(UV.x*5.);
	NORMAL=normalize(vec3(-height*(.405*cos(4.5*UV.x)-.58*across)/5.25,.025,1.));
}
void fragment(){
	vec3 marks=texture(impressions,UV).rgb;
	vec3 grain=texture(fibres,UV*vec2(4.,3.)).rgb;
	ALBEDO=marks*(.77+.07*grain.g);
	ROUGHNESS=finish_roughness;
	SPECULAR=.22;
	float ridges=sin(UV.x*79.+UV.y*21.+sin(UV.y*20.));
	NORMAL_MAP=normalize(vec3((grain.g-.5)*.055+crumple*ridges*.053,(grain.r-.5)*.065,1.))*.5+.5;
}
