/* enumwin.exe close HWND — envia WM_CLOSE.
 * enumwin.exe size HWND X Y W H — reposiciona/redimensiona (com filhas que ocupam a área cliente).
 * enumwin.exe [pid] — lista janelas de topo (e filhas) com retângulos, estilos e estilos estendidos. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static DWORD want;
static void dump(HWND h, int depth)
{
    char cls[64], title[64]; RECT r, c; DWORD pid;
    GetWindowThreadProcessId(h, &pid);
    if (want && pid != want) return;
    GetClassNameA(h, cls, sizeof(cls)); GetWindowTextA(h, title, sizeof(title));
    GetWindowRect(h, &r); GetClientRect(h, &c);
    printf("%*s%p pid=%lu vis=%d [%s] \"%s\" rect=(%ld,%ld)-(%ld,%ld) %ldx%ld client=%ldx%ld style=%08lx ex=%08lx\n",
           depth * 2, "", h, pid, IsWindowVisible(h), cls, title, r.left, r.top, r.right, r.bottom,
           r.right - r.left, r.bottom - r.top, c.right, c.bottom, GetWindowLongA(h, GWL_STYLE), GetWindowLongA(h, GWL_EXSTYLE));
}
static BOOL CALLBACK child(HWND h, LPARAM d)
{
    int depth = 0; HWND p = h;
    while ((p = GetParent(p)) && p != (HWND)d) depth++;
    dump(h, 1 + depth);
    return TRUE;
}
static BOOL CALLBACK top(HWND h, LPARAM l) { dump(h, 0); if (IsWindowVisible(h)) EnumChildWindows(h, child, (LPARAM)h); return TRUE; }
int main(int argc, char **argv)
{
    if (argc > 2 && !strcmp(argv[1], "close")) return !PostMessageA((HWND)(ULONG_PTR)strtoull(argv[2], NULL, 16), WM_CLOSE, 0, 0);
    if (argc > 6 && !strcmp(argv[1], "size"))
    {
        HWND h = (HWND)(ULONG_PTR)strtoull(argv[2], NULL, 16), c;
        int x = atoi(argv[3]), y = atoi(argv[4]), w = atoi(argv[5]), hh = atoi(argv[6]);
        RECT rc;
        SetWindowPos(h, NULL, x, y, w, hh, SWP_NOZORDER | SWP_NOACTIVATE);
        GetClientRect(h, &rc);
        for (c = GetWindow(h, GW_CHILD); c; c = GetWindow(c, GW_HWNDNEXT))
            SetWindowPos(c, NULL, 0, 0, rc.right, rc.bottom, SWP_NOZORDER | SWP_NOACTIVATE);
        return 0;
    }
    want = argc > 1 ? strtoul(argv[1], NULL, 0) : 0;
    EnumWindows(top, 0);
    return 0;
}
