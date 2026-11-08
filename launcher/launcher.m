#import <Cocoa/Cocoa.h>
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#include <stdio.h>

#define WINE      "/Users/macmini/wine-proton/bin/wine"
#define PREFIX    @"/Volumes/MacMiniDev/Moved/Emulador Windows/rubinot-prefix"
#define STUB      @"/Volumes/MacMiniDev/Moved/Emulador Windows/emac-stub.dll"
#define WINELIB   @"/Users/macmini/wine-proton/lib"
#define LOCKFILE  @"/tmp/nativewinapps.lock"

static NSWindow *win;
static NSTextField *label;
static NSTextField *sub;

static void killOld(void) {
    system("pkill -9 -f 'RubinOT.exe' 2>/dev/null; "
           "pkill -9 -f 'msedgewebview2.exe' 2>/dev/null; "
           "pkill -9 -f 'winedbg' 2>/dev/null");
}

static void launchGame(void) {
    NSString *root = [PREFIX stringByAppendingString:@"/drive_c/Program Files (x86)/RubinOT 2.0"];
    NSString *stubDst = [root stringByAppendingString:@"/emac-core.dll"];

    // garante a DLL stub (contorna o anti-cheat)
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:[root stringByAppendingString:@"/emac-core.dll.packed"]]) {
        [fm removeItemAtPath:stubDst error:nil];
        [fm copyItemAtPath:STUB toPath:stubDst error:nil];
    } else if ([fm fileExistsAtPath:STUB]) {
        if (![fm fileExistsAtPath:[root stringByAppendingString:@"/emac-core.dll.orig"]]) {
            [fm copyItemAtPath:stubDst toPath:[root stringByAppendingString:@"/emac-core.dll.orig"] error:nil];
        }
        [fm removeItemAtPath:stubDst error:nil];
        [fm copyItemAtPath:STUB toPath:stubDst error:nil];
    }

    killOld();
    // encerra a sessão anterior do wine (não precisa do DYLD)
    system("\"/Users/macmini/wine-proton/bin/wine\" wineserver -k 2>/dev/null");
    sleep(2);

    // variáveis de ambiente (definidas antes do fork)
    setenv("WINEPREFIX", [PREFIX UTF8String], 1);
    setenv("WINEDLLOVERRIDES", "mscoree,mshtml=", 1);
    setenv("WINEDEBUG", "-all", 1);
    setenv("DYLD_FALLBACK_LIBRARY_PATH", [WINELIB UTF8String], 1);

    // lança o jogo como processo desanexado (sobrevive ao launcher fechar)
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        NSString *logPath = [NSHomeDirectory() stringByAppendingString:@"/Library/Logs/NativeWinApps.log"];
        int fd = open([logPath UTF8String], O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); if (fd > 2) close(fd); }
        execl(WINE, WINE, "C:\\Program Files (x86)\\RubinOT 2.0\\RubinOT.exe", (char *)NULL);
        _exit(127);
    }
}

static BOOL gameReady(void) {
    FILE *p = popen("pgrep -f 'msedgewebview2.exe' >/dev/null 2>&1 && echo yes || echo no", "r");
    char buf[8] = {0};
    if (p) { fgets(buf, sizeof(buf), p); pclose(p); }
    return (strcmp(buf, "yes\n") == 0);
}

static void activateGame(void) {
    // ativa o app "wine" (dono da janela do jogo) para trazê-la à frente
    for (NSRunningApplication *ra in [[NSWorkspace sharedWorkspace] runningApplications]) {
        NSString *exe = ra.executableURL.lastPathComponent ?: @"";
        if ([ra.localizedName isEqualToString:@"wine"] || [exe hasPrefix:@"wine"]) {
            [ra activateWithOptions:NSApplicationActivateAllWindows];
            break;
        }
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        // trava de instância única
        if ([fm fileExistsAtPath:LOCKFILE]) {
            NSString *s = [NSString stringWithContentsOfFile:LOCKFILE encoding:NSUTF8StringEncoding error:nil];
            int pid = [s intValue];
            if (pid > 0 && kill(pid, 0) == 0) {
                NSRunningApplication *ra = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
                if (ra) [ra activateWithOptions:NSApplicationActivateAllWindows];
                return 0;
            }
        }
        [[@([[NSProcessInfo processInfo] processIdentifier]) stringValue]
            writeToFile:LOCKFILE atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 130)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [win setTitle:@"Native WinApps"];
        [win center];
        [win setLevel:NSFloatingWindowLevel];

        label = [NSTextField labelWithString:@"Iniciando o RubinOT…"];
        [label setFrame:NSMakeRect(24, 82, 392, 26)];
        [label setFont:[NSFont boldSystemFontOfSize:16]];
        [[win contentView] addSubview:label];

        sub = [NSTextField labelWithString:@"Aguarde 30–60 segundos…"];
        [sub setFrame:NSMakeRect(24, 60, 392, 18)];
        [sub setFont:[NSFont systemFontOfSize:13]];
        [sub setTextColor:[NSColor secondaryLabelColor]];
        [[win contentView] addSubview:sub];

        NSProgressIndicator *spin = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(204, 18, 32, 32)];
        [spin setStyle:NSProgressIndicatorStyleSpinning];
        [spin startAnimation:nil];
        [[win contentView] addSubview:spin];

        [win makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ launchGame(); });

        __block int readySeen = 0;
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *tmr) {
            if (gameReady()) {
                if (readySeen == 0) {
                    readySeen = 1;
                    [label setStringValue:@"RubinOT pronto!"];
                    [sub setStringValue:@"Abrindo a janela do jogo…"];
                    activateGame();
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2500 * NSEC_PER_MSEC),
                                   dispatch_get_main_queue(), ^{
                        [win orderOut:nil];
                        [NSApp terminate:nil];
                    });
                    [tmr invalidate];
                }
            }
        }];

        [app run];

        [fm removeItemAtPath:LOCKFILE error:nil];
    }
    return 0;
}
