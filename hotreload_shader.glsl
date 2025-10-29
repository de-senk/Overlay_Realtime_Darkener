#if 0
OUT_IN vec2 TexCoords;
OUT_IN vec4 iterated_color;
#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;
in vec2 vert_uv0;
uniform mat4 projection;
void main() {
    TexCoords = vert_uv0.xy;
    gl_Position = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color = vert_color;
}
#endif // VERTEX_SHADER
#ifdef FRAGMENT_SHADER
out vec4 color;
uniform sampler2D diffuse_texture;
const vec2 texel_size = vec2(1.0/1920.0,1.0/1080.0);
float luminance(vec3 c){return dot(c,vec3(0.299,0.587,0.114));}
vec3 rgb2hsv(vec3 c){
    vec4 k=vec4(0.,-1./3.,2./3.,-1.);
    vec4 p=mix(vec4(c.bg,k.wz),vec4(c.gb,k.xy),step(c.b,c.g));
    vec4 q=mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
    float d=q.x-min(q.w,q.y);
    return vec3(abs(q.z+(q.w-q.y)/(6.*d+1e-10)),d/(q.x+1e-10),q.x);
}
vec3 hsv2rgb(vec3 h){
    float u=h.x*6.;
    float s=h.y;
    float v=h.z;
    float c=v*s;
    float x=c*(1.-abs(mod(u,2.)-1.));
    float m=v-c;
    vec3 r;
    if(u<1.)r=vec3(c,x,0);
    else if(u<2.)r=vec3(x,c,0);
    else if(u<3.)r=vec3(0,c,x);
    else if(u<4.)r=vec3(0,x,c);
    else if(u<5.)r=vec3(x,0,c);
    else r=vec3(c,0,x);
    return r+m;
}
float skin_score(vec3 rgb){
    vec3 h=rgb2hsv(rgb);
    float s=h.y;float v=h.z;float u=h.x;
    float a=smoothstep(0.02,0.18,u)*(1.-smoothstep(0.30,0.5,u));
    float b=smoothstep(0.05,0.7,s);
    float c=smoothstep(0.3,1.0,v);
    return clamp(a*(0.6*b+0.4*c),0.,1.);
}
float character_score(vec3 rgb){
    vec3 h=rgb2hsv(rgb);
    float s=h.y;float v=h.z;
    float a=smoothstep(0.25,0.85,s);
    float b=1.-abs(v-0.5)*2.;
    return clamp(a*b,0.,1.);
}
float edge_strength(vec2 uv){
    float l00=luminance(texture(diffuse_texture,uv+vec2(-1.,-1.)*texel_size).rgb);
    float l10=luminance(texture(diffuse_texture,uv+vec2( 0.,-1.)*texel_size).rgb);
    float l20=luminance(texture(diffuse_texture,uv+vec2( 1.,-1.)*texel_size).rgb);
    float l01=luminance(texture(diffuse_texture,uv+vec2(-1., 0.)*texel_size).rgb);
    float l11=luminance(texture(diffuse_texture,uv).rgb);
    float l21=luminance(texture(diffuse_texture,uv+vec2( 1., 0.)*texel_size).rgb);
    float l02=luminance(texture(diffuse_texture,uv+vec2(-1., 1.)*texel_size).rgb);
    float l12=luminance(texture(diffuse_texture,uv+vec2( 0., 1.)*texel_size).rgb);
    float l22=luminance(texture(diffuse_texture,uv+vec2( 1., 1.)*texel_size).rgb);
    float gx=-l00-2.*l01-l02+l20+2.*l21+l22;
    float gy=-l00-2.*l10-l20+l02+2.*l12+l22;
    return clamp(length(vec2(gx,gy))*2.,0.,1.);
}
bool white_detector(vec3 c){
    float th = 0.025;
    bool c0 = dot(c,vec3(1,1,1))> 0.7;
    bool c3 = (abs(c.r - c.b) < th && abs(c.r - c.g) < th && abs(c.b - c.g) < th);
    return c3 && c0;
}

// Backlight-efficient dark mode with color fidelity preservation
vec3 applyDarkMode(vec3 rgb, vec2 uv) {
    float lum = luminance(rgb);
    float f=max(skin_score(rgb), character_score(rgb));
    f=max(f, smoothstep(0.15,0.5,edge_strength(uv)));

    // Handle white/near-white colors
    if (white_detector(rgb)) {
        vec3 base=rgb*0.4;
        if(lum>0.8){
            vec3 inv=1.-rgb;
            float ia=smoothstep(0.7,0.95,lum);
            ia*=1.-f;
            base=mix(base,inv,ia);
        }
        return base;
    }

    // === BACKLIGHT REDUCTION WITH COLOR FIDELITY ===

    // Strategy: Reduce max(R,G,B) while boosting saturation to maintain color perception
    // This minimizes LED power while keeping colors vibrant

    vec3 hsv = rgb2hsv(rgb);
    float h = hsv.x; // Hue (preserve exactly)
    float s = hsv.y; // Saturation
    float v = hsv.z; // Value (brightness)

    // Power curve on brightness - reduces backlight exponentially
    float exponent = 2.5; // Higher = darker (1.8-3.5 range)
    float newV = pow(v, exponent);

    // Scale to reasonable range
    float minV = 0.03; // Minimum brightness (prevents pure black)
    float maxV = 0.40; // Maximum brightness (reduces backlight significantly)
    newV = mix(minV, maxV, newV);

    // === THE TRICK: Saturation compensation ===
    // When we darken, boost saturation to maintain perceived color richness
    // This keeps colors looking "colorful" even at lower brightness
    float satBoost = 1.0 + (v - newV) * 0.8; // More darkening = more sat boost
    float newS = min(s * satBoost, 1.0);

    // Optional: Slight hue shift towards warmer tones for comfort
    // Uncomment to reduce blue light (better for eyes at night)
    // float hueShift = 0.02; // Subtle warm shift
    // h = mod(h + hueShift, 1.0);

    // Reconstruct color with new HSV values
    vec3 result = hsv2rgb(vec3(h, newS, newV));

    // === PERCEPTUAL CONTRAST ENHANCEMENT ===
    // Boost mid-tone contrast slightly to maintain detail visibility
    float contrast = 1.015;
    result = (result - 0.5) * contrast + 0.5;
    result = clamp(result, 0.0, 1.0);

    return result;
}

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);
    vec3 darkened = applyDarkMode(color_tex.rgb, TexCoords);
    color = vec4(darkened.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
#else // DISABLER1
OUT_IN vec2 TexCoords;
OUT_IN vec4 iterated_color;
#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;
in vec2 vert_uv0;
uniform mat4 projection;
void main() {
    TexCoords = vert_uv0.xy;
    gl_Position = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color = vert_color;
}
#endif // VERTEX_SHADER
#ifdef FRAGMENT_SHADER
out vec4 color;
uniform sampler2D diffuse_texture;
const vec2 texel_size = vec2(1.0/1920.0,1.0/1080.0);
float luminance(vec3 c){return dot(c,vec3(0.100,0.587,0.114));}
vec3 rgb2hsv(vec3 c){
    vec4 k=vec4(0.,-1./3.,2./3.,-1.);
    vec4 p=mix(vec4(c.bg,k.wz),vec4(c.gb,k.xy),step(c.b,c.g));
    vec4 q=mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
    float d=q.x-min(q.w,q.y);
    return vec3(abs(q.z+(q.w-q.y)/(6.*d+1e-10)),d/(q.x+1e-10),q.x);
}
float skin_score(vec3 rgb){
    vec3 h=rgb2hsv(rgb);
    float s=h.y;float v=h.z;float u=h.x;
    float a=smoothstep(0.02,0.18,u)*(1.-smoothstep(0.30,0.5,u));
    float b=smoothstep(0.05,0.7,s);
    float c=smoothstep(0.3,1.0,v);
    return clamp(a*(0.6*b+0.4*c),0.,1.);
}
float character_score(vec3 rgb){
    vec3 h=rgb2hsv(rgb);
    float s=h.y;float v=h.z;
    float a=smoothstep(0.25,0.85,s);
    float b=1.-abs(v-0.5)*2.;
    return clamp(a*b,0.,1.);
}
float edge_strength(vec2 uv){
    float l00=luminance(texture(diffuse_texture,uv+vec2(-1.,-1.)*texel_size).rgb);
    float l10=luminance(texture(diffuse_texture,uv+vec2( 0.,-1.)*texel_size).rgb);
    float l20=luminance(texture(diffuse_texture,uv+vec2( 1.,-1.)*texel_size).rgb);
    float l01=luminance(texture(diffuse_texture,uv+vec2(-1., 0.)*texel_size).rgb);
    float l11=luminance(texture(diffuse_texture,uv).rgb);
    float l21=luminance(texture(diffuse_texture,uv+vec2( 1., 0.)*texel_size).rgb);
    float l02=luminance(texture(diffuse_texture,uv+vec2(-1., 1.)*texel_size).rgb);
    float l12=luminance(texture(diffuse_texture,uv+vec2( 0., 1.)*texel_size).rgb);
    float l22=luminance(texture(diffuse_texture,uv+vec2( 1., 1.)*texel_size).rgb);
    float gx=-l00-2.*l01-l02+l20+2.*l21+l22;
    float gy=-l00-2.*l10-l20+l02+2.*l12+l22;
    return clamp(length(vec2(gx,gy))*2.,0.,1.);
}
bool white_detector(vec3 c){
    float th = 0.015;
    bool c0 = dot(c,vec3(1,1,1))> 0.195;
    bool c3 = (abs(c.r - c.b) < th && abs(c.r - c.g) < th && abs(c.b - c.g) < th);
    return c3 && c0;
}

// Smooth non-linear darkening curve
vec3 applyDarkMode(vec3 rgb, vec2 uv) {
    float lum = luminance(rgb);
    float f=max(skin_score(rgb), character_score(rgb));
    f=max(f, smoothstep(0.15,0.5,edge_strength(uv)));

    // Handle white/near-white colors
    if (white_detector(rgb)) {
        vec3 base=rgb*0.4;
        if(lum>0.8){
            vec3 inv=1.-rgb;
            float ia=smoothstep(0.7,0.95,lum);
            ia*=1.-f;
            base=mix(base,inv,ia);
        }
        return base;
    }

    // Non-linear curve: darker stays dark, brighter gets progressively darker
    // Using power curve for smooth exponential-like behavior

    // Normalize luminance to 0-1 range for curve application
    float normalizedLum = clamp(lum, 0.1, 1.0);

    // Power curve: higher exponent = more aggressive darkening of bright colors
    // Values < 1.0 = brighten darks (lift shadows)
    // Values > 1.0 = darken brights (crush highlights)
    float exponent = 1.5; // Adjust this: 1.5-3.0 range works well

    // Apply power curve to luminance
    float curvedLum = pow(normalizedLum, exponent);

    // Scale the curve to prevent total darkness
    float minOutput = 0.01; // Prevents pure black
    float maxOutput = 0.85; // Controls maximum brightness after darkening
    curvedLum = mix(minOutput, maxOutput, curvedLum);

    // Apply curve while preserving color ratios
    float lumRatio = curvedLum / max(lum, 0.001); // Prevent division by zero
    vec3 result = rgb * lumRatio;

    // Optional: Boost saturation slightly on darkened colors to prevent washout
    vec3 hsv = rgb2hsv(result);
    hsv.y = min(hsv.y * 0.89, 1.0); // Slight saturation boost

    // Convert back (simplified HSV to RGB)
    float h = hsv.x * 6.0;
    float s = hsv.y;
    float v = hsv.z;
    float c = v * s;
    float x = c * (1.0 - abs(mod(h, 2.0) - 1.0));
    float m = v - c;

    vec3 rgbResult;
    if (h < 1.0) rgbResult = vec3(c, x, 0);
    else if (h < 2.0) rgbResult = vec3(x, c, 0);
    else if (h < 3.0) rgbResult = vec3(0, c, x);
    else if (h < 4.0) rgbResult = vec3(0, x, c);
    else if (h < 5.0) rgbResult = vec3(x, 0, c);
    else rgbResult = vec3(c, 0, x);

    return rgbResult + m;
}

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);
    vec3 darkened = applyDarkMode(color_tex.rgb, TexCoords);
    color = vec4(darkened.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
#endif // DISABLER1
// OUT_IN vec2 TexCoords;
// OUT_IN vec4 iterated_color;

// #ifdef VERTEX_SHADER
// in vec4 vert_position;
// in vec4 vert_color;
// in vec2 vert_uv0;

// uniform mat4 projection;

// void main() {
//     TexCoords = vert_uv0.xy;
//     gl_Position = projection * vec4(vert_position.xy, 0.0, 1.0);
//     iterated_color = vert_color;
// }
// #endif // VERTEX_SHADER

// #ifdef FRAGMENT_SHADER
// out vec4 color;

// uniform sampler2D diffuse_texture;
// const vec2 texel_size = vec2(1.0/1920.0,1.0/1080.0);
// float luminance(vec3 c){return dot(c,vec3(0.100,0.587,0.114));}


// vec3 rgb2hsv(vec3 c){
//     vec4 k=vec4(0.,-1./3.,2./3.,-1.);
//     vec4 p=mix(vec4(c.bg,k.wz),vec4(c.gb,k.xy),step(c.b,c.g));
//     vec4 q=mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
//     float d=q.x-min(q.w,q.y);
//     return vec3(abs(q.z+(q.w-q.y)/(6.*d+1e-10)),d/(q.x+1e-10),q.x);
// }
// float skin_score(vec3 rgb){
//     vec3 h=rgb2hsv(rgb);
//     float s=h.y;float v=h.z;float u=h.x;
//     float a=smoothstep(0.02,0.18,u)*(1.-smoothstep(0.30,0.5,u));
//     float b=smoothstep(0.05,0.7,s);
//     float c=smoothstep(0.3,1.0,v);
//     return clamp(a*(0.6*b+0.4*c),0.,1.);
// }
// float character_score(vec3 rgb){
//     vec3 h=rgb2hsv(rgb);
//     float s=h.y;float v=h.z;
//     float a=smoothstep(0.25,0.85,s);
//     float b=1.-abs(v-0.5)*2.;
//     return clamp(a*b,0.,1.);
// }

// float edge_strength(vec2 uv){
//     float l00=luminance(texture(diffuse_texture,uv+vec2(-1.,-1.)*texel_size).rgb);
//     float l10=luminance(texture(diffuse_texture,uv+vec2( 0.,-1.)*texel_size).rgb);
//     float l20=luminance(texture(diffuse_texture,uv+vec2( 1.,-1.)*texel_size).rgb);
//     float l01=luminance(texture(diffuse_texture,uv+vec2(-1., 0.)*texel_size).rgb);
//     float l11=luminance(texture(diffuse_texture,uv).rgb);
//     float l21=luminance(texture(diffuse_texture,uv+vec2( 1., 0.)*texel_size).rgb);
//     float l02=luminance(texture(diffuse_texture,uv+vec2(-1., 1.)*texel_size).rgb);
//     float l12=luminance(texture(diffuse_texture,uv+vec2( 0., 1.)*texel_size).rgb);
//     float l22=luminance(texture(diffuse_texture,uv+vec2( 1., 1.)*texel_size).rgb);
//     float gx=-l00-2.*l01-l02+l20+2.*l21+l22;
//     float gy=-l00-2.*l10-l20+l02+2.*l12+l22;
//     return clamp(length(vec2(gx,gy))*2.,0.,1.);
// }

// bool white_detector(vec3 c){
//     float th = 0.015;
//     // dot(c,vec3(0.100,0.587,0.114))
//     bool c0 = dot(c,vec3(1,1,1))> 0.195;
//     bool c3 = (abs(c.r - c.b) < th && abs(c.r - c.g) < th && abs(c.b - c.g) < th);
//     return c3 && c0;
// }


// // Smooth darkening curve - preserves dark colors, gradually darkens bright ones
// vec3 applyDarkMode(vec3 rgb, vec2 uv) {
//     float lum = luminance(rgb);


//     float f=max(skin_score(rgb), character_score(rgb));
//     f=max(f, smoothstep(0.15,0.5,edge_strength(uv)));

//     if ( white_detector(rgb)) {
//             //The only reason I have this is for white
//        {
//         vec3 base=rgb*0.4;
//         if(lum>0.8){
//             vec3 inv=1.-rgb;
//             float ia=smoothstep(0.7,0.95,lum);
//             ia*=1.-f; // reduce on characters
//             base=mix(base,inv,ia);
//         }
//         return base;
//         }
//         return vec3(0,0,0);  // I wish I could do this, but.. white text...
//     }
//     // Define thresholds
//     float darkThreshold = 0.1;   // Below this, colors stay unchanged
//     float brightThreshold = 1.3; // Above this, maximum darkening applies

//     if (lum < darkThreshold) {
//         // Dark colors: leave untouched
//         return rgb;
//     } else {
//         // Mid-range colors: gentle progressive darkening
//         float midRange = (lum - darkThreshold) / (brightThreshold - darkThreshold);
//         float darkenFactor = .9 - (midRange * 0.4); // Darken up to 40%
//         return rgb * darkenFactor;
//     }
// }

// void main () {
//     vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);
//     vec3 darkened = applyDarkMode(color_tex.rgb, TexCoords);
//     color = vec4(darkened.bgr, color_tex.a);
// }
// #endif // FRAGMENT_SHADER