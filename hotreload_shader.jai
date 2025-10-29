
fs :: #import "File";
fsu ::#import "File_Utilities";

g_loaded_shader: ShaderData;
ShaderData :: struct{
    program: u32;
    should_hotreload: bool= true;
  	modtime1: Apollo_Time;
  	size1: s64;
  	fullshader_path: string;
    counter_of_shader_reloads: u32;
};

try_compile_shader :: (fullshader_path:string) -> (success:bool, rogram: u32)
{
  shader_raw, success1   := fs.read_entire_file(fullshader_path);
  defer free(shader_raw);

  if !(success1)
  {
    log("ERROR:  Failed to read shader file %",  fullshader_path);
    return false, 0;
  }

  shader_program := Simp.get_shader_program(shader_raw);

  if shader_program == 0 then return false, 0;
  return true, shader_program;
}


maybe_reload_shader :: (shader_path: string)
{

    if !g_loaded_shader.should_hotreload then return;

    modtime1, size1 := fsu.file_modtime_and_size(shader_path);

    should_recompule_shader := g_loaded_shader.modtime1 != modtime1 || g_loaded_shader.size1 != size1;
    if should_recompule_shader
     {
        succeed, new_program := try_compile_shader(shader_path);
        if succeed
        {
          #if SHOULD_LOG log("shader compiled! %",modtime1);
          // glDeleteProgram(g_loaded_shader.program);
          g_loaded_shader.program = new_program;
          g_loaded_shader.modtime1 = modtime1;
          g_loaded_shader.size1 = size1;
            Simp.shader_sprite_left_handed.gl_handle   = new_program;
            Simp.shader_sprite_left_handed.alpha_blend = true;

        }
        else
        {
          #if SHOULD_LOG then log("ERROR: trying to compile sahders");
        }
      }


}


#scope_file
  SHOULD_LOG :: false;
