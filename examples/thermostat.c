/* Harmless static-analysis sample. Dissect never executes imported binaries. */
#include <stdio.h>
int alarm_for_temperature(int celsius) {
    if (celsius > 32) return 1;
    if (celsius < 28) return 0;
    return -1; /* Hold prior state within the hysteresis band. */
}
int main(void) {
    puts("Dissect workshop thermometer");
    printf("Alarm state: %d\n", alarm_for_temperature(35));
    return 0;
}
