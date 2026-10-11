#include "NDIBridge.h"
#include <stdio.h>
int main(void) {
    if (SNDIRuntimeIsAvailable()) { fputs("First initialization should fail\n", stderr); return 1; }
    if (!SNDIRuntimeIsAvailable()) { fputs("Second initialization should recover\n", stderr); return 1; }
    puts("NDI runtime recovered from a failed first initialization");
    return 0;
}
