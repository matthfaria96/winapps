/* chrometest.exe — janela com "barra de título própria", como Power BI, Office, Teams e
   apps Chromium/Electron: WM_NCCALCSIZE devolve 0 (a área do programa ocupa a janela toda)
   e WM_NCHITTEST diz onde é barra (HTCAPTION, faixa azul de 40 px no topo) e bordas
   (8 px). Serve para testar redimensionar, arrastar, encaixar e minimizar no Mac.
   "chrometest.exe max" abre maximizada. */
#include <windows.h>
#include <windowsx.h>
#include <string.h>

#define BAR 40
#define EDGE 8

static char last_key[64] = "(nenhuma)";

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m)
    {
    case WM_NCCALCSIZE:
        return 0;   /* sem moldura do sistema: a área do programa é a janela toda */
    case WM_NCHITTEST:
    {
        RECT r; POINT p = { GET_X_LPARAM(l), GET_Y_LPARAM(l) };
        BOOL left, right, top, bottom;
        GetWindowRect(h, &r);
        if (IsZoomed(h)) return p.y - r.top < BAR ? HTCAPTION : HTCLIENT;
        left = p.x < r.left + EDGE; right = p.x >= r.right - EDGE;
        top = p.y < r.top + EDGE; bottom = p.y >= r.bottom - EDGE;
        if (top && left) return HTTOPLEFT;
        if (top && right) return HTTOPRIGHT;
        if (bottom && left) return HTBOTTOMLEFT;
        if (bottom && right) return HTBOTTOMRIGHT;
        if (left) return HTLEFT;
        if (right) return HTRIGHT;
        if (top) return HTTOP;
        if (bottom) return HTBOTTOM;
        return p.y - r.top < BAR ? HTCAPTION : HTCLIENT;
    }
    case WM_PAINT:
    {
        PAINTSTRUCT ps; RECT rc, bar; HDC dc = BeginPaint(h, &ps);
        char text[128];
        GetClientRect(h, &rc);
        FillRect(dc, &rc, (HBRUSH)GetStockObject(WHITE_BRUSH));
        bar = rc; bar.bottom = BAR;
        { HBRUSH b = CreateSolidBrush(RGB(40, 90, 200)); FillRect(dc, &bar, b); DeleteObject(b); }
        SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(255, 255, 255));
        TextOutA(dc, 12, 12, "chrometest - barra propria", 26);
        SetTextColor(dc, RGB(0, 0, 0));
        wsprintfA(text, "%d x %d %s", rc.right, rc.bottom, IsZoomed(h) ? "(maximizada)" : "");
        TextOutA(dc, 12, BAR + 20, text, lstrlenA(text));
        wsprintfA(text, "ultima tecla: %s", last_key);
        TextOutA(dc, 12, BAR + 44, text, lstrlenA(text));
        EndPaint(h, &ps);
        return 0;
    }
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
        if (w != VK_CONTROL && w != VK_SHIFT && w != VK_MENU)
        {
            wsprintfA(last_key, "%s%s%s0x%02X",
                      GetKeyState(VK_CONTROL) < 0 ? "Ctrl+" : "", GetKeyState(VK_SHIFT) < 0 ? "Shift+" : "",
                      GetKeyState(VK_MENU) < 0 ? "Alt+" : "", (unsigned)w);
            InvalidateRect(h, NULL, TRUE);
        }
        break;
    case WM_SIZE:
        InvalidateRect(h, NULL, TRUE);
        break;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    WNDCLASSW wc = {0};
    MSG msg;
    HWND h;
    wc.lpfnWndProc = proc; wc.hInstance = inst; wc.lpszClassName = L"chrometest";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassW(&wc);
    h = CreateWindowW(L"chrometest", L"chrometest", WS_OVERLAPPEDWINDOW,
                      200, 200, 640, 420, NULL, NULL, inst, NULL);
    /* como Chromium/Power BI: aplica já a "moldura" própria (WM_NCCALCSIZE) */
    SetWindowPos(h, NULL, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER);
    ShowWindow(h, strstr(cmd, "max") ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
    while (GetMessageW(&msg, NULL, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    return 0;
}
