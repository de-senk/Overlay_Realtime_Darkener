my_window: Window_Type;
window_width  : s32 = 1920;
window_height : s32 = 1080;

image_test: Simp.Texture;

screenshot_index := 0;

#if OS == .WINDOWS {
    using Windows :: #import "Windows";
    // #import,file "take_screenshot_win32.jai";
}

hotkey_id_start_recording: s32 = 1;
hotkey_id_toggle_window: s32 = 2;
hotkey_id_should_drag: s32 = 4;

MOD_ALT :: 0x0001;
MOD_CONTROL :: 0x0002;
MOD_SHIFT  :: 0x0004;
MOD_WIN :: 0x0008;
#load "hotreload_shader.jai";
main :: () {
    #if OS == .WINDOWS {

        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);

        Input.process_registered_inuts.should_quit_val = 3;
        Input.process_registered_inuts.should_record_val = 2;
        Input.process_registered_inuts.should_edit_shader_val = 1;


        //meh, I consider this project finished for now.
        modifiers :u32= MOD_WIN | MOD_SHIFT;

       if (!RegisterHotKey(null, xx Input.process_registered_inuts.should_quit_val, modifiers, #char "Q")) {
            modifiers = MOD_ALT | MOD_SHIFT;
            if (!RegisterHotKey(null, xx process_registered_inuts.should_quit_val, modifiers, #char "Q")) {
                assert(false, "RegisterHotKey Q failed", "Error", MB_OK);
                return;
            }
        }

        if (!RegisterHotKey(null, xx Input.process_registered_inuts.should_record_val, modifiers, #char "A")) {
            modifiers = MOD_ALT | MOD_SHIFT;
            if (!RegisterHotKey(null, xx Input.process_registered_inuts.should_record_val, modifiers, #char "A")) {
                assert(false, "RegisterHotKey A failed", "Error", MB_OK);
                return;
            }
        }

        if (!RegisterHotKey(null, xx Input.process_registered_inuts.should_edit_shader_val, modifiers, #char "E")) {
            modifiers = MOD_ALT | MOD_SHIFT;
            if (!RegisterHotKey(null, xx Input.process_registered_inuts.should_edit_shader_val, modifiers, #char "E")) {
                assert(false, "RegisterHotKey A failed", "Error", MB_OK);
                return;
            }
        }

        if (!RegisterHotKey(null, hotkey_id_toggle_window, modifiers, #char "G")) {
            modifiers = MOD_ALT | MOD_SHIFT;
            if (!RegisterHotKey(null, hotkey_id_toggle_window, modifiers, #char "G")) {
                assert(false, "RegisterHotKey G failed", "Error", MB_OK);
                return;
            }
        }


    }

    #if OS == .OUNCE {
        base_dir = copy_string(fs.mount_rom());
    } else {
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);
        base_dir = ".";
    }


    WANTED_MSAA :: 8;
    // On Linux, we need to pass the MSAA value to create_window
    my_window = create_window(window_width, window_height, "A Window", wanted_msaa = WANTED_MSAA);
    cache_hwnd = my_window;
    // On other operating systems, the MSAA value needs to be passed to *_create_context, so we
    // need to have an extra step here if you want MSAA.
    msaa := Simp.prepare_window(my_window, wanted_msaa = WANTED_MSAA);
    log("Wanted MSAA: %\nChosen MSAA: %", WANTED_MSAA, msaa);

    // Actual render size in pixels can be different from the window dimensions we specified above (for example on high-resolution displays on macOS/iOS).
    window_width, window_height = Simp.get_render_dimensions(my_window);

    Simp.set_render_target(my_window, .LEFT_HANDED);

    success := Simp.texture_load_from_file(*image_test, tprint("%/image_test.jpg", base_dir));
    assert(success);

    my_init_fonts();
    ui_init();
    Input.process_registered_inuts.should_record = true;
    Input.process_registered_inuts.should_edit_shader = true;
    quit := false;
    want_screenshot := false;
    set_shader_to_custom(SHADER_TEXT_DEFAULT);
    while !quit {

        if current_shader == 0 then maybe_reload_shader("./hotreload_shader.glsl");
        if Input.process_registered_inuts.should_quit then break;
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);  // Simp will do nothing if it doesn't care about this window.

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;
            getrect_handle_event(it);
            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE {
                    quit = true;
                }

                if it.key_pressed && it.key_code == #char "D" {  // Press spacebar to take a screenshot.
                    // want_screenshot = true;
                    screenshot_cache.should_invert_rgba = !screenshot_cache.should_invert_rgba;
                }

                if it.key_pressed && it.key_code == #char "S" {  // Press spacebar to take a screenshot.
                   max_monitor_iterations += 1;
                   if max_monitor_iterations > 2 then max_monitor_iterations = 0;
                   cleanup_screenshot();
                   init_screenshot();
                }
            }
        }

        draw_one_frame();

        if want_screenshot {
            screenshot_index += 1;

            // The Simp API for screenshots makes allowance for screenshots to occur
            // asynchronously. You call pixel_read_begin to start taking the screenshot,
            // and pixel_read_end to finish it and return the resulting bitmap (if it's
            // not ready yet, pixel_read_end will block until it is). If you want to know
            // whether the screenshot is done, you can call pixel_read_is_done().
            // Not all graphics APIs give us a way to do this asynchronously (for example,
            // OpenGL does not seem to), so you aren't guaranteed that this will be smooth,
            // but the API at least *provides a way* for it to be smooth if the backend permits.

            // Because this is a simple example, we just call _end immediately after _begin
            // to show the minimal code required to take a screenshot. To be asynchronous,
            // you would issue the read on one frame, then check whether it's done on each
            // subsequent frame, or else launch a thread to do this.
            async_read := Simp.pixel_read_begin(null, .RGBA8);
            bitmap     := Simp.pixel_read_end(async_read);

            filename := tprint("screenshot%.png\0", screenshot_index);

            #import "stb_image_write";
            stbi_write_png(filename.data, bitmap.width, bitmap.height, 4, bitmap.data.data, xx (bitmap.width * Simp.get_image_bytes_per_texel(bitmap.format)));  // Hardcoded to 4 channels because we know we requested .BGRA8 above.

            want_screenshot = false;

            Simp.deinit(*bitmap);
        }

        sleep_milliseconds(10);
        reset_temporary_storage();
    }
}


set_shader_to_default :: () {
    Simp.shader_sprite_left_handed.gl_handle   = Simp.get_shader_program(Simp.SHADER_SPRITE_LEFT_HANDED);
    Simp.shader_sprite_left_handed.alpha_blend = true;
}

set_shader_to_custom :: (shader_text: string) {
  shader_program := Simp.get_shader_program(shader_text);
  if shader_program == 0 then return;
  Simp.shader_sprite_left_handed.gl_handle   = shader_program;
  Simp.shader_sprite_left_handed.alpha_blend = true;
}

doOneCapture :: () {
    take_screenshot_smallest_monitorw();

    pixel_count := screenshot_cache.width * screenshot_cache.height;
    bitmap: Simp.Bitmap;
    bitmap.width = screenshot_cache.width;
    bitmap.height = screenshot_cache.height;
    bitmap.data.data = screenshot_cache.pBits;
    bitmap.data.count = pixel_count * 4;
    bitmap.format = .RGBA8; // Now it's RGBA after swap

    //I had to force expose this procedure if I remember correctly
    Simp.texture_load_from_bitmap(*image_test, *bitmap);
}

current_time: float64;
last\  _time: float64;
draw_one_frame :: () {


    LWA_ALPHA :: 0x00000002; //seems like it behaves like swap buffers
    LWA_COLOR :: 0x00000001; //seems to work BUT, I need to trigger WM_PAINT
    is_recording := Input.process_registered_inuts.should_record;
    is_editing_shaders := Input.process_registered_inuts.should_edit_shader;
    // SetLayeredWindowAttributes(my_window, 0, 122, LWA_ALPHA); // Fully opaque but layered
    // InvalidateRect(my_window, null, .FALSE);

    // UpdateWindow(my_window);
    // Simp.clear_render_target(0, 0, 0, 0);
    if is_recording doOneCapture();
    // return;
    // ValidateRect(my_window, null);
    // Simp.swap_buff  ers(my_window);
    // SetLayeredWindowAttributes(my_window, 0, 255, LWA_ALPHA); // Fully opaque but layered

    // UpdateWindow(my_window);
    Simp.clear_render_target(.15, .08, .08, 1);
    Simp.set_shader_for_color();
    time := seconds_since_init();
    current_time = seconds_since_init();


    //
    // Draw the screenshot!
    //
    if image_test.width && image_test.height {
        // Draw the texture test, to make sure
        // it comes out right-side-up.

        Simp.set_shader_for_images(*image_test);
        Simp.immediate_begin();

        w := image_test.width/1.1;
        y0 := cast(float) window_height;
        x0 := cast(float) window_width;

        Simp.immediate_quad(.{0, 0}, .{x0, 0}, .{x0, y0}, .{0, y0});
    }



    //this commented out code was for an old strategy. it was terrible.
        // currentExStyle := GetWindowLongPtrA(my_window, GWL_EXSTYLE);
        // is_trasparent := currentExStyle & WS_EX_TRANSPARENT == 1;
        // if is_recording
        // {
        //     // if !is_trasparent SetWindowLongPtrW(my_window, GWL_EXSTYLE, currentExStyle | WS_EX_TRANSPARENT);
        // }
        // if !is_recording
        // {
            //is_trasparent := currentExStyle & WS_EX_TRANSPARENT == 1;
        //     // if !is_trasparent SetWindowLongPtrW(my_window, GWL_EXSTYLE, currentExStyle & ~WS_EX_TRANSPARENT);
        // }

    draw_shader_options();
    draw_cursor();

     // This is our own code to set up a rotating square:
     #if 0
    {
        b := cast(float)window_height / 10;
        p: Vector2;
        p.x = cast(float)(window_width  / 2);
        p.y = cast(float)(window_height / 2);

        theta := cast(float) fmod_cycling(current_time, TAU);

        ct := cos(theta);
        st := sin(theta);

        w := Vector2.{b*ct, b*st};
        h := Vector2.{b*st, -b*ct};

        p0 := p - w - h;
        p1 := p + w - h;
        p2 := p + w + h;
        p3 := p - w + h;

        a :: 1.0;
        c0 := Vector4.{1, 0, 0, a};
        c1 := Vector4.{0, 1, 0, a};
        c2 := Vector4.{0, 0, 1, a};
        c3 := Vector4.{1, 1, 1, a};

        Simp.immediate_quad(p0, p1, p2, p3, c0, c1, c2, c3);
    }
    Simp.immediate_flush();
    Simp.swap_buffers(my_window);
}

my_init_fonts :: () {
    // So that we can load our font, set to path of running executable.
    // @Incomplete: Pack a default font into Simp.

    pixel_height := window_height / 48;

    // @Cleanup: Don't have path + name be separate.
    my_font = Simp.get_font_at_size(base_dir, "OpenSans-BoldItalic.ttf", pixel_height);
    assert(my_font != null);

     pixel_height /= 2;
    button_font = Simp.get_font_at_size(base_dir, "OpenSans-BoldItalic.ttf", pixel_height);
    assert(button_font != null);
}

SHADER_NAMES := string.["DEFAULT Hot Reload","Normal","Shader 1","Shader 2","Shader 3","Shader 4","Shader 5"];
current_shader: s32;
draw_shader_options :: () {
    should_go_transparent := !Input.process_registered_inuts.should_edit_shader;
    {
         currentExStyle := GetWindowLongPtrA(my_window, GWL_EXSTYLE);

        is_transparent := (currentExStyle & WS_EX_TRANSPARENT) != 0;
        if !is_transparent && should_go_transparent
            then SetWindowLongPtrW(my_window, GWL_EXSTYLE, currentExStyle | WS_EX_TRANSPARENT);

        if is_transparent && !should_go_transparent
            then SetWindowLongPtrW(my_window, GWL_EXSTYLE, currentExStyle & ~WS_EX_TRANSPARENT);

    }
    if should_go_transparent then return;
    proc := default_theme_procs[0];
    my_theme := proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!
    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);


    button_theme := my_theme.button_theme;
    button_theme.font = button_font;

        // my_theme := default_overall_theme;
        r := get_rect(0, 22, 150, 20);
        dropdown_theme := *my_theme.dropdown_theme;

        // The 'dropdown' function causes a popup to be created, which
        // gets rendered at the end of the frame when we call draw_popups().
        // The theme and choices array must remain valid until after that time!
        // The 'current_shader' pointer also needs to remain pointing at valid memory
        // until after that time, as that is when it will be changed.
       changed := dropdown(r, SHADER_NAMES, *current_shader, dropdown_theme);
       if changed {
        if current_shader == {
            case 0;
                // set_shader_to_default();
                 // set_shader_to_custom(SHADER_TEXT_DEFAULT);
                 // log("ASDASD");
                 Simp.shader_sprite_left_handed.gl_handle = g_loaded_shader.program;
            case 1; set_shader_to_custom(SHADER_TEXT_NORMAL);
            case 2; set_shader_to_custom(SHADER_TEXT_1);
            case 3; set_shader_to_custom(SHADER_TEXT_2);
            case 4; set_shader_to_custom(SHADER_TEXT_3);
            case 5; set_shader_to_custom(SHADER_TEXT_4);
            case 6; set_shader_to_custom(SHADER_TEXT_5);
        }
       }

    // if q
    {
        // Do a bunch of wacky math to figure out sthe text color.
        theta := cast(float) fmod_cycling(current_time*3, TAU);

        color: Vector4;
        color.x = cos(theta)*.5+.5;
        Clamp(*color.x, 0, 1);
        color.y = 1;
        color.z = sin(theta)*-.5+.5;
        Clamp(*color.z, 0, 1);
        color.w = .5;
        // color *= 5.6;
        // Now, to draw the text:
        MEMORIZE := "MEMORIZE THESE";
        exit_text := "->WIN+SHIFT + Q = exit";
        recr_text := "->WIN+SHIFT+ E = show UI | hide UI and pass through mouse inputs";
        stopcapturing_text := "WIN+SHIFT+ A = capture";

        // We could just call Simp.draw_text to draw text! But we want to know the width
        // so that we can center the text, and to find the width, we have to do all the
        // text layout. So it makes sense just to draw the prepared text after that,
        // so there's a special routine, "draw_prepared_text", that draws the thing
        // you just prepared and got the width of.
        //draw hotkey 1
        text_x, text_y: s64;
        text_x = (r.x + r.w).(s64);
        text_y = r.y.(s64);
        {
            text_y  +=  my_font.character_height;
            text_width := Simp.prepare_text(my_font, MEMORIZE);
            // text_x = (window_width - text_width) / 2;
            // text_y = window_height/2 + my_font.character_height/4;

            Simp.draw_prepared_text(my_font, text_x, text_y, color);
            text_x += text_width+20;
            // text_y  +=  my_font.character_height;
        }
        {
            text_width := Simp.prepare_text(my_font, exit_text);

            // text_x = (window_width - text_width) / 2;
            // text_y = window_height/2 + my_font.character_height/4;

            Simp.draw_prepared_text(my_font, text_x, text_y, color);
        }
        //draw hotkey 2
        {
            text_width := Simp.prepare_text(my_font, recr_text);

            // text_x  = (text_width);
            text_y  +=  my_font.character_height;

            Simp.draw_prepared_text(my_font, text_x, text_y, color);
        }
    }

    draw_popups();  // This draws Subwindows as well.
}


draw_cursor :: () {
    using Windows;
    if !screenshot_cache.initialized return;

    // grab cursor from the OS layer TODO: Do I really care about other OS than windows 11?
    point: POINT;
    success := GetCursorPos(*point);
    if success == 0 return;

    cursor_x := point.x - screenshot_cache.monitor_left;
    cursor_y := point.y - screenshot_cache.monitor_top;

    cursor_outside_capture_area := cursor_x < 0 || cursor_y < 0 || cursor_x >= screenshot_cache.width || cursor_y >= screenshot_cache.height;
    if cursor_outside_capture_area return;

    // because monitor sizes may be different, we need to apply  scaling towards our window
    scale_x := cast(float) window_width / cast(float) screenshot_cache.width;
    scale_y := cast(float) (window_height - 0) / cast(float) screenshot_cache.height; // -0 for your offset
    scaled_cursor_x := cast(float) cursor_x * scale_x;
    scaled_cursor_y := cast(float) cursor_y * scale_y + 0.0; // +20 for your Y offset

    //
    // draw quad, TODO: make a real cursor?
    //
    Simp.set_shader_for_color();
    Simp.immediate_begin();
    cursor_size := 5.0;
    Simp.immediate_quad(
        .{scaled_cursor_x, scaled_cursor_y},
        .{scaled_cursor_x + cursor_size, scaled_cursor_y},
        .{scaled_cursor_x + cursor_size, scaled_cursor_y + cursor_size},
        .{scaled_cursor_x, scaled_cursor_y + cursor_size}
    );

}

glsl_autocomplete_list :: string.[
"radians","degrees","sin","cos","tan","asin","acos","atan","pow","exp","log","exp2","log2","sqrt","inversesqrt","abs","sign","floor","ceil","fract","mod","min","max","clamp","mix","step","smoothstep","length","distance","dot","cross","normalize","faceforward","reflect","refract","matrixCompMult","lessThan","lessThanEqual","greaterThan","greaterThanEqual","equal","notEqual","any","all","not","gl_FragCoord","gl_FrontFacing","gl_PointCoord","gl_FragDepth","gl_Position","gl_PointSize","gl_VertexID","gl_InstanceID","if","else","switch","case","default","for","while","do","break","continue","return","const","in","out","inout","uniform","centroid","flat","smooth","lowp","mediump","highp","precision","struct","layout","discard","void","bool","int","uint","float","double","vec2","vec3","vec4","bvec2","bvec3","bvec4","ivec2","ivec3","ivec4","uvec2","uvec3","uvec4","mat2","mat3","mat4","sampler2D","sampler3D","samplerCube","sampler2DShadow","samplerCubeShadow","sampler2DArray","sampler2DArrayShadow","isampler2D","isampler3D","isamplerCube","isampler2DArray","usampler2D","usampler3D","usamplerCube","usampler2DArray"
];

// @Cleanup: Get rid of the need for begins_with_count?
begins_with_count :: (str: string, prefix: string) -> int {
    for 0..prefix.count-1 {
        // Case-insensitive.
        if it >= str.count return it;

        // @Speed: This is a pretty slow compare.
        ca := Basic.to_lower(str[it]);    // :CompilerBug
        cb := Basic.to_lower(prefix[it]);
/*
        ca := to_lower(str[it]);
        cb := to_lower(prefix[it]);
*/
        if ca != cb return it;
    }

    return prefix.count;
}


using,except(Windows) GETREKT :: #import "GetRect_LeftHanded"; //Im so confused
#import "String";  // For path_strip_filename. @Cleanup.

base_dir: string;

my_font: *Simp.Dynamic_Font;
button_font: *Simp.Dynamic_Font;


Simp  :: #import "Simp";

using Input :: #import "Input";

#import "Window_Creation";

using Basic :: #import "Basic";
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console(); //happyness
    }
}

//
// Yes, I used AI for creating these shaders. And yes I'm ashamed to do so but I dont care for this toy tool. There is not too much to learn here.
//
SHADER_TEXT_DEFAULT :: #string GLSL
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

float luminance(vec3 rgb) {
    return dot(rgb, vec3(0.100, 0.587, 0.114)); //idk man
}

vec3 applyDarkMode(vec3 rgb) {
    float lum = luminance(rgb);

    float darkThreshold = 0.1;   // Below this, colors stay unchanged
    float brightThreshold = 0.9; // Above this, maximum darkening applies

    if (lum < darkThreshold) {
         return rgb;
    }
    else if (lum > brightThreshold) {
        // Bright colors: invert or darken heavily
        float brightness = (lum - brightThreshold) / (1.0 - brightThreshold);

        // Smooth interpolation: the brighter it is, the darker we make it
        float darkenFactor = 1.0 - pow(brightness, 0.5); // Exponential curve

        // For very bright colors (near white), invert them
        if (lum > 0.7) {
            // Smooth inversion with color preservation
            vec3 inverted = vec3(1.0) - rgb;
            float invertAmount = (lum - 0.9) / 0.1; // 0 to 1 as lum goes 0.9 to 1.0
            invertAmount = smoothstep(0.0, 1.0, invertAmount);
            return mix(rgb * darkenFactor, inverted, invertAmount);
        } else {
            // Just darken
            return rgb * darkenFactor;
        }
    } else {
        // Mid-range colors: gentle progressive darkening
        float midRange = (lum - darkThreshold) / (brightThreshold - darkThreshold);
        float darkenFactor = 1.0 - (midRange * 0.4); // Darken up to 40%
        return rgb * darkenFactor;
    }
}

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 applyDarkModeHSV(vec3 rgb) {
    vec3 hsv = rgb2hsv(rgb);
    float value = hsv.z; // Brightness

    // Keep dark colors, darken bright ones
    if (value > 0.7) {
        // Bright: reduce value dramatically
        float newValue = 1.0 - value; // Invert brightness
        hsv.z = newValue;
        // Optionally boost saturation for inverted colors
        hsv.y = min(hsv.y * 1.2, 1.0);
    } else if (value > 0.3) {
        // Mid-tones: gentle darkening
        float darkenAmount = (value - 0.3) / 0.4;
        hsv.z = value * (1.0 - darkenAmount * 0.5);
    }
    // Else: dark colors stay unchanged

    return hsv2rgb(hsv);
}

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);

    if (color_tex.a < 0.1) discard;

    // Apply dark mode transformation
    // Choose one of these approaches:

    // Option 1: RGB-based (faster, good for most content)
    vec3 darkened = applyDarkMode(color_tex.rgb);

    // Option 2: HSV-based (slower but better color preservation)
    // Uncomment to use instead:
    // vec3 darkened = applyDarkModeHSV(color_tex.rgb);

    color = vec4(darkened.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
GLSL


SHADER_TEXT_DEFAULT_BACKYP :: #string GLSL
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

// Convert RGB to perceived brightness (luminance)
float luminance(vec3 rgb) {
    // Perceptual weights for human eye sensitivity
    return dot(rgb, vec3(0.100, 0.587, 0.114));
}

// Smooth darkening curve - preserves dark colors, gradually darkens bright ones
vec3 applyDarkMode(vec3 rgb) {
    float lum = luminance(rgb);

    // Define thresholds
    float darkThreshold = 0.1;   // Below this, colors stay unchanged
    float brightThreshold = 0.9; // Above this, maximum darkening applies

    if (lum < darkThreshold) {
        // Dark colors: leave untouched
        return rgb;
    }
    else if (lum > brightThreshold) {
        // Bright colors: invert or darken heavily
        float brightness = (lum - brightThreshold) / (1.0 - brightThreshold);

        // Smooth interpolation: the brighter it is, the darker we make it
        float darkenFactor = 1.0 - pow(brightness, 0.5); // Exponential curve

        // For very bright colors (near white), invert them
        if (lum > 0.7) {
            // Smooth inversion with color preservation
            vec3 inverted = vec3(1.0) - rgb;
            float invertAmount = (lum - 0.9) / 0.1; // 0 to 1 as lum goes 0.9 to 1.0
            invertAmount = smoothstep(0.0, 1.0, invertAmount);
            return mix(rgb * darkenFactor, inverted, invertAmount);
        } else {
            // Just darken
            return rgb * darkenFactor;
        }
    } else {
        // Mid-range colors: gentle progressive darkening
        float midRange = (lum - darkThreshold) / (brightThreshold - darkThreshold);
        float darkenFactor = 1.0 - (midRange * 0.4); // Darken up to 40%
        return rgb * darkenFactor;
    }
}

// Alternative: HSV-based approach (preserves hue better)
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 applyDarkModeHSV(vec3 rgb) {
    vec3 hsv = rgb2hsv(rgb);
    float value = hsv.z; // Brightness

    // Keep dark colors, darken bright ones
    if (value > 0.7) {
        // Bright: reduce value dramatically
        float newValue = 1.0 - value; // Invert brightness
        hsv.z = newValue;
        // Optionally boost saturation for inverted colors
        hsv.y = min(hsv.y * 1.2, 1.0);
    } else if (value > 0.3) {
        // Mid-tones: gentle darkening
        float darkenAmount = (value - 0.3) / 0.4;
        hsv.z = value * (1.0 - darkenAmount * 0.5);
    }
    // Else: dark colors stay unchanged

    return hsv2rgb(hsv);
}

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);

    if (color_tex.a < 0.1) discard;

    // Apply dark mode transformation
    // Choose one of these approaches:

    // Option 1: RGB-based (faster, good for most content)
    vec3 darkened = applyDarkMode(color_tex.rgb);

    // Option 2: HSV-based (slower but better color preservation)
    // Uncomment to use instead:
    // vec3 darkened = applyDarkModeHSV(color_tex.rgb);

    color = vec4(darkened.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
GLSL


SHADER_TEXT_NORMAL :: #string GLSL
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


void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);

    if (color_tex.a < 0.1) discard;
    color = vec4(color_tex.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
GLSL


SHADER_TEXT_1 :: #string GLSL
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

// Convert RGB to perceived brightness (luminance)
float luminance(vec3 rgb) {
    // Perceptual weights for human eye sensitivity
    return dot(rgb, vec3(0.299, 0.587, 0.114));
}

// Smooth darkening curve - preserves dark colors, gradually darkens bright ones
vec3 applyDarkMode(vec3 rgb) {
    float lum = luminance(rgb);

    // Define thresholds
    float darkThreshold = 0.3;   // Below this, colors stay unchanged
    float brightThreshold = 0.6; // Above this, maximum darkening applies

    if (lum < darkThreshold) {
        // Dark colors: leave untouched
        return rgb;
    } else if (lum > brightThreshold) {
        // Bright colors: invert or darken heavily
        float brightness = (lum - brightThreshold) / (1.0 - brightThreshold);

        // Smooth interpolation: the brighter it is, the darker we make it
        float darkenFactor = 1.0 - pow(brightness, 0.5); // Exponential curve

        // For very bright colors (near white), invert them
        if (lum > 0.7) {
            // Smooth inversion with color preservation
            vec3 inverted = vec3(1.0) - rgb;
            float invertAmount = (lum - 0.9) / 0.1; // 0 to 1 as lum goes 0.9 to 1.0
            invertAmount = smoothstep(0.0, 1.0, invertAmount);
            return mix(rgb * darkenFactor, inverted, invertAmount);
        } else {
            // Just darken
            return rgb * darkenFactor;
        }
    } else {
        // Mid-range colors: gentle progressive darkening
        float midRange = (lum - darkThreshold) / (brightThreshold - darkThreshold);
        float darkenFactor = 1.0 - (midRange * 0.4); // Darken up to 40%
        return rgb * darkenFactor;
    }
}

// Alternative: HSV-based approach (preserves hue better)
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 applyDarkModeHSV(vec3 rgb) {
    vec3 hsv = rgb2hsv(rgb);
    float value = hsv.z; // Brightness

    // Keep dark colors, darken bright ones
    if (value > 0.7) {
        // Bright: reduce value dramatically
        float newValue = 1.0 - value; // Invert brightness
        hsv.z = newValue;
        // Optionally boost saturation for inverted colors
        hsv.y = min(hsv.y * 1.2, 1.0);
    } else if (value > 0.3) {
        // Mid-tones: gentle darkening
        float darkenAmount = (value - 0.3) / 0.4;
        hsv.z = value * (1.0 - darkenAmount * 0.5);
    }
    // Else: dark colors stay unchanged

    return hsv2rgb(hsv);
}

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);

    if (color_tex.a < 0.1) discard;

    // Apply dark mode transformation
    // Choose one of these approaches:

    // Option 1: RGB-based (faster, good for most content)
    vec3 darkened = applyDarkMode(color_tex.rgb);

    // Option 2: HSV-based (slower but better color preservation)
    // Uncomment to use instead:
    // vec3 darkened = applyDarkModeHSV(color_tex.rgb);

    color = vec4(darkened.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
GLSL


SHADER_TEXT_2 :: #string GLSL
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

// Convert RGB to perceived brightness (luminance)
float luminance(vec3 rgb) {
    // Perceptual weights for human eye sensitivity
    return dot(rgb, vec3(0.299, 0.587, 0.114));
}

// Smooth darkening curve - preserves dark colors, gradually darkens bright ones
vec3 applyDarkMode(vec3 rgb) {
    float lum = luminance(rgb);

    // Define thresholds
    float darkThreshold = 0.1;   // Below this, colors stay unchanged
    float brightThreshold = 0.5; // Above this, maximum darkening applies

    if (lum < darkThreshold) {
        // Dark colors: leave untouched
        return rgb;
    } else if (lum > brightThreshold) {
        // Bright colors: invert or darken heavily
        float brightness = (lum - brightThreshold) / (1.0 - brightThreshold);

        // Smooth interpolation: the brighter it is, the darker we make it
        float darkenFactor = 1.0 - pow(brightness, 0.5); // Exponential curve

        // For very bright colors (near white), invert them
        if (lum > 0.9) {
            // Smooth inversion with color preservation
            vec3 inverted = vec3(1.0) - rgb;
            float invertAmount = (lum - 0.9) / 0.1; // 0 to 1 as lum goes 0.9 to 1.0
            invertAmount = smoothstep(0.0, 1.0, invertAmount);
            return mix(rgb * darkenFactor, inverted, invertAmount);
        } else {
            // Just darken
            return rgb * darkenFactor;
        }
    } else {
        // Mid-range colors: gentle progressive darkening
        float midRange = (lum - darkThreshold) / (brightThreshold - darkThreshold);
        float darkenFactor = 1.0 - (midRange * 0.4); // Darken up to 40%
        return rgb * darkenFactor;
    }
}

// Alternative: HSV-based approach (preserves hue better)
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 applyDarkModeHSV(vec3 rgb) {
    vec3 hsv = rgb2hsv(rgb);
    float value = hsv.z; // Brightness

    // Keep dark colors, darken bright ones
    if (value > 0.7) {
        // Bright: reduce value dramatically
        float newValue = 1.0 - value; // Invert brightness
        hsv.z = newValue;
        // Optionally boost saturation for inverted colors
        hsv.y = min(hsv.y * 1.2, 1.0);
    } else if (value > 0.3) {
        // Mid-tones: gentle darkening
        float darkenAmount = (value - 0.3) / 0.4;
        hsv.z = value * (1.0 - darkenAmount * 0.5);
    }
    // Else: dark colors stay unchanged

    return hsv2rgb(hsv);
}

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);

    if (color_tex.a < 0.1) discard;

    // Apply dark mode transformation
    // Choose one of these approaches:

    // Option 1: RGB-based (faster, good for most content)
    // vec3 darkened = applyDarkMode(color_tex.rgb);

    // Option 2: HSV-based (slower but better color preservation)
    // Uncomment to use instead:
    vec3 darkened = applyDarkModeHSV(color_tex.rgb);

    color = vec4(darkened.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
GLSL


SHADER_TEXT_3 :: #string GLSL
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

// Convert RGB to perceived brightness (luminance)
float luminance(vec3 rgb) {
    // Perceptual weights for human eye sensitivity
    return dot(rgb, vec3(0.299, 0.587, 0.114));
}

// Smooth darkening curve - preserves dark colors, gradually darkens bright ones
vec3 applyDarkMode(vec3 rgb) {
    float lum = luminance(rgb);

    // Define thresholds
    float darkThreshold = 0.8;   // Below this, colors stay unchanged
    float brightThreshold = 0.8; // Above this, maximum darkening applies

    if (lum < darkThreshold) {
        // Dark colors: leave untouched
        return rgb;
    } else if (lum > brightThreshold) {
        // Bright colors: invert or darken heavily
        float brightness = (lum - brightThreshold) / (1.0 - brightThreshold);

        // Smooth interpolation: the brighter it is, the darker we make it
        float darkenFactor = 1.0 - pow(brightness, 0.5); // Exponential curve

        // For very bright colors (near white), invert them
        if (lum > 0.9) {
            // Smooth inversion with color preservation
            vec3 inverted = vec3(1.0) - rgb;
            float invertAmount = (lum - 0.9) / 0.1; // 0 to 1 as lum goes 0.9 to 1.0
            invertAmount = smoothstep(0.0, 1.0, invertAmount);
            return mix(rgb * darkenFactor, inverted, invertAmount);
        } else {
            // Just darken
            return rgb * darkenFactor;
        }
    } else {
        // Mid-range colors: gentle progressive darkening
        float midRange = (lum - darkThreshold) / (brightThreshold - darkThreshold);
        float darkenFactor = 1.0 - (midRange * 0.4); // Darken up to 40%
        return rgb * darkenFactor;
    }
}

// Alternative: HSV-based approach (preserves hue better)
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 applyDarkModeHSV(vec3 rgb) {
    vec3 hsv = rgb2hsv(rgb);
    float value = hsv.z; // Brightness

    // Keep dark colors, darken bright ones
    if (value > 0.7) {
        // Bright: reduce value dramatically
        float newValue = 1.0 - value; // Invert brightness
        hsv.z = newValue;
        // Optionally boost saturation for inverted colors
        hsv.y = min(hsv.y * 1.2, 1.0);
    } else if (value > 0.3) {
        // Mid-tones: gentle darkening
        float darkenAmount = (value - 0.3) / 0.4;
        hsv.z = value * (1.0 - darkenAmount * 0.5);
    }
    // Else: dark colors stay unchanged

    return hsv2rgb(hsv);
}

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);

    if (color_tex.a < 0.1) discard;

    // Apply dark mode transformation
    // Choose one of these approaches:

    // Option 1: RGB-based (faster, good for most content)
    vec3 darkened = applyDarkMode(color_tex.rgb);

    // Option 2: HSV-based (slower but better color preservation)
    // Uncomment to use instead:
    // vec3 darkened = applyDarkModeHSV(color_tex.rgb);

    color = vec4(darkened.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
GLSL


SHADER_TEXT_4 :: #string GLSL
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

// Convert RGB to perceived brightness (luminance)
float luminance(vec3 rgb) {
    // Perceptual weights for human eye sensitivity
    return dot(rgb, vec3(0.299, 0.587, 0.114));
}

// Smooth darkening curve - preserves dark colors, gradually darkens bright ones
vec3 applyDarkMode(vec3 rgb) {
    float lum = luminance(rgb);

    // Define thresholds
    float darkThreshold = 0.1;   // Below this, colors stay unchanged
    float brightThreshold = 0.5; // Above this, maximum darkening applies

    if (lum < darkThreshold) {
        // Dark colors: leave untouched
        return rgb;
    } else if (lum > brightThreshold) {
        // Bright colors: invert or darken heavily
        float brightness = (lum - brightThreshold) / (1.0 - brightThreshold);

        // Smooth interpolation: the brighter it is, the darker we make it
        float darkenFactor = 1.0 - pow(brightness, 0.5); // Exponential curve

        // For very bright colors (near white), invert them
        if (lum > 0.9) {
            // Smooth inversion with color preservation
            vec3 inverted = vec3(1.0) - rgb;
            float invertAmount = (lum - 0.9) / 0.1; // 0 to 1 as lum goes 0.9 to 1.0
            invertAmount = smoothstep(0.0, 1.0, invertAmount);
            return mix(rgb * darkenFactor, inverted, invertAmount);
        } else {
            // Just darken
            return rgb * darkenFactor;
        }
    } else {
        // Mid-range colors: gentle progressive darkening
        float midRange = (lum - darkThreshold) / (brightThreshold - darkThreshold);
        float darkenFactor = 1.0 - (midRange * 0.4); // Darken up to 40%
        return rgb * darkenFactor;
    }
}

// Alternative: HSV-based approach (preserves hue better)
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 applyDarkModeHSV(vec3 rgb) {
    vec3 hsv = rgb2hsv(rgb);
    float value = hsv.z; // Brightness

    // Keep dark colors, darken bright ones
    if (value > 0.7) {
        // Bright: reduce value dramatically
        float newValue = 1.0 - value; // Invert brightness
        hsv.z = newValue;
        // Optionally boost saturation for inverted colors
        hsv.y = min(hsv.y * 1.2, 1.0);
    } else if (value > 0.3) {
        // Mid-tones: gentle darkening
        float darkenAmount = (value - 0.3) / 0.4;
        hsv.z = value * (1.0 - darkenAmount * 0.1);
    }
    // Else: dark colors stay unchanged

    return hsv2rgb(hsv);
}

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);

    if (color_tex.a < 0.1) discard;

    // Apply dark mode transformation
    // Choose one of these approaches:

    // Option 1: RGB-based (faster, good for most content)
    // vec3 darkened = applyDarkMode(color_tex.rgb);

    // Option 2: HSV-based (slower but better color preservation)
    // Uncomment to use instead:
    vec3 darkened = applyDarkModeHSV(color_tex.rgb);

    color = vec4(darkened.bgr, color_tex.a);
}
#endif // FRAGMENT_SHADER
GLSL

SHADER_TEXT_5 :: #string GLSL
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
    bool c0 = dot(c,vec3(1,1,1))> 0.5195;
    bool c3 = (abs(c.r - c.b) < th && abs(c.r - c.g) < th && abs(c.b - c.g) < th);
    return c3 && c0;
}

bool brown_detector(vec3 c){
    float th = 0.25;
    bool c0 = dot(c,vec3(0.0,1.0,0.0))> 0.595;
    bool c3 = (abs(c.r - c.b) < th+th && abs(c.r - c.g) < th+th && abs(c.b - c.g) < th);
    return c3 && c0;
}


// Smooth non-linear darkening curve
vec3 applyDarkMode(vec3 rgb, vec2 uv) {
    float lum = luminance(rgb);
    float f=max(skin_score(rgb), character_score(rgb));
    f=max(f, smoothstep(0.15,0.5,edge_strength(uv)));

    // Handle white/near-white colors
    if (white_detector(rgb) || brown_detector(rgb)) {
        vec3 base=rgb*0.4;
        if(lum>0.8){
            vec3 inv=1.-rgb;
            float ia=smoothstep(0.7,0.95,lum);
            ia*=1.-f;
            base=mix(base,inv,ia);
        }
        return vec3(0,0,0);

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
GLSL