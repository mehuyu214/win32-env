// d3d9test.c - minimal 32-bit Direct3D9 render test.
// Direct3DCreate9 -> CreateDevice (HAL, fallback REF) -> Clear(magenta) -> Present loop.
// Logs each step + front-buffer center pixel to d3d9test.log (cwd) and stdout.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdarg.h>

static FILE *lf = NULL;
static void logf_(const char *fmt, ...) {
    char buf[1024];
    va_list ap; va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (lf) { fputs(buf, lf); fputc('\n', lf); fflush(lf); }
    fputs(buf, stdout); fputc('\n', stdout); fflush(stdout);
}

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR cmd, int show) {
    lf = fopen("d3d9test.log", "w");
    logf_("=== d3d9test start ===");
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = "D3D9TESTWND";
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    RegisterClassA(&wc);
    HWND hwnd = CreateWindowA("D3D9TESTWND", "D3D9TEST", WS_OVERLAPPEDWINDOW,
        100, 100, 640, 480, NULL, NULL, hInst, NULL);
    if (!hwnd) { logf_("CreateWindow FAILED gle=%lu", GetLastError()); return 1; }
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    logf_("window created");

    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
    logf_("Direct3DCreate9 -> %p", (void*)d3d);
    if (!d3d) { logf_("FAIL: Direct3DCreate9 null"); Sleep(5000); return 2; }

    D3DADAPTER_IDENTIFIER9 ident;
    HRESULT hr = IDirect3D9_GetAdapterIdentifier(d3d, D3DADAPTER_DEFAULT, 0, &ident);
    if (SUCCEEDED(hr)) logf_("adapter: driver=%s desc=%s", ident.Driver, ident.Description);

    D3DCAPS9 caps;
    hr = IDirect3D9_GetDeviceCaps(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, &caps);
    logf_("GetDeviceCaps HAL hr=0x%08lx", (unsigned long)hr);

    D3DPRESENT_PARAMETERS pp = {0};
    pp.Windowed = TRUE;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.BackBufferFormat = D3DFMT_UNKNOWN;
    pp.hDeviceWindow = hwnd;

    IDirect3DDevice9 *dev = NULL;
    hr = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hwnd,
        D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev);
    logf_("CreateDevice HAL hr=0x%08lx dev=%p", (unsigned long)hr, (void*)dev);
    if (FAILED(hr)) {
        hr = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_REF, hwnd,
            D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev);
        logf_("CreateDevice REF hr=0x%08lx dev=%p", (unsigned long)hr, (void*)dev);
    }
    if (FAILED(hr) || !dev) { logf_("FAIL: no device"); Sleep(5000); return 3; }
    logf_("DEVICE OK");

    int frames = 0;
    DWORD t0 = GetTickCount();
    HRESULT firstPresent = 0, firstClear = 0;
    while (GetTickCount() - t0 < 25000) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) goto done;
            TranslateMessage(&msg); DispatchMessageA(&msg);
        }
        hr = IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(255, 0, 255), 1.0f, 0);
        if (frames == 0) firstClear = hr;
        IDirect3DDevice9_BeginScene(dev);
        IDirect3DDevice9_EndScene(dev);
        hr = IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL);
        if (frames == 0) firstPresent = hr;
        frames++;
        if (frames == 5) {
            // read back front buffer center pixel as internal pixel proof
            IDirect3DSurface9 *fb = NULL;
            D3DDISPLAYMODE dm;
            IDirect3DDevice9_GetDisplayMode(dev, 0, &dm);
            hr = IDirect3DDevice9_CreateOffscreenPlainSurface(dev, dm.Width, dm.Height,
                D3DFMT_A8R8G8B8, D3DPOOL_SYSTEMMEM, &fb, NULL);
            if (SUCCEEDED(hr) && fb) {
                hr = IDirect3DDevice9_GetFrontBufferData(dev, 0, fb);
                D3DLOCKED_RECT lr;
                if (SUCCEEDED(hr) && SUCCEEDED(IDirect3DSurface9_LockRect(fb, &lr, NULL, D3DLOCK_READONLY))) {
                    // window at (100,100) size 640x480; sample inside it
                    int sx = 300, sy = 300;
                    DWORD *px = (DWORD*)((char*)lr.pBits + sy * lr.Pitch + sx * 4);
                    logf_("frontbuffer(%d,%d) = 0x%08lx (display %ux%u)", sx, sy,
                        (unsigned long)*px, dm.Width, dm.Height);
                    IDirect3DSurface9_UnlockRect(fb);
                } else logf_("GetFrontBufferData/Lock hr=0x%08lx", (unsigned long)hr);
                IDirect3DSurface9_Release(fb);
            } else logf_("CreateOffscreenPlainSurface hr=0x%08lx", (unsigned long)hr);
        }
        Sleep(16);
    }
done:
    logf_("frames=%d firstClear=0x%08lx firstPresent=0x%08lx DONE", frames,
        (unsigned long)firstClear, (unsigned long)firstPresent);
    if (dev) IDirect3DDevice9_Release(dev);
    if (d3d) IDirect3D9_Release(d3d);
    if (lf) fclose(lf);
    return 0;
}
