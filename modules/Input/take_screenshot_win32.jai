#scope_file
using Windows :: #import "Windows";
#import "Basic";
#scope_export

cache_hwnd: Windows.HWND;

screenshot_cache: ScreenshotCache;
ScreenshotCache :: struct {
    hScreenDC: Windows.HDC;
    hMemoryDC: Windows.HDC;
    hBitmap: Windows.HBITMAP;
    hOldBitmap: Windows.HGDIOBJ;
    pBits: *u8;
    width: s32;
    height: s32;
    monitor_left: s32;
    monitor_top: s32;
    initialized: bool;

    should_invert_rgba :bool;

    icon_info: Windows.ICONINFO;

}



max_monitor_iterations := 0;
iterations_so_far := 0;
MonitorEnumData :: struct {
    smallest_monitor: HMONITOR;
    smallest_area: s32 = 0x7FFFFFFF;
    monitor_rect: RECT;
    iterations_so_far:s32;
}




// win32 callback for EnumDisplayMonitors
monitor_enum_cb :: (hMonitor: HMONITOR, hdcMonitor: HDC, lprcMonitor: *RECT, dwData: LPARAM) -> BOOL #c_call {
    using Windows;

    data := cast(*MonitorEnumData) dwData;

    // monitor area (for cursor shenanigans)
    width := lprcMonitor.right - lprcMonitor.left;
    height := lprcMonitor.bottom - lprcMonitor.top;
    area := width * height;

    // if area > data.smallest_area {
    //grab the latest somehow
    if iterations_so_far >= max_monitor_iterations  {
        data.smallest_area = area;
        data.smallest_monitor = hMonitor;
        data.monitor_rect = lprcMonitor.*;
        return BOOL.FALSE;
    }

    iterations_so_far += 1;
    return BOOL.TRUE;
}

find_monitor :: () {
    iterations_so_far=0;
    defer iterations_so_far = 0;
    enum_data: MonitorEnumData;
    EnumDisplayMonitors(null, null, monitor_enum_cb, cast(LPARAM) *enum_data);

    if enum_data.smallest_monitor == null {
        log("No monitors found!", flags=.ERROR);
        return;
    }

    //cache monitor size
    monitor_rect := enum_data.monitor_rect;
    screenshot_cache.width = monitor_rect.right - monitor_rect.left;
    screenshot_cache.height = monitor_rect.bottom - monitor_rect.top;
    screenshot_cache.monitor_left = monitor_rect.left;
    screenshot_cache.monitor_top = monitor_rect.top;

}


platform_get_mouse_pointer_position :: (window: HWND, right_handed: bool) -> (x: int, y: int, success: bool) {
    point: POINT;
    success := GetCursorPos(*point);

    if success {
        ScreenToClient(window, *point);

        // In GetRect_LeftHanded, coordinates are left-handed by default,
        // so if right_handed is true, we need to flip the y-coordinate
        if right_handed {
            client_rect: RECT;
            GetClientRect(window, *client_rect);
            point.y = client_rect.bottom - point.y;
        }

        return point.x, point.y, true;
    }

    return 0, 0, false;
}


init_screenshot :: () {
    using Windows;

    find_monitor();

    log("Initializing screenshot for monitor: %x% at (%,%)",
        screenshot_cache.width, screenshot_cache.height,
        screenshot_cache.monitor_left, screenshot_cache.monitor_top);

    // Create all the DCs and bitmap ONCE
    screenshot_cache.hScreenDC = GetDC(null);
    screenshot_cache.hMemoryDC = CreateCompatibleDC(screenshot_cache.hScreenDC);
    SetWindowDisplayAffinity(cache_hwnd,0x00000011); //to avoid capturing itself!
    // Create DIB
    bmi: BITMAPINFO;
    bmi.bmiHeader.biSize = size_of(type_of(bmi.bmiHeader));
    bmi.bmiHeader.biWidth = screenshot_cache.width;
    bmi.bmiHeader.biHeight = -screenshot_cache.height;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;

    screenshot_cache.hBitmap = CreateDIBSection(
        screenshot_cache.hMemoryDC,
        *bmi,
        DIB_RGB_COLORS,
        *screenshot_cache.pBits,
        null,
        0
    );

    screenshot_cache.hOldBitmap = SelectObject(screenshot_cache.hMemoryDC, screenshot_cache.hBitmap);
    screenshot_cache.initialized = true;
}

cleanup_screenshot :: () {
    using Windows;
    if !screenshot_cache.initialized return;

    SelectObject(screenshot_cache.hMemoryDC, screenshot_cache.hOldBitmap);
    DeleteObject(screenshot_cache.hBitmap);
    DeleteDC(screenshot_cache.hMemoryDC);
    ReleaseDC(null, screenshot_cache.hScreenDC);
    screenshot_cache = .{};
}


take_screenshot_smallest_monitorw :: () {
    using Windows;

    if !screenshot_cache.initialized init_screenshot();

    BitBlt(
        screenshot_cache.hMemoryDC,
        0, 0,
        screenshot_cache.width,
        screenshot_cache.height,
        screenshot_cache.hScreenDC,
        screenshot_cache.monitor_left,
        screenshot_cache.monitor_top,
        .SRCCOPY
    );

    // maybe do this in the shader instead
    if screenshot_cache.should_invert_rgba {
        pixel_count := screenshot_cache.width * screenshot_cache.height;
        pixels := cast(*u32) screenshot_cache.pBits;

        for i: 0..pixel_count-1 {
            pixel := pixels[i];
            b := (pixel >>  0) & 0xFF;
            g := (pixel >>  8) & 0xFF;
            r := (pixel >> 16) & 0xFF;
            a := (pixel >> 24) & 0xFF;

            // swap blue with red
            pixels[i] = (a << 24) | (b << 16) | (g << 8) | r;
        }
    }

}

