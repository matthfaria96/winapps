/* Teste mínimo de Direct3D 11: janela + dispositivo + shaders + triângulo animado.
 * Grava o resultado em C:\d3d11test.txt e fecha sozinho depois de 8 s. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <math.h>

static const char *hlsl =
    "struct V { float4 p : SV_Position; float4 c : COLOR; };\n"
    "cbuffer T : register(b0) { float t; float3 pad; };\n"
    "V vs(uint id : SV_VertexID) {\n"
    "  float2 pos[3] = { float2(0, 0.7), float2(0.7, -0.6), float2(-0.7, -0.6) };\n"
    "  float a = t; float2 p = pos[id];\n"
    "  V o; o.p = float4(p.x*cos(a) - p.y*sin(a), p.x*sin(a) + p.y*cos(a), 0, 1);\n"
    "  o.c = float4(id==0, id==1, id==2, 1); return o; }\n"
    "float4 ps(V i) : SV_Target { return i.c; }\n";

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    FILE *log = fopen("C:\\d3d11test.txt", "w");
    WNDCLASSA wc = {0};
    DXGI_SWAP_CHAIN_DESC sd = {0};
    ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL; IDXGISwapChain *sc = NULL;
    ID3D11Texture2D *bb = NULL; ID3D11RenderTargetView *rtv = NULL;
    ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
    ID3D11VertexShader *vs = NULL; ID3D11PixelShader *ps = NULL; ID3D11Buffer *cb = NULL;
    D3D_FEATURE_LEVEL fl; HRESULT hr; HWND hwnd; MSG msg;
    DWORD start, frames = 0; char name[256] = "?";

    wc.lpfnWndProc = wndproc; wc.hInstance = inst; wc.lpszClassName = "d3dtest";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassA(&wc);
    hwnd = CreateWindowA("d3dtest", "Teste Direct3D 11", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                         100, 100, 800, 600, NULL, NULL, inst, NULL);

    sd.BufferCount = 2; sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    /* "warp" na linha de comando: pede o Direct3D por software da Microsoft (o WebView2 exige) */
    hr = D3D11CreateDeviceAndSwapChain(NULL, strstr(cmd, "warp") ? D3D_DRIVER_TYPE_WARP : D3D_DRIVER_TYPE_HARDWARE,
                                       NULL, 0, NULL, 0,
                                       D3D11_SDK_VERSION, &sd, &sc, &dev, &fl, &ctx);
    fprintf(log, "CreateDevice: 0x%08lx feature_level=0x%x\n", hr, fl);
    if (FAILED(hr)) { fclose(log); return 1; }

    {   /* nome da placa de vídeo vista pelo Direct3D */
        IDXGIDevice *xd; IDXGIAdapter *ad; DXGI_ADAPTER_DESC desc;
        if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&xd)) &&
            SUCCEEDED(IDXGIDevice_GetAdapter(xd, &ad)) && SUCCEEDED(IDXGIAdapter_GetDesc(ad, &desc)))
            WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, name, sizeof(name), NULL, NULL);
        fprintf(log, "Adapter: %s\n", name);
    }

    hr = D3DCompile(hlsl, strlen(hlsl), NULL, NULL, NULL, "vs", "vs_4_0", 0, 0, &vsb, &err);
    fprintf(log, "Compile VS: 0x%08lx\n", hr);
    hr = D3DCompile(hlsl, strlen(hlsl), NULL, NULL, NULL, "ps", "ps_4_0", 0, 0, &psb, &err);
    fprintf(log, "Compile PS: 0x%08lx\n", hr);
    ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), NULL, &vs);
    ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(psb), ID3D10Blob_GetBufferSize(psb), NULL, &ps);
    {
        D3D11_BUFFER_DESC bd = { 16, D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0 };
        ID3D11Device_CreateBuffer(dev, &bd, NULL, &cb);
    }
    IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb);
    ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv);

    start = GetTickCount();
    for (;;)
    {
        float t = (GetTickCount() - start) / 1000.0f, consts[4] = { t, 0, 0, 0 };
        float clear[4] = { 0.1f, 0.12f + 0.1f * sinf(t), 0.25f, 1 };
        D3D11_VIEWPORT vp = { 0, 0, 800, 600, 0, 1 };
        RECT rc; char title[300];

        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT) goto done;
            TranslateMessage(&msg); DispatchMessageA(&msg);
        }
        GetClientRect(hwnd, &rc); vp.Width = (float)rc.right; vp.Height = (float)rc.bottom;
        ID3D11DeviceContext_UpdateSubresource(ctx, (ID3D11Resource *)cb, 0, NULL, consts, 0, 0);
        ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
        ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, clear);
        ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
        ID3D11DeviceContext_VSSetConstantBuffers(ctx, 0, 1, &cb);
        ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
        ID3D11DeviceContext_Draw(ctx, 3, 0);
        IDXGISwapChain_Present(sc, 0, 0);
        frames++;
        if (frames % 60 == 0)
        {
            sprintf(title, "Direct3D 11 - %s - %.0f FPS", name, frames / (t > 0 ? t : 1));
            SetWindowTextA(hwnd, title);
        }
        if (t > 8) break;
    }
done:
    {
        float secs = (GetTickCount() - start) / 1000.0f;
        fprintf(log, "Frames: %lu in %.1fs = %.0f FPS\n", frames, secs, frames / secs);
    }
    fclose(log);
    return 0;
}
