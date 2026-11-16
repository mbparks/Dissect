/* Header-free sample for ARM64 Mach-O object analysis; no executable entry point. */
const char project_name[] = "Dissect firmware workbench";
int alarm_for_temperature(int celsius, int previous_state) {
    if (celsius >= 32) return 1;
    if (celsius <= 28) return 0;
    return previous_state;
}
int sample_sensor_reading(void) {
    return alarm_for_temperature(30, 1);
}
