/* docktest.exe — o processo pai mostra uma janela e abre uma cópia de si como
   processo filho, que mostra outra janela (como msedgewebview2 sob o Power BI).
   Com o patch 0011 só o pai deve ganhar ícone no Dock. "docktest.exe child" = filho. */
#include <windows.h>
#include <string.h>

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) PostQuitMessage(0);
    return DefWindowProcW(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    BOOL child = strstr(cmd, "child") != NULL;
    WNDCLASSW wc = {0};
    MSG msg;
    wc.lpfnWndProc = proc; wc.hInstance = inst; wc.lpszClassName = L"docktest";
    wc.hbrBackground = (HBRUSH)GetStockObject(child ? GRAY_BRUSH : WHITE_BRUSH);
    RegisterClassW(&wc);
    CreateWindowW(L"docktest", child ? L"docktest: filho" : L"docktest: pai",
                  WS_OVERLAPPEDWINDOW | WS_VISIBLE, child ? 300 : 200, child ? 300 : 200,
                  400, 300, NULL, NULL, inst, NULL);
    if (!child)
    {
        WCHAR path[MAX_PATH], line[MAX_PATH + 16];
        STARTUPINFOW si = {sizeof(si)};
        PROCESS_INFORMATION pi;
        GetModuleFileNameW(NULL, path, MAX_PATH);
        wsprintfW(line, L"\"%s\" child", path);
        Sleep(1500);
        if (CreateProcessW(path, line, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        {
            CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
        }
    }
    while (GetMessageW(&msg, NULL, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    return 0;
}
