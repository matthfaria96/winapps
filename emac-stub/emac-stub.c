#include <windows.h>
BOOL WINAPI DllMain(HINSTANCE h, DWORD r, LPVOID x) { (void)h;(void)r;(void)x; return TRUE; }
int __stdcall EMAC_SetEventCallBack(void* cb) { (void)cb; return 1; }
int __stdcall EMAC_ReceiveEvent(void* buf, int size) { (void)buf;(void)size; return 0; }
