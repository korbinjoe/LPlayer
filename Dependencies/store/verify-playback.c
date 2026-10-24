// Headless integration smoke check. The sandbox UI/rendering needs a separate
// real-window check; this verifies libmpv demux/decode and external sub loading.
#include <mpv/client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    if (argc < 2 || argc > 3) {
        fprintf(stderr, "Usage: verify-playback video [subtitle]\n");
        return 2;
    }
    mpv_handle *m = mpv_create();
    if (!m) return 2;
    const char *options[][2] = {
        {"config", "no"}, {"vo", "null"}, {"ao", "null"},
        {"hwdec", "videotoolbox-copy"}, {"sub-auto", "no"},
        {"idle", "yes"}, {"keep-open", "yes"},
    };
    for (size_t i = 0; i < sizeof(options) / sizeof(options[0]); i++) {
        int r = mpv_set_option_string(m, options[i][0], options[i][1]);
        if (r < 0) { fprintf(stderr, "option %s: %s\n", options[i][0], mpv_error_string(r)); return 2; }
    }
    if (mpv_initialize(m) < 0) return 2;
    const char *load[] = {"loadfile", argv[1], NULL};
    if (mpv_command(m, load) < 0) return 2;
    int loaded = 0, passed = 0;
    for (int i = 0; i < 200; i++) {
        mpv_event *e = mpv_wait_event(m, 0.1);
        if (e->event_id == MPV_EVENT_FILE_LOADED) {
            loaded = 1;
            if (argc == 3) {
                const char *sub[] = {"sub-add", argv[2], "select", NULL};
                if (mpv_command(m, sub) < 0) { fprintf(stderr, "sub-add failed\n"); break; }
            }
        }
        if (e->event_id == MPV_EVENT_END_FILE && ((mpv_event_end_file *)e->data)->error < 0) {
            fprintf(stderr, "decode failed: %s\n", mpv_error_string(((mpv_event_end_file *)e->data)->error)); break;
        }
        double position = 0;
        if (loaded && mpv_get_property(m, "time-pos", MPV_FORMAT_DOUBLE, &position) >= 0 && position >= 0.7) {
            char *hw = mpv_get_property_string(m, "hwdec-current");
            char *codec = mpv_get_property_string(m, "video-codec");
            char *sid = mpv_get_property_string(m, "sid");
            int hw_ok = hw && strstr(hw, "videotoolbox");
            int sub_ok = argc < 3 || (sid && strcmp(sid, "no") != 0);
            printf("%s | codec=%s | hwdec=%s | sid=%s | time=%.3f\n", argv[1], codec ? codec : "", hw ? hw : "", sid ? sid : "", position);
            mpv_free(hw); mpv_free(codec); mpv_free(sid);
            passed = hw_ok && sub_ok;
            break;
        }
    }
    mpv_terminate_destroy(m);
    return passed ? 0 : 1;
}
