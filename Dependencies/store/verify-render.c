// Render the real libmpv OpenGL API into an offscreen CGL framebuffer.
// Build with -framework OpenGL -lmpv, then pass video subtitle output.ppm.
#define GL_SILENCE_DEPRECATION
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void *get_proc(void *opaque, const char *name) { (void)opaque; return dlsym(RTLD_DEFAULT, name); }

int main(int argc, char **argv)
{
    if (argc != 4) { fprintf(stderr, "Usage: verify-render video subtitle output.ppm\n"); return 2; }
    CGLPixelFormatAttribute attrs[] = { kCGLPFAAccelerated, kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core, 0 };
    CGLPixelFormatObj format = NULL; GLint n = 0; CGLContextObj glctx = NULL;
    if (CGLChoosePixelFormat(attrs, &format, &n) || !format || CGLCreateContext(format, NULL, &glctx) || !glctx) return 2;
    CGLDestroyPixelFormat(format); CGLSetCurrentContext(glctx);
    mpv_handle *m = mpv_create();
    if (!m) return 2;
    const char *options[][2] = {
        {"config", "no"}, {"vo", "libmpv"}, {"audio", "no"},
        {"hwdec", "videotoolbox"}, {"sub-auto", "no"},
        {"idle", "yes"}, {"pause", "yes"}, {"keep-open", "yes"},
    };
    for (size_t i = 0; i < sizeof(options) / sizeof(options[0]); i++) {
        int r = mpv_set_option_string(m, options[i][0], options[i][1]);
        if (r < 0) { fprintf(stderr, "%s: %s\n", options[i][0], mpv_error_string(r)); return 2; }
    }
    if (mpv_initialize(m) < 0) return 2;
    mpv_opengl_init_params init = {get_proc, NULL};
    mpv_render_param params[] = {{MPV_RENDER_PARAM_API_TYPE, MPV_RENDER_API_TYPE_OPENGL}, {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &init}, {0}};
    mpv_render_context *renderer = NULL;
    int r = mpv_render_context_create(&renderer, m, params);
    if (r < 0) { fprintf(stderr, "render context: %s\n", mpv_error_string(r)); return 2; }
    const int w = 640, h = 360;
    GLuint fbo, texture; glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenTextures(1, &texture); glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) return 2;
    const char *load[] = {"loadfile", argv[1], NULL};
    if (mpv_command(m, load) < 0) return 2;
    int loaded = 0, frames = 0, ready = 0, restarted = 0;
    double position = 0;
    mpv_opengl_fbo target = {(int)fbo, w, h, GL_RGBA8};
    int flip = 1;
    mpv_render_param draw[] = {{MPV_RENDER_PARAM_OPENGL_FBO, &target}, {MPV_RENDER_PARAM_FLIP_Y, &flip}, {0}};
    for (int i = 0; i < 400; i++) {
        mpv_event *e = mpv_wait_event(m, 0.02);
        if (e->event_id == MPV_EVENT_FILE_LOADED && !loaded) {
            loaded = 1;
            const char *sub[] = {"sub-add", argv[2], "select", NULL};
            const char *seek[] = {"seek", "0.8", "absolute+exact", NULL};
            if (mpv_command(m, sub) < 0 || mpv_command(m, seek) < 0) break;
        }
        if (loaded && e->event_id == MPV_EVENT_PLAYBACK_RESTART) restarted = 1;
        if (mpv_render_context_update(renderer) & MPV_RENDER_UPDATE_FRAME) {
            mpv_render_context_render(renderer, draw); glFinish(); frames++;
        }
        if (loaded && restarted && frames >= 2 && mpv_get_property(m, "time-pos", MPV_FORMAT_DOUBLE, &position) >= 0 && position >= 0.79) {
            ready = 1;
            // Allow pending subtitle reconfiguration to settle, rendering each
            // delivered update, without advancing the paused video frame.
            for (int j=0; j<20; j++) {
                mpv_wait_event(m, 0);
                if (mpv_render_context_update(renderer) & MPV_RENDER_UPDATE_FRAME) mpv_render_context_render(renderer, draw);
                usleep(20000);
            }
            break;
        }
    }
    unsigned char *pixels = malloc(w*h*3); glBindFramebuffer(GL_FRAMEBUFFER, fbo); glReadPixels(0,0,w,h,GL_RGB,GL_UNSIGNED_BYTE,pixels);
    unsigned lo=255, hi=0; for (int i=0;i<w*h*3;i++) { if(pixels[i]<lo)lo=pixels[i];if(pixels[i]>hi)hi=pixels[i]; }
    FILE *f=fopen(argv[3],"wb");if(!f)return 2;fprintf(f,"P6\n%d %d\n255\n",w,h);
    for(int y=h-1;y>=0;y--) fwrite(pixels+y*w*3,1,w*3,f);
    fclose(f);free(pixels);
    char *hw=mpv_get_property_string(m,"hwdec-current"); char *sid=mpv_get_property_string(m,"sid");
    printf("render ready=%d frames=%d time=%.3f hwdec=%s sid=%s pixel-range=%u..%u\n",ready,frames,position,hw?hw:"",sid?sid:"",lo,hi);
    int passed=ready&&hi-lo>32&&hw&&strstr(hw,"videotoolbox");
    mpv_free(hw);mpv_free(sid);mpv_render_context_free(renderer);mpv_terminate_destroy(m);
    glDeleteTextures(1,&texture);glDeleteFramebuffers(1,&fbo);CGLSetCurrentContext(NULL);CGLDestroyContext(glctx);
    return passed?0:1;
}
