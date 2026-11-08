/* Teste mínimo de WebView2: janela + navegador embutido + página animada.
 * Grava as etapas em C:\wv2test.txt e fecha sozinho depois de 20 s. */
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include "WebView2.h"

static FILE *logf;
static HWND hwnd;
static ICoreWebView2Controller *controller;
static ICoreWebView2 *webview;
static ICoreWebView2Environment *genv;   /* modo "popup": 2ª WebView numa janela pop-up */
static HWND popup;
static ICoreWebView2Controller *controller2;
static int popup_mode;

static void logmsg(const char *fmt, HRESULT hr)
{
    fprintf(logf, fmt, (unsigned long)hr);
    fflush(logf);
}

/* objeto COM genérico para os "handlers" (callbacks) do WebView2 */
typedef struct { void *vtbl; LONG ref; } Handler;
static HRESULT STDMETHODCALLTYPE h_qi(void *self, REFIID riid, void **out) { *out = self; return S_OK; }
static ULONG STDMETHODCALLTYPE h_addref(void *self) { return InterlockedIncrement(&((Handler *)self)->ref); }
static ULONG STDMETHODCALLTYPE h_release(void *self) { return InterlockedDecrement(&((Handler *)self)->ref); }

static const WCHAR page[] =
    L"<html><body style='margin:0;height:100vh;display:flex;align-items:center;justify-content:center;"
    L"font-family:-apple-system,Segoe UI,Helvetica;color:white;"
    L"background:linear-gradient(120deg,#2563eb,#9333ea,#db2777);background-size:300% 300%;"
    L"animation:g 3s ease infinite'>"
    L"<style>@keyframes g{0%{background-position:0% 50%}50%{background-position:100% 50%}100%{background-position:0% 50%}}</style>"
    L"<div style='text-align:center'><div style='font-size:64px;font-weight:800'>WebView2 OK</div>"
    L"<div id='ua' style='font-size:20px;margin-top:12px'></div>"
    L"<button id='b' onclick=\"this.textContent='Clicado! '+(++window.n||(window.n=1))\" "
    L"style='font-size:26px;margin-top:24px;padding:10px 28px;border-radius:12px;border:0'>Clique aqui</button></div>"
    L"<script>document.getElementById('ua').textContent=(navigator.userAgent.match(/Edg\\/[0-9.]+/)||['?'])[0]"
    L"+' \\u2014 '+new Date().toLocaleTimeString()</script></body></html>";

/* página carregada? */
static HRESULT STDMETHODCALLTYPE nav_invoke(ICoreWebView2NavigationCompletedEventHandler *self,
                                            ICoreWebView2 *sender, ICoreWebView2NavigationCompletedEventArgs *args)
{
    BOOL ok = FALSE;
    ICoreWebView2NavigationCompletedEventArgs_get_IsSuccess(args, &ok);
    logmsg("NavigationCompleted: success=%lu\n", ok);
    return S_OK;
}
static ICoreWebView2NavigationCompletedEventHandlerVtbl nav_vtbl = { (void *)h_qi, (void *)h_addref, (void *)h_release, nav_invoke };
static Handler nav_handler = { &nav_vtbl, 1 };

static HRESULT STDMETHODCALLTYPE ctrl_invoke(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self,
                                             HRESULT res, ICoreWebView2Controller *ctl)
{
    RECT rc;
    EventRegistrationToken token;

    logmsg("Controller: 0x%08lx\n", res);
    if (FAILED(res) || !ctl) return S_OK;
    controller = ctl;
    ICoreWebView2Controller_AddRef(ctl);
    ICoreWebView2Controller_get_CoreWebView2(ctl, &webview);
    GetClientRect(hwnd, &rc);
    ICoreWebView2Controller_put_Bounds(ctl, rc);
    ICoreWebView2_add_NavigationCompleted(webview, (ICoreWebView2NavigationCompletedEventHandler *)&nav_handler, &token);
    logmsg("NavigateToString: 0x%08lx\n", ICoreWebView2_NavigateToString(webview, page));
    return S_OK;
}
static ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl ctrl_vtbl = { (void *)h_qi, (void *)h_addref, (void *)h_release, ctrl_invoke };
static Handler ctrl_handler = { &ctrl_vtbl, 1 };

static HRESULT STDMETHODCALLTYPE ctrl2_invoke(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self,
                                              HRESULT res, ICoreWebView2Controller *ctl)
{
    RECT rc;
    ICoreWebView2 *wv;
    logmsg("Controller (popup): 0x%08lx\n", res);
    if (FAILED(res) || !ctl) return S_OK;
    controller2 = ctl;
    ICoreWebView2Controller_AddRef(ctl);
    ICoreWebView2Controller_get_CoreWebView2(ctl, &wv);
    GetClientRect(popup, &rc);
    ICoreWebView2Controller_put_Bounds(ctl, rc);
    ICoreWebView2_NavigateToString(wv, L"<body style='margin:0;background:#1b8a3a;color:white;font:32px sans-serif;"
        L"display:flex;align-items:center;justify-content:center;height:100vh'>JANELA POP-UP OK</body>");
    return S_OK;
}
static ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl ctrl2_vtbl = { (void *)h_qi, (void *)h_addref, (void *)h_release, ctrl2_invoke };
static Handler ctrl2_handler = { &ctrl2_vtbl, 1 };

static HRESULT STDMETHODCALLTYPE env_invoke(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self,
                                            HRESULT res, ICoreWebView2Environment *env)
{
    logmsg("Environment: 0x%08lx\n", res);
    if (SUCCEEDED(res) && env) { genv = env; ICoreWebView2Environment_AddRef(env); }
    if (SUCCEEDED(res) && env)
        ICoreWebView2Environment_CreateCoreWebView2Controller(env, hwnd,
            (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *)&ctrl_handler);
    return S_OK;
}
static ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl env_vtbl = { (void *)h_qi, (void *)h_addref, (void *)h_release, env_invoke };
static Handler env_handler = { &env_vtbl, 1 };

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_SIZE && (h == hwnd ? controller : controller2))
    {
        RECT rc; GetClientRect(h, &rc);
        ICoreWebView2Controller_put_Bounds(h == hwnd ? controller : controller2, rc);
    }
    if (m == WM_TIMER && w == 2)
    {
        KillTimer(h, 2);
        popup = CreateWindowExW(0, L"wv2test", L"", WS_POPUP | WS_BORDER | WS_VISIBLE,
                                300, 250, 600, 400, hwnd, NULL, GetModuleHandleW(NULL), NULL);
        logmsg("Popup criado: %p\n", (HRESULT)(ULONG_PTR)popup);
        if (genv) ICoreWebView2Environment_CreateCoreWebView2Controller(genv, popup,
            (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *)&ctrl2_handler);
        return 0;
    }
    if (m == WM_TIMER) { logmsg("Timeout: %lu s\n", 20); DestroyWindow(h); }
    if (m == WM_DESTROY) { if (h == hwnd) PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

typedef HRESULT (STDAPICALLTYPE *create_env_fn)(PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions *,
                                                ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *);

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR cmd, int show)
{
    WNDCLASSW wc = {0};
    HMODULE loader;
    create_env_fn create_env;
    MSG msg;
    WCHAR datadir[MAX_PATH];

    logf = fopen("C:\\wv2test.txt", "w");
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    wc.lpfnWndProc = wndproc; wc.hInstance = inst; wc.lpszClassName = L"wv2test";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassW(&wc);
    hwnd = CreateWindowW(L"wv2test", L"Teste WebView2", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                         100, 100, 900, 600, NULL, NULL, inst, NULL);
    SetTimer(hwnd, 1, 60000, NULL);
    popup_mode = wcsstr(cmd, L"popup") != NULL;
    if (popup_mode) SetTimer(hwnd, 2, 15000, NULL);

    if (!(loader = LoadLibraryW(L"WebView2Loader.dll"))) { logmsg("LoadLibrary WebView2Loader: %lu\n", GetLastError()); return 1; }
    create_env = (create_env_fn)GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions");
    GetTempPathW(MAX_PATH, datadir);
    lstrcatW(datadir, L"wv2test-data");
    logmsg("CreateEnvironment call: 0x%08lx\n", create_env(NULL, datadir, NULL,
        (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *)&env_handler));

    while (GetMessageW(&msg, NULL, 0, 0)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    fclose(logf);
    return 0;
}
