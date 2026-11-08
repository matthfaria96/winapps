/*
 * win-size-hook.c — tamanho e redimensionamento da janela do RubinOT.
 *
 * O cliente (rubinot_dx.exe, empacotado com VMProtect) fixa o tamanho do render
 * no startup: ele calcula a janela com AdjustWindowRectEx e usa esse tamanho
 * para o render/UI. Redimensionar depois não re-cria o buffer (o jogo ficava
 * no canto e o resto da janela vazio).
 *
 * Este DLL se chama avrt.dll e é carregado do próprio diretório do jogo
 * (o cliente importa avrt.dll do Windows; o Wine procura primeiro no diretório
 * do executável). Ele intercepta a IAT do exe (antes do packer rodar) e:
 *   - força as primeiras chamadas grandes de AdjustWindowRectEx para o tamanho
 *     desejado (FORCED_W x FORCED_H): o cliente abre a janela nesse tamanho;
 *   - ESCALA: o primeiro tamanho de área cliente que o jogo lê vira o tamanho
 *     "virtual" fixo. Daí em diante o jogo e o ANGLE (libGLESv2.dll) sempre veem
 *     esse tamanho (GetClientRect, WM_SIZE), então o buffer não muda e o
 *     DXGI/DXMT estica a imagem até a janela real. O mouse é convertido da
 *     janela real para o tamanho virtual; o redimensionamento mantém a
 *     proporção (WM_SIZING) e permite encolher (WM_GETMINMAXINFO). Pedidos de
 *     tamanho do próprio jogo (SetWindowPos/MoveWindow) são ignorados depois
 *     disso — quem decide o tamanho é o usuário;
 *   - exporta as 4 funções avrt que o cliente importa (senão ele não carrega).
 *
 * Para mudar o tamanho inicial: ajuste FORCED_W/FORCED_H e recompile com build-hook.sh.
 */
#include <windows.h>
#include <windowsx.h>
#include <stdio.h>
static void mark(const char *fmt, ...){
    FILE *f=fopen("C:\\RubinOT\\bin\\x64\\avrt-hook.log","a");
    if(f){ va_list ap; va_start(ap,fmt); vfprintf(f,fmt,ap); va_end(ap); fputc('\n',f); fclose(f);}
}
static HHOOK g_cbt; static DWORD g_main_tid; static HWND g_game_wnd;

static BOOL (WINAPI *r_GetClientRect)(HWND,LPRECT);
static BOOL (WINAPI *r_GetWindowRect)(HWND,LPRECT);
static BOOL (WINAPI *r_AdjustWindowRectEx)(LPRECT,DWORD,BOOL,DWORD);
static BOOL (WINAPI *r_ShowWindow)(HWND,int);
static BOOL (WINAPI *r_SetWindowPlacement)(HWND,const WINDOWPLACEMENT*);
static BOOL (WINAPI *r_SetWindowPos)(HWND,HWND,int,int,int,int,UINT);
static BOOL (WINAPI *r_MoveWindow)(HWND,int,int,int,int,BOOL);
static LONG_PTR (WINAPI *r_SetWindowLongPtrA)(HWND,int,LONG_PTR);
static LONG_PTR (WINAPI *r_GetWindowLongPtrA)(HWND,int);
static BOOL (WINAPI *r_angle_GetClientRect)(HWND,LPRECT);

/* ---- escala ---- */
static LONG g_vw, g_vh;          /* tamanho virtual da área cliente (0 = ainda não fixado) */
static WNDPROC g_orig_proc;      /* wndproc do jogo */
static BOOL g_unicode;
static BOOL g_angle_patched;

static BOOL is_game(HWND h){ return h && g_game_wnd && (h==g_game_wnd || IsChild(g_game_wnd,h)); }

static LPARAM scale_point(HWND h,LPARAM lp){
    RECT rc; if(!g_vw || !r_GetClientRect(h,&rc)) return lp;
    LONG cw=rc.right-rc.left, ch=rc.bottom-rc.top;
    if(cw<=0 || ch<=0 || (cw==g_vw && ch==g_vh)) return lp;
    int x=GET_X_LPARAM(lp), y=GET_Y_LPARAM(lp);
    x=MulDiv(x,g_vw,cw); y=MulDiv(y,g_vh,ch);
    return MAKELPARAM((SHORT)x,(SHORT)y);
}
/* bordas da janela (diferença entre retângulo da janela e área cliente) */
static void frame_extra(HWND h,LONG *ex,LONG *ey){
    RECT w,c; *ex=*ey=0;
    if(r_GetWindowRect(h,&w) && r_GetClientRect(h,&c)){ *ex=(w.right-w.left)-c.right; *ey=(w.bottom-w.top)-c.bottom; }
}
static void keep_aspect(HWND h,WPARAM edge,RECT *r){
    LONG ex,ey; frame_extra(h,&ex,&ey);
    LONG cw=(r->right-r->left)-ex, ch=(r->bottom-r->top)-ey;
    if(cw<1) cw=1;
    if(ch<1) ch=1;
    /* o winemac sempre manda um canto: a dimensão que mais mudou manda */
    BOOL by_height = (edge==WMSZ_TOP || edge==WMSZ_BOTTOM);
    RECT cur;
    if(!by_height && edge!=WMSZ_LEFT && edge!=WMSZ_RIGHT && r_GetWindowRect(h,&cur)){
        LONG dw=labs(cw-((cur.right-cur.left)-ex)), dh=labs(ch-((cur.bottom-cur.top)-ey));
        by_height = (LONGLONG)dh*g_vw > (LONGLONG)dw*g_vh;
    }
    if(by_height){
        cw=MulDiv(ch,g_vw,g_vh);
        if(edge==WMSZ_LEFT || edge==WMSZ_TOPLEFT || edge==WMSZ_BOTTOMLEFT) r->left=r->right-cw-ex;
        else r->right=r->left+cw+ex;
    }else{
        ch=MulDiv(cw,g_vh,g_vw);
        if(edge==WMSZ_TOP || edge==WMSZ_TOPLEFT || edge==WMSZ_TOPRIGHT) r->top=r->bottom-ch-ey;
        else r->bottom=r->top+ch+ey;
    }
}
static LRESULT call_orig(HWND h,UINT m,WPARAM wp,LPARAM lp){
    return g_unicode ? CallWindowProcW(g_orig_proc,h,m,wp,lp) : CallWindowProcA(g_orig_proc,h,m,wp,lp);
}
/* fechar a janela (X / Cmd+Q) fecha o jogo: ele recebe o pedido normalmente e,
   se não tiver saído em 2 s (ele ignora o X), o processo é encerrado */
static DWORD WINAPI close_watchdog(LPVOID p){
    (void)p; Sleep(2000);
    mark("fechar: jogo nao saiu sozinho, encerrando");
    TerminateProcess(GetCurrentProcess(),0);
    return 0;
}
static void request_close(const char *why){
    static LONG once;
    if(InterlockedExchange(&once,1)) return;
    mark("fechar: %s", why);
    CloseHandle(CreateThread(NULL,0,close_watchdog,NULL,0,NULL));
}
static LRESULT CALLBACK scale_proc(HWND h,UINT m,WPARAM wp,LPARAM lp){
    switch(m){
    case WM_CLOSE: request_close("WM_CLOSE"); break;
    case WM_SYSCOMMAND: if((wp & 0xFFF0)==SC_CLOSE) request_close("SC_CLOSE"); break;
    case WM_MOUSEMOVE: case WM_MOUSEHOVER:
    case WM_LBUTTONDOWN: case WM_LBUTTONUP: case WM_LBUTTONDBLCLK:
    case WM_RBUTTONDOWN: case WM_RBUTTONUP: case WM_RBUTTONDBLCLK:
    case WM_MBUTTONDOWN: case WM_MBUTTONUP: case WM_MBUTTONDBLCLK:
    case WM_XBUTTONDOWN: case WM_XBUTTONUP: case WM_XBUTTONDBLCLK:
        lp=scale_point(h,lp); break;
    case WM_SIZE:
        if(g_vw && wp!=SIZE_MINIMIZED) lp=MAKELPARAM(g_vw,g_vh);
        break;
    case WM_SIZING:
        if(g_vw && lp){ LRESULT res=call_orig(h,m,wp,lp); keep_aspect(h,wp,(RECT*)lp); (void)res; return TRUE; }
        break;
    case WM_GETMINMAXINFO:
        if(g_vw && lp){
            LRESULT res=call_orig(h,m,wp,lp);
            MINMAXINFO *mm=(MINMAXINFO*)lp; LONG ex,ey; frame_extra(h,&ex,&ey);
            mm->ptMinTrackSize.x=g_vw/5+ex; mm->ptMinTrackSize.y=g_vh/5+ey;
            return res;
        }
        break;
    }
    return call_orig(h,m,wp,lp);
}

static void *iat_patch(HMODULE exe,const char *dll,const char *func,void *hook){
    if(!exe) return NULL;
    BYTE *base=(BYTE*)exe; IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)base;
    IMAGE_NT_HEADERS *nt=(IMAGE_NT_HEADERS*)(base+dos->e_lfanew);
    IMAGE_DATA_DIRECTORY *dir=&nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if(!dir->VirtualAddress) return NULL;
    IMAGE_IMPORT_DESCRIPTOR *d=(IMAGE_IMPORT_DESCRIPTOR*)(base+dir->VirtualAddress);
    for(; d->Name; d++){
        if(_stricmp((char*)(base+d->Name),dll)) continue;
        IMAGE_THUNK_DATA *orig=(IMAGE_THUNK_DATA*)(base+(d->OriginalFirstThunk?d->OriginalFirstThunk:d->FirstThunk));
        IMAGE_THUNK_DATA *iat=(IMAGE_THUNK_DATA*)(base+d->FirstThunk);
        for(; orig->u1.AddressOfData; orig++, iat++){
            if(orig->u1.Ordinal & IMAGE_ORDINAL_FLAG) continue;
            IMAGE_IMPORT_BY_NAME *ibn=(IMAGE_IMPORT_BY_NAME*)(base+orig->u1.AddressOfData);
            if(strcmp((char*)ibn->Name,func)) continue;
            void *old=(void*)iat->u1.Function; DWORD prot;
            VirtualProtect(&iat->u1.Function,sizeof(void*),PAGE_READWRITE,&prot);
            iat->u1.Function=(ULONG_PTR)hook;
            VirtualProtect(&iat->u1.Function,sizeof(void*),prot,&prot);
            return old;
        }
    }
    return NULL;
}

/* ANGLE (libGLESv2.dll) mede a janela para dimensionar o swapchain: ver o tamanho virtual */
static BOOL WINAPI h_angle_GetClientRect(HWND h,LPRECT r){
    BOOL ok=r_angle_GetClientRect(h,r);
    if(ok && r && g_vw && is_game(h)){ r->left=r->top=0; r->right=g_vw; r->bottom=g_vh; }
    return ok;
}
static void patch_angle(void){
    if(g_angle_patched) return;
    HMODULE gl=GetModuleHandleW(L"libGLESv2.dll");
    if(!gl) return;
    g_angle_patched=TRUE;
    r_angle_GetClientRect=(void*)iat_patch(gl,"USER32.dll","GetClientRect",(void*)h_angle_GetClientRect);
    if(!r_angle_GetClientRect) r_angle_GetClientRect=r_GetClientRect;
    mark("ANGLE GetClientRect %s", r_angle_GetClientRect!=r_GetClientRect?"interceptado":"NAO encontrado");
}
static void freeze_virtual(HWND h,LONG w,LONG hgt){
    g_vw=w; g_vh=hgt;
    g_unicode=IsWindowUnicode(h);
    g_orig_proc=(WNDPROC)(g_unicode ? SetWindowLongPtrW(h,GWLP_WNDPROC,(LONG_PTR)scale_proc)
                                    : r_SetWindowLongPtrA(h,GWLP_WNDPROC,(LONG_PTR)scale_proc));
    mark("escala: tamanho virtual %ldx%ld (wndproc %s)", w, hgt, g_unicode?"W":"A");
    patch_angle();
}

static BOOL WINAPI h_GetClientRect(HWND h,LPRECT r){
    BOOL ok=r_GetClientRect(h,r);
    if(ok && r && h==g_game_wnd){
        if(!g_vw && r->right>=550 && r->bottom>=450) freeze_virtual(h,r->right,r->bottom);
        if(g_vw){ patch_angle(); r->left=r->top=0; r->right=g_vw; r->bottom=g_vh; }
    }
    return ok;
}
static BOOL WINAPI h_GetWindowRect(HWND h,LPRECT r){ return r_GetWindowRect(h,r); }
#define FORCED_W 2400
#define FORCED_H 1300
static int g_forced;
static BOOL WINAPI h_AdjustWindowRectEx(LPRECT r,DWORD st,BOOL menu,DWORD ex){
    if(r && g_forced<6){
        LONG w=r->right-r->left, h=r->bottom-r->top;
        if(w>=550 && h>=450 && w<=1600 && h<=1000 && !(st & WS_POPUP)){
            g_forced++;
            mark("AdjustWindowRectEx %ldx%ld -> %dx%d (#%d)", w, h, FORCED_W, FORCED_H, g_forced);
            r->left=0; r->top=0; r->right=FORCED_W; r->bottom=FORCED_H;
        }
    }
    return r_AdjustWindowRectEx(r,st,menu,ex);
}
static BOOL WINAPI h_ShowWindow(HWND h,int cmd){ if(h==g_game_wnd) mark("ShowWindow cmd=%d", cmd); return r_ShowWindow(h,cmd); }
static BOOL WINAPI h_SetWindowPlacement(HWND h,const WINDOWPLACEMENT *wp){ if(h==g_game_wnd && wp) mark("SetWindowPlacement %ldx%ld", wp->rcNormalPosition.right-wp->rcNormalPosition.left, wp->rcNormalPosition.bottom-wp->rcNormalPosition.top); return r_SetWindowPlacement(h,wp); }
/* depois de fixar o tamanho virtual, o jogo não muda mais o tamanho da janela */
static BOOL WINAPI h_SetWindowPos(HWND h,HWND after,int x,int y,int cx,int cy,UINT fl){
    if(g_vw && h==g_game_wnd && !(fl & SWP_NOSIZE)){ mark("SetWindowPos do jogo %dx%d ignorado (tamanho)", cx, cy); fl|=SWP_NOSIZE; }
    return r_SetWindowPos(h,after,x,y,cx,cy,fl);
}
static BOOL WINAPI h_MoveWindow(HWND h,int x,int y,int cx,int cy,BOOL rep){
    if(g_vw && h==g_game_wnd){ mark("MoveWindow do jogo %dx%d ignorado (tamanho)", cx, cy); return r_SetWindowPos(h,NULL,x,y,0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE); }
    return r_MoveWindow(h,x,y,cx,cy,rep);
}
/* o jogo pode trocar o próprio wndproc depois: manter o nosso na frente */
static LONG_PTR WINAPI h_SetWindowLongPtrA(HWND h,int i,LONG_PTR v){
    if(i==GWLP_WNDPROC && g_orig_proc && h==g_game_wnd){ LONG_PTR old=(LONG_PTR)g_orig_proc; g_orig_proc=(WNDPROC)v; return old; }
    return r_SetWindowLongPtrA(h,i,v);
}
static LONG_PTR WINAPI h_GetWindowLongPtrA(HWND h,int i){
    if(i==GWLP_WNDPROC && g_orig_proc && h==g_game_wnd) return (LONG_PTR)g_orig_proc;
    return r_GetWindowLongPtrA(h,i);
}

static LRESULT CALLBACK cbt_proc(int code,WPARAM wp,LPARAM lp){
    if(code==HCBT_CREATEWND){
        CBT_CREATEWNDA *cc=(CBT_CREATEWNDA*)lp; CREATESTRUCTA *cs=cc?cc->lpcs:NULL;
        char cls[64]={0};
        if(cs&&cs->lpszClass&&(((ULONG_PTR)cs->lpszClass)>>16)) lstrcpynA(cls,cs->lpszClass,63);
        if(cs&&lstrcmpA(cls,"config")==0){ g_game_wnd=(HWND)wp; mark("jogo criado %dx%d hwnd=%p",cs->cx,cs->cy,(void*)wp); }
    }
    return CallNextHookEx(NULL,code,wp,lp);
}
static DWORD WINAPI installer(LPVOID p){
    (void)p; Sleep(150);
    g_cbt=SetWindowsHookExA(WH_CBT,cbt_proc,GetModuleHandleW(L"avrt.dll"),g_main_tid); mark("cbt=%p",g_cbt);
    /* o ANGLE é carregado depois: interceptar assim que aparecer (até 10 min) */
    for(int i=0; i<6000 && !g_angle_patched; i++){ Sleep(100); patch_angle(); }
    return 0;
}
#define HOOK(name) do{ r_##name=(void*)iat_patch(exe,"USER32.dll",#name,(void*)h_##name); \
                       if(!r_##name) r_##name=(void*)GetProcAddress(u,#name); }while(0)
BOOL WINAPI DllMain(HINSTANCE h,DWORD r,LPVOID x){
    (void)x;
    if(r==DLL_PROCESS_ATTACH){
        g_main_tid=GetCurrentThreadId(); DisableThreadLibraryCalls(h);
        mark("DLL_PROCESS_ATTACH");
        HMODULE u=GetModuleHandleW(L"user32.dll"), exe=GetModuleHandleW(NULL);
        HOOK(GetClientRect); HOOK(GetWindowRect); HOOK(AdjustWindowRectEx);
        HOOK(ShowWindow); HOOK(SetWindowPlacement); HOOK(SetWindowPos); HOOK(MoveWindow);
        HOOK(SetWindowLongPtrA); HOOK(GetWindowLongPtrA);
        CloseHandle(CreateThread(NULL,0,installer,NULL,0,NULL));
    }
    return TRUE;
}
HANDLE WINAPI AvSetMmThreadCharacteristicsA(LPCSTR t,LPDWORD i){ (void)t;(void)i; return (HANDLE)1; }
HANDLE WINAPI AvSetMmThreadCharacteristicsW(LPCWSTR t,LPDWORD i){ (void)t;(void)i; return (HANDLE)1; }
BOOL WINAPI AvRevertMmThreadCharacteristic(HANDLE h){ (void)h; return TRUE; }
BOOL WINAPI AvQuerySystemResponsiveness(HANDLE h,PULONG v){ (void)h; if(v)*v=100; return TRUE; }
