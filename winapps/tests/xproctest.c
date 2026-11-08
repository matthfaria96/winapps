/* Teste de janela-filha de outro processo (o caso do WebView2/Chromium).
 *   xproctest.exe [d3d]        → processo A: cria a janela principal e abre o processo B
 *   xproctest.exe child H [d3d] → processo B: cria uma janela-filha dentro da janela H e
 *                            pinta com GDI (cor muda a cada 0,5 s) ou, com "d3d", com
 *                            Direct3D 11 (fundo que muda de cor a cada quadro); fecha em 60 s. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int tick;

static LRESULT CALLBACK child_proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_TIMER) { tick++; InvalidateRect(h, NULL, FALSE); return 0; }
    if (m == WM_LBUTTONDOWN) { tick += 100; InvalidateRect(h, NULL, FALSE); return 0; }  /* clique: +100 */
    if (m == WM_PAINT)
    {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(h, &ps);
        RECT rc;
        HBRUSH br = CreateSolidBrush(tick % 2 ? RGB(220, 40, 40) : RGB(40, 120, 220));
        char text[64];
        GetClientRect(h, &rc);
        FillRect(dc, &rc, br);
        DeleteObject(br);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(255, 255, 255));
        sprintf(text, "Processo B (pid %lu) quadro %d", GetCurrentProcessId(), tick);
        DrawTextA(dc, text, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        EndPaint(h, &ps);
        return 0;
    }
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

static LRESULT CALLBACK main_proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    WNDCLASSA wc = {0};
    MSG msg;

    if (!strncmp(cmd, "child ", 6))
    {
        HWND parent = (HWND)(ULONG_PTR)strtoull(cmd + 6, NULL, 16), child;
        wc.lpfnWndProc = child_proc; wc.hInstance = inst; wc.lpszClassName = "xchild";
        RegisterClassA(&wc);
        child = CreateWindowA("xchild", "", WS_CHILD | WS_VISIBLE, 40, 40, 500, 300, parent, NULL, inst, NULL);
        if (strstr(cmd, "d3d"))
        {
            DXGI_SWAP_CHAIN_DESC sd = {0};
            ID3D11Device *dev; ID3D11DeviceContext *ctx; IDXGISwapChain *sc; ID3D11Texture2D *bb;
            ID3D11RenderTargetView *rtv; DWORD start = GetTickCount();
            sd.BufferCount = 2; sd.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
            sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.OutputWindow = child;
            sd.SampleDesc.Count = 1; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
            if (FAILED(D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                       D3D11_SDK_VERSION, &sd, &sc, &dev, NULL, &ctx))) return 1;
            IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb);
            ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv);
            while (GetTickCount() - start < 60000)
            {
                float t = (GetTickCount() - start) / 1000.0f;
                float c[4] = { 0.5f + 0.5f * sinf(t * 2), 0.3f, 0.5f + 0.5f * cosf(t * 2), 1 };
                while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&msg);
                ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, c);
                IDXGISwapChain_Present(sc, 1, 0);
            }
            return 0;
        }
        SetTimer(child, 1, 500, NULL);
        SetTimer(NULL, 2, 60000, NULL);
        while (GetMessageA(&msg, NULL, 0, 0))
        {
            if (msg.message == WM_TIMER && !msg.hwnd) break;
            DispatchMessageA(&msg);
        }
        return 0;
    }
    else
    {
        HWND main;
        char exe[MAX_PATH], line[MAX_PATH + 32];
        STARTUPINFOA si = { sizeof(si) };
        PROCESS_INFORMATION pi;

        wc.lpfnWndProc = main_proc; wc.hInstance = inst; wc.lpszClassName = "xmain";
        wc.hbrBackground = (HBRUSH)GetStockObject(LTGRAY_BRUSH);
        RegisterClassA(&wc);
        main = CreateWindowA("xmain", "Teste janela de outro processo", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                             100, 100, 640, 420, NULL, NULL, inst, NULL);
        GetModuleFileNameA(NULL, exe, sizeof(exe));
        sprintf(line, "\"%s\" child %llx%s", exe, (unsigned long long)(ULONG_PTR)main, strstr(cmd, "d3d") ? " d3d" : "");
        CreateProcessA(exe, line, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi);
        SetTimer(NULL, 2, 61000, NULL);
        while (GetMessageA(&msg, NULL, 0, 0))
        {
            if (msg.message == WM_TIMER && !msg.hwnd) break;
            DispatchMessageA(&msg);
        }
        return 0;
    }
}
