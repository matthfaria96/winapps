#include <windows.h>
#include <stdio.h>

static void mark(const char *fmt, ...){
    FILE *f=fopen("C:\\RubinOT\\bin\\x64\\avrt-hook.log","a");
    if(f){ va_list ap; va_start(ap,fmt); vfprintf(f,fmt,ap); va_end(ap); fputc('\n',f); fclose(f);} 
}
#define FORCED_W 2400
#define FORCED_H 1300
static HHOOK g_cbt; static DWORD g_main_tid; static HWND g_game_wnd;

static BOOL (WINAPI *real_MoveWindow)(HWND,int,int,int,int,BOOL);
static BOOL (WINAPI *real_SetWindowPos)(HWND,HWND,int,int,int,int,UINT);
static BOOL (WINAPI *real_SetWindowPlacement)(HWND,const WINDOWPLACEMENT*);

static BOOL (WINAPI *real_GetClientRect)(HWND, LPRECT);
static BOOL WINAPI hook_GetClientRect(HWND h, LPRECT r){
    if(h && h==g_game_wnd && r){ r->left=0; r->top=0; r->right=FORCED_W; r->bottom=FORCED_H; return TRUE; }
    return real_GetClientRect(h,r);
}
static BOOL WINAPI hook_MoveWindow(HWND h,int x,int y,int w,int ht,BOOL rep){
    if(h && h==g_game_wnd){ mark("MoveWindow(%dx%d)->forcado",w,ht); w=FORCED_W; ht=FORCED_H; }
    return real_MoveWindow(h,x,y,w,ht,rep);
}
static BOOL WINAPI hook_SetWindowPos(HWND h,HWND a,int x,int y,int cx,int cy,UINT f){
    if(h && h==g_game_wnd && !(f&SWP_NOSIZE)){ mark("SetWindowPos(%dx%d)->forcado",cx,cy); cx=FORCED_W; cy=FORCED_H; }
    return real_SetWindowPos(h,a,x,y,cx,cy,f);
}
static BOOL WINAPI hook_SetWindowPlacement(HWND h,const WINDOWPLACEMENT *wp){
    if(h && h==g_game_wnd && wp){
        WINDOWPLACEMENT w=*wp;
        mark("SetWindowPlacement(%ld,%ld %ldx%ld)", w.rcNormalPosition.left,w.rcNormalPosition.top,
             w.rcNormalPosition.right-w.rcNormalPosition.left, w.rcNormalPosition.bottom-w.rcNormalPosition.top);
        w.rcNormalPosition.right = w.rcNormalPosition.left + FORCED_W;
        w.rcNormalPosition.bottom = w.rcNormalPosition.top + FORCED_H;
        return real_SetWindowPlacement(h,&w);
    }
    return real_SetWindowPlacement(h,wp);
}

static void *eat_patch(HMODULE mod, const char *func, void *hook){
    BYTE *base=(BYTE*)mod;
    IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)base;
    IMAGE_NT_HEADERS *nt=(IMAGE_NT_HEADERS*)(base+dos->e_lfanew);
    IMAGE_DATA_DIRECTORY *dir=&nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
    IMAGE_EXPORT_DIRECTORY *exp=(IMAGE_EXPORT_DIRECTORY*)(base+dir->VirtualAddress);
    DWORD *names=(DWORD*)(base+exp->AddressOfNames);
    WORD *ords=(WORD*)(base+exp->AddressOfNameOrdinals);
    DWORD *funcs=(DWORD*)(base+exp->AddressOfFunctions);
    for(DWORD i=0;i<exp->NumberOfNames;i++){
        if(strcmp((char*)(base+names[i]),func)) continue;
        DWORD idx=ords[i];
        void *orig=(void*)(base+funcs[idx]);
        ULONGLONG delta=(ULONGLONG)((BYTE*)hook-base);
        DWORD prot;
        VirtualProtect(&funcs[idx],4,PAGE_READWRITE,&prot);
        funcs[idx]=(DWORD)delta;
        VirtualProtect(&funcs[idx],4,prot,&prot);
        mark("EAT %s old=%p delta=%08lx", func, orig, (unsigned long)(DWORD)delta);
        return orig;
    }
    mark("EAT NOT found %s", func);
    return NULL;
}

static DWORD WINAPI hammer(LPVOID p){
    HWND h=(HWND)p;
    for(int i=0;i<1600;i++){ /* ~8s a 5ms */
        real_SetWindowPos(h,NULL,40,40,FORCED_W,FORCED_H,SWP_NOZORDER|SWP_NOACTIVATE|SWP_SHOWWINDOW);
        Sleep(5);
    }
    mark("hammer terminou");
    return 0;
}
static LRESULT CALLBACK cbt_proc(int code, WPARAM wp, LPARAM lp){
    if(code==HCBT_CREATEWND){
        CBT_CREATEWNDA *cc=(CBT_CREATEWNDA*)lp; CREATESTRUCTA *cs=cc?cc->lpcs:NULL;
        char cls[64]={0};
        if(cs&&cs->lpszClass&&(((ULONG_PTR)cs->lpszClass)>>16)) lstrcpynA(cls,cs->lpszClass,63);
        mark("HCBT class=%s %dx%d hwnd=%p", cls, cs?cs->cx:0, cs?cs->cy:0, (void*)wp);
        if(cs&&lstrcmpA(cls,"config")==0){ g_game_wnd=(HWND)wp; cs->cx=FORCED_W; cs->cy=FORCED_H; cs->x=40; cs->y=40; mark("  -> forcado %dx%d",FORCED_W,FORCED_H); }
    }
    return CallNextHookEx(NULL,code,wp,lp);
}

static DWORD WINAPI installer(LPVOID p){
    (void)p; Sleep(120);
    g_cbt=SetWindowsHookExA(WH_CBT,cbt_proc,GetModuleHandleW(L"avrt.dll"),g_main_tid);
    mark("cbt=%p err=%lu", g_cbt, (unsigned long)GetLastError());
    return 0;
}
static void patch_all(void){
    HMODULE u=GetModuleHandleW(L"user32.dll");
    if(!u){ mark("user32 ausente no DllMain"); return; }
    real_GetClientRect=(void*)eat_patch(u,"GetClientRect",(void*)hook_GetClientRect);
    if(!real_GetClientRect) real_GetClientRect=(void*)GetProcAddress(u,"GetClientRect");
    real_MoveWindow=(void*)eat_patch(u,"MoveWindow",(void*)hook_MoveWindow);
    real_SetWindowPos=(void*)eat_patch(u,"SetWindowPos",(void*)hook_SetWindowPos);
    real_SetWindowPlacement=(void*)eat_patch(u,"SetWindowPlacement",(void*)hook_SetWindowPlacement);
    if(!real_MoveWindow) real_MoveWindow=(void*)GetProcAddress(u,"MoveWindow");
    if(!real_SetWindowPos) real_SetWindowPos=(void*)GetProcAddress(u,"SetWindowPos");
    if(!real_SetWindowPlacement) real_SetWindowPlacement=(void*)GetProcAddress(u,"SetWindowPlacement");
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD r, LPVOID x){
    (void)x;
    if(r==DLL_PROCESS_ATTACH){ mark("DLL_PROCESS_ATTACH"); g_main_tid=GetCurrentThreadId(); DisableThreadLibraryCalls(h); CloseHandle(CreateThread(NULL,0,installer,NULL,0,NULL)); }
    return TRUE;
}
HANDLE WINAPI AvSetMmThreadCharacteristicsA(LPCSTR t,LPDWORD i){ (void)t;(void)i; return (HANDLE)1; }
HANDLE WINAPI AvSetMmThreadCharacteristicsW(LPCWSTR t,LPDWORD i){ (void)t;(void)i; return (HANDLE)1; }
BOOL WINAPI AvRevertMmThreadCharacteristic(HANDLE h){ (void)h; return TRUE; }
BOOL WINAPI AvQuerySystemResponsiveness(HANDLE h,PULONG v){ (void)h; if(v)*v=100; return TRUE; }
