/* Biblioteca de compatibilidade emac-client64: exporta os 10 símbolos que o cliente
 * espera e registra cada chamada (horário, argumentos, retorno) em
 * C:\RubinOT\bin\x64\emac-stub-calls.log */
#include <windows.h>
#include <stdio.h>

static CRITICAL_SECTION g_cs;
static int g_init;
static void logf_(const char *n, unsigned long long a, unsigned long long b,
                  unsigned long long c, unsigned long long d, long long ret)
{
    SYSTEMTIME st;
    GetLocalTime(&st);
    if (g_init) EnterCriticalSection(&g_cs);
    FILE *f = fopen("C:\\RubinOT\\bin\\x64\\emac-stub-calls.log", "a");
    if (f) {
        fprintf(f, "%02d:%02d:%02d.%03d %s(%llx, %llx, %llx, %llx) -> %lld\n",
                st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, n, a, b, c, d, ret);
        fclose(f);
    }
    if (g_init) LeaveCriticalSection(&g_cs);
}

long long CLHB (unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("CLHB",a,b,c,d,0); return 0; }
long long CLVER(unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("CLVER",a,b,c,d,0); return 0; }
long long PF   (unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("PF",a,b,c,d,0); return 0; }
long long SLG  (unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("SLG",a,b,c,d,0); return 0; }
long long SWND (unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("SWND",a,b,c,d,0); return 0; }
long long USR  (unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("USR",a,b,c,d,0); return 0; }
long long USR2 (unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("USR2",a,b,c,d,0); return 0; }
long long USR3 (unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("USR3",a,b,c,d,0); return 0; }
long long USR4 (unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("USR4",a,b,c,d,0); return 0; }
long long USRLGT(unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long d){ logf_("USRLGT",a,b,c,d,0); return 0; }

BOOL WINAPI DllMain(HINSTANCE h, DWORD r, LPVOID x)
{
    (void)h; (void)x;
    if (r == DLL_PROCESS_ATTACH) { InitializeCriticalSection(&g_cs); g_init = 1; }
    return TRUE;
}
