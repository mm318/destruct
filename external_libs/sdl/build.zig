const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const c_flags = b.option([]const []const u8, "c_flags", "C compiler flags") orelse &.{};

    const lib = b.addStaticLibrary(.{
        .name = "SDL2",
        .target = target,
        .optimize = optimize,
    });

    lib.addIncludePath(b.path("include"));
    lib.addCSourceFiles(.{ .files = &generic_src_files, .flags = @alignCast(c_flags) });
    lib.defineCMacro("SDL_USE_BUILTIN_OPENGL_DEFINITIONS", "1");
    lib.linkLibC();
    switch (target.result.os.tag) {
        .windows => {
            lib.addCSourceFiles(.{ .files = &windows_src_files, .flags = @alignCast(c_flags) });
            lib.linkSystemLibrary("setupapi");
            lib.linkSystemLibrary("winmm");
            lib.linkSystemLibrary("gdi32");
            lib.linkSystemLibrary("imm32");
            lib.linkSystemLibrary("version");
            lib.linkSystemLibrary("oleaut32");
            lib.linkSystemLibrary("ole32");
        },
        .macos => {
            lib.addCSourceFiles(.{ .files = &darwin_src_files, .flags = @alignCast(c_flags) });
            lib.addCSourceFiles(.{
                .files = &objective_c_src_files,
                .flags = &.{"-fobjc-arc"},
            });
            lib.linkFramework("OpenGL");
            lib.linkFramework("Metal");
            lib.linkFramework("CoreVideo");
            lib.linkFramework("Cocoa");
            lib.linkFramework("IOKit");
            lib.linkFramework("ForceFeedback");
            lib.linkFramework("Carbon");
            lib.linkFramework("CoreAudio");
            lib.linkFramework("AudioToolbox");
            lib.linkFramework("AVFoundation");
            lib.linkFramework("Foundation");
        },
        .emscripten => {
            lib.defineCMacro("__EMSCRIPTEN_PTHREADS__", "1");
            lib.defineCMacro("USE_SDL", "2");
            lib.addCSourceFiles(.{ .files = &emscripten_src_files, .flags = @alignCast(c_flags) });

            // NOTE(jae): 2024-04-13
            // Used to do this, but now in our main "build.zig", I automatically add this systemIncludePath for each module
            // when building under Emscripten
            // const emsdk_sysroot = b.sysroot orelse {
            //     @panic("Set \"b.sysroot\" to \"[path to emsdk installation]/upstream/emscripten/cache/sysroot\"'");
            // };
            // const include_path = b.pathJoin(&.{ emsdk_sysroot, "include" });
            // lib.addSystemIncludePath(.{ .path = include_path });
        },
        else => {
            const config_header = b.addConfigHeader(.{
                .style = .{ .cmake = b.path("include/SDL_config.h.cmake") },
                .include_path = "SDL2/SDL_config.h",
            }, .{});
            lib.addConfigHeader(config_header);
            lib.installConfigHeader(config_header);
        },
    }
    // note(jae): 2024-04-13
    // Experimenting with just importing SDL from this dependency
    // lib.installHeadersDirectory("include", "SDL2");
    b.installArtifact(lib);

    var module = b.addModule("sdl", .{
        .root_source_file = b.path("sdl.zig"),
    });
    module.addIncludePath(b.path("include"));
}

const generic_src_files = [_][]const u8{
    "src/SDL.c",
    "src/SDL_assert.c",
    "src/SDL_dataqueue.c",
    "src/SDL_error.c",
    "src/SDL_guid.c",
    "src/SDL_hints.c",
    "src/SDL_list.c",
    "src/SDL_log.c",
    "src/SDL_utils.c",
    "src/atomic/SDL_atomic.c",
    "src/atomic/SDL_spinlock.c",
    "src/audio/SDL_audio.c",
    "src/audio/SDL_audiocvt.c",
    "src/audio/SDL_audiodev.c",
    "src/audio/SDL_audiotypecvt.c",
    "src/audio/SDL_mixer.c",
    "src/audio/SDL_wave.c",
    "src/cpuinfo/SDL_cpuinfo.c",
    "src/dynapi/SDL_dynapi.c",
    "src/events/SDL_clipboardevents.c",
    "src/events/SDL_displayevents.c",
    "src/events/SDL_dropevents.c",
    "src/events/SDL_events.c",
    "src/events/SDL_gesture.c",
    "src/events/SDL_keyboard.c",
    "src/events/SDL_keysym_to_scancode.c",
    "src/events/SDL_mouse.c",
    "src/events/SDL_quit.c",
    "src/events/SDL_scancode_tables.c",
    "src/events/SDL_touch.c",
    "src/events/SDL_windowevents.c",
    "src/events/imKStoUCS.c",
    "src/file/SDL_rwops.c",
    "src/haptic/SDL_haptic.c",
    "src/hidapi/SDL_hidapi.c",

    "src/joystick/SDL_gamecontroller.c",
    "src/joystick/SDL_joystick.c",
    "src/joystick/controller_type.c",
    "src/joystick/virtual/SDL_virtualjoystick.c",

    "src/libm/e_atan2.c",
    "src/libm/e_exp.c",
    "src/libm/e_fmod.c",
    "src/libm/e_log.c",
    "src/libm/e_log10.c",
    "src/libm/e_pow.c",
    "src/libm/e_rem_pio2.c",
    "src/libm/e_sqrt.c",
    "src/libm/k_cos.c",
    "src/libm/k_rem_pio2.c",
    "src/libm/k_sin.c",
    "src/libm/k_tan.c",
    "src/libm/s_atan.c",
    "src/libm/s_copysign.c",
    "src/libm/s_cos.c",
    "src/libm/s_fabs.c",
    "src/libm/s_floor.c",
    "src/libm/s_scalbn.c",
    "src/libm/s_sin.c",
    "src/libm/s_tan.c",
    "src/locale/SDL_locale.c",
    "src/misc/SDL_url.c",
    "src/power/SDL_power.c",
    "src/render/SDL_d3dmath.c",
    "src/render/SDL_render.c",
    "src/render/SDL_yuv_sw.c",
    "src/sensor/SDL_sensor.c",
    "src/stdlib/SDL_crc16.c",
    "src/stdlib/SDL_crc32.c",
    "src/stdlib/SDL_getenv.c",
    "src/stdlib/SDL_iconv.c",
    "src/stdlib/SDL_malloc.c",
    "src/stdlib/SDL_mslibc.c",
    "src/stdlib/SDL_qsort.c",
    "src/stdlib/SDL_stdlib.c",
    "src/stdlib/SDL_string.c",
    "src/stdlib/SDL_strtokr.c",
    "src/thread/SDL_thread.c",
    "src/timer/SDL_timer.c",
    "src/video/SDL_RLEaccel.c",
    "src/video/SDL_blit.c",
    "src/video/SDL_blit_0.c",
    "src/video/SDL_blit_1.c",
    "src/video/SDL_blit_A.c",
    "src/video/SDL_blit_N.c",
    "src/video/SDL_blit_auto.c",
    "src/video/SDL_blit_copy.c",
    "src/video/SDL_blit_slow.c",
    "src/video/SDL_bmp.c",
    "src/video/SDL_clipboard.c",
    "src/video/SDL_egl.c",
    "src/video/SDL_fillrect.c",
    "src/video/SDL_pixels.c",
    "src/video/SDL_rect.c",
    "src/video/SDL_shape.c",
    "src/video/SDL_stretch.c",
    "src/video/SDL_surface.c",
    "src/video/SDL_video.c",
    "src/video/SDL_vulkan_utils.c",
    "src/video/SDL_yuv.c",
    "src/video/yuv2rgb/yuv_rgb.c",

    "src/video/dummy/SDL_nullevents.c",
    "src/video/dummy/SDL_nullframebuffer.c",
    "src/video/dummy/SDL_nullvideo.c",

    "src/render/software/SDL_blendfillrect.c",
    "src/render/software/SDL_blendline.c",
    "src/render/software/SDL_blendpoint.c",
    "src/render/software/SDL_drawline.c",
    "src/render/software/SDL_drawpoint.c",
    "src/render/software/SDL_render_sw.c",
    "src/render/software/SDL_rotate.c",
    "src/render/software/SDL_triangle.c",

    "src/audio/dummy/SDL_dummyaudio.c",

    "src/joystick/hidapi/SDL_hidapi_combined.c",
    "src/joystick/hidapi/SDL_hidapi_gamecube.c",
    "src/joystick/hidapi/SDL_hidapi_luna.c",
    "src/joystick/hidapi/SDL_hidapi_ps3.c",
    "src/joystick/hidapi/SDL_hidapi_ps4.c",
    "src/joystick/hidapi/SDL_hidapi_ps5.c",
    "src/joystick/hidapi/SDL_hidapi_rumble.c",
    "src/joystick/hidapi/SDL_hidapi_shield.c",
    "src/joystick/hidapi/SDL_hidapi_stadia.c",
    "src/joystick/hidapi/SDL_hidapi_steam.c",
    "src/joystick/hidapi/SDL_hidapi_switch.c",
    "src/joystick/hidapi/SDL_hidapi_wii.c",
    "src/joystick/hidapi/SDL_hidapi_xbox360.c",
    "src/joystick/hidapi/SDL_hidapi_xbox360w.c",
    "src/joystick/hidapi/SDL_hidapi_xboxone.c",
    "src/joystick/hidapi/SDL_hidapijoystick.c",
};

const windows_src_files = [_][]const u8{
    "src/core/windows/SDL_hid.c",
    "src/core/windows/SDL_immdevice.c",
    "src/core/windows/SDL_windows.c",
    "src/core/windows/SDL_xinput.c",
    "src/filesystem/windows/SDL_sysfilesystem.c",
    "src/haptic/windows/SDL_dinputhaptic.c",
    "src/haptic/windows/SDL_windowshaptic.c",
    "src/haptic/windows/SDL_xinputhaptic.c",
    "src/hidapi/windows/hid.c",
    "src/joystick/windows/SDL_dinputjoystick.c",
    "src/joystick/windows/SDL_rawinputjoystick.c",
    // This can be enabled when Zig updates to the next mingw-w64 release,
    // which will make the headers gain `windows.gaming.input.h`.
    // Also revert the patch 2c79fd8fd04f1e5045cbe5978943b0aea7593110.
    //"src/joystick/windows/SDL_windows_gaming_input.c",
    "src/joystick/windows/SDL_windowsjoystick.c",
    "src/joystick/windows/SDL_xinputjoystick.c",

    "src/loadso/windows/SDL_sysloadso.c",
    "src/locale/windows/SDL_syslocale.c",
    "src/main/windows/SDL_windows_main.c",
    "src/misc/windows/SDL_sysurl.c",
    "src/power/windows/SDL_syspower.c",
    "src/sensor/windows/SDL_windowssensor.c",
    "src/timer/windows/SDL_systimer.c",
    "src/video/windows/SDL_windowsclipboard.c",
    "src/video/windows/SDL_windowsevents.c",
    "src/video/windows/SDL_windowsframebuffer.c",
    "src/video/windows/SDL_windowskeyboard.c",
    "src/video/windows/SDL_windowsmessagebox.c",
    "src/video/windows/SDL_windowsmodes.c",
    "src/video/windows/SDL_windowsmouse.c",
    "src/video/windows/SDL_windowsopengl.c",
    "src/video/windows/SDL_windowsopengles.c",
    "src/video/windows/SDL_windowsshape.c",
    "src/video/windows/SDL_windowsvideo.c",
    "src/video/windows/SDL_windowsvulkan.c",
    "src/video/windows/SDL_windowswindow.c",

    "src/thread/windows/SDL_syscond_cv.c",
    "src/thread/windows/SDL_sysmutex.c",
    "src/thread/windows/SDL_syssem.c",
    "src/thread/windows/SDL_systhread.c",
    "src/thread/windows/SDL_systls.c",
    "src/thread/generic/SDL_syscond.c",

    "src/render/direct3d/SDL_render_d3d.c",
    "src/render/direct3d/SDL_shaders_d3d.c",
    "src/render/direct3d11/SDL_render_d3d11.c",
    "src/render/direct3d11/SDL_shaders_d3d11.c",
    "src/render/direct3d12/SDL_render_d3d12.c",
    "src/render/direct3d12/SDL_shaders_d3d12.c",

    "src/audio/directsound/SDL_directsound.c",
    "src/audio/wasapi/SDL_wasapi.c",
    "src/audio/wasapi/SDL_wasapi_win32.c",
    "src/audio/winmm/SDL_winmm.c",
    "src/audio/disk/SDL_diskaudio.c",

    "src/render/opengl/SDL_render_gl.c",
    "src/render/opengl/SDL_shaders_gl.c",
    "src/render/opengles/SDL_render_gles.c",
    "src/render/opengles2/SDL_render_gles2.c",
    "src/render/opengles2/SDL_shaders_gles2.c",
};

const linux_src_files = [_][]const u8{
    "src/core/linux/SDL_dbus.c",
    "src/core/linux/SDL_evdev.c",
    "src/core/linux/SDL_evdev_capabilities.c",
    "src/core/linux/SDL_evdev_kbd.c",
    "src/core/linux/SDL_fcitx.c",
    "src/core/linux/SDL_ibus.c",
    "src/core/linux/SDL_ime.c",
    "src/core/linux/SDL_sandbox.c",
    "src/core/linux/SDL_threadprio.c",
    "src/core/linux/SDL_udev.c",
    "src/haptic/linux/SDL_syshaptic.c",
    "src/hidapi/linux/hid.c",
    "src/joystick/linux/SDL_sysjoystick.c",
    "src/power/linux/SDL_syspower.c",

    "src/video/wayland/SDL_waylandclipboard.c",
    "src/video/wayland/SDL_waylanddatamanager.c",
    "src/video/wayland/SDL_waylanddyn.c",
    "src/video/wayland/SDL_waylandevents.c",
    "src/video/wayland/SDL_waylandkeyboard.c",
    "src/video/wayland/SDL_waylandmessagebox.c",
    "src/video/wayland/SDL_waylandmouse.c",
    "src/video/wayland/SDL_waylandopengles.c",
    "src/video/wayland/SDL_waylandtouch.c",
    "src/video/wayland/SDL_waylandvideo.c",
    "src/video/wayland/SDL_waylandvulkan.c",
    "src/video/wayland/SDL_waylandwindow.c",

    "src/video/x11/SDL_x11clipboard.c",
    "src/video/x11/SDL_x11dyn.c",
    "src/video/x11/SDL_x11events.c",
    "src/video/x11/SDL_x11framebuffer.c",
    "src/video/x11/SDL_x11keyboard.c",
    "src/video/x11/SDL_x11messagebox.c",
    "src/video/x11/SDL_x11modes.c",
    "src/video/x11/SDL_x11mouse.c",
    "src/video/x11/SDL_x11opengl.c",
    "src/video/x11/SDL_x11opengles.c",
    "src/video/x11/SDL_x11shape.c",
    "src/video/x11/SDL_x11touch.c",
    "src/video/x11/SDL_x11video.c",
    "src/video/x11/SDL_x11vulkan.c",
    "src/video/x11/SDL_x11window.c",
    "src/video/x11/SDL_x11xfixes.c",
    "src/video/x11/SDL_x11xinput2.c",
    "src/video/x11/edid-parse.c",

    "src/audio/alsa/SDL_alsa_audio.c",
    "src/audio/jack/SDL_jackaudio.c",
    "src/audio/pulseaudio/SDL_pulseaudio.c",
};

const darwin_src_files = [_][]const u8{
    "src/haptic/darwin/SDL_syshaptic.c",
    "src/joystick/darwin/SDL_iokitjoystick.c",
    "src/power/macosx/SDL_syspower.c",
    "src/timer/unix/SDL_systimer.c",
    "src/loadso/dlopen/SDL_sysloadso.c",
    "src/audio/disk/SDL_diskaudio.c",
    "src/render/opengl/SDL_render_gl.c",
    "src/render/opengl/SDL_shaders_gl.c",
    "src/render/opengles/SDL_render_gles.c",
    "src/render/opengles2/SDL_render_gles2.c",
    "src/render/opengles2/SDL_shaders_gles2.c",
    "src/sensor/dummy/SDL_dummysensor.c",

    "src/thread/pthread/SDL_syscond.c",
    "src/thread/pthread/SDL_sysmutex.c",
    "src/thread/pthread/SDL_syssem.c",
    "src/thread/pthread/SDL_systhread.c",
    "src/thread/pthread/SDL_systls.c",
};

const objective_c_src_files = [_][]const u8{
    "src/audio/coreaudio/SDL_coreaudio.m",
    "src/file/cocoa/SDL_rwopsbundlesupport.m",
    "src/filesystem/cocoa/SDL_sysfilesystem.m",
    //"src/hidapi/testgui/mac_support_cocoa.m",
    // This appears to be for SDL3 only.
    //"src/joystick/apple/SDL_mfijoystick.m",
    "src/locale/macosx/SDL_syslocale.m",
    "src/misc/macosx/SDL_sysurl.m",
    "src/power/uikit/SDL_syspower.m",
    "src/render/metal/SDL_render_metal.m",
    "src/sensor/coremotion/SDL_coremotionsensor.m",
    "src/video/cocoa/SDL_cocoaclipboard.m",
    "src/video/cocoa/SDL_cocoaevents.m",
    "src/video/cocoa/SDL_cocoakeyboard.m",
    "src/video/cocoa/SDL_cocoamessagebox.m",
    "src/video/cocoa/SDL_cocoametalview.m",
    "src/video/cocoa/SDL_cocoamodes.m",
    "src/video/cocoa/SDL_cocoamouse.m",
    "src/video/cocoa/SDL_cocoaopengl.m",
    "src/video/cocoa/SDL_cocoaopengles.m",
    "src/video/cocoa/SDL_cocoashape.m",
    "src/video/cocoa/SDL_cocoavideo.m",
    "src/video/cocoa/SDL_cocoavulkan.m",
    "src/video/cocoa/SDL_cocoawindow.m",
    "src/video/uikit/SDL_uikitappdelegate.m",
    "src/video/uikit/SDL_uikitclipboard.m",
    "src/video/uikit/SDL_uikitevents.m",
    "src/video/uikit/SDL_uikitmessagebox.m",
    "src/video/uikit/SDL_uikitmetalview.m",
    "src/video/uikit/SDL_uikitmodes.m",
    "src/video/uikit/SDL_uikitopengles.m",
    "src/video/uikit/SDL_uikitopenglview.m",
    "src/video/uikit/SDL_uikitvideo.m",
    "src/video/uikit/SDL_uikitview.m",
    "src/video/uikit/SDL_uikitviewcontroller.m",
    "src/video/uikit/SDL_uikitvulkan.m",
    "src/video/uikit/SDL_uikitwindow.m",
};

const ios_src_files = [_][]const u8{
    "src/hidapi/ios/hid.m",
    "src/misc/ios/SDL_sysurl.m",
    "src/joystick/iphoneos/SDL_mfijoystick.m",
};

const emscripten_src_files = [_][]const u8{
    "src/audio/emscripten/SDL_emscriptenaudio.c",
    "src/filesystem/emscripten/SDL_sysfilesystem.c",
    "src/joystick/emscripten/SDL_sysjoystick.c",
    "src/locale/emscripten/SDL_syslocale.c",
    "src/misc/emscripten/SDL_sysurl.c",
    "src/power/emscripten/SDL_syspower.c",
    "src/video/emscripten/SDL_emscriptenevents.c",
    "src/video/emscripten/SDL_emscriptenframebuffer.c",
    "src/video/emscripten/SDL_emscriptenmouse.c",
    "src/video/emscripten/SDL_emscriptenopengles.c",
    "src/video/emscripten/SDL_emscriptenvideo.c",

    "src/timer/unix/SDL_systimer.c",
    "src/loadso/dlopen/SDL_sysloadso.c",
    "src/audio/disk/SDL_diskaudio.c",
    "src/render/opengles2/SDL_render_gles2.c",
    "src/render/opengles2/SDL_shaders_gles2.c",
    "src/sensor/dummy/SDL_dummysensor.c",

    "src/thread/pthread/SDL_syscond.c",
    "src/thread/pthread/SDL_sysmutex.c",
    "src/thread/pthread/SDL_syssem.c",
    "src/thread/pthread/SDL_systhread.c",
    "src/thread/pthread/SDL_systls.c",
};
