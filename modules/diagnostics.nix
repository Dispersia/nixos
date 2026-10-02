{ pkgs, ... }:
{
  # Diagnostics for intermittent hard freezes (no kernel log, hard reset needed).
  # Goal: make the next freeze leave a trace, and auto-recover instead of hanging.

  boot.kernel.sysctl = {
    # Full magic SysRq. During a hang try: Alt+SysRq+R E I S U B,
    # or Alt+SysRq+W (blocked tasks) / Alt+SysRq+L (CPU backtraces) to dump state.
    "kernel.sysrq" = 1;

    # Log tasks stuck (>60s) in D-state / uninterruptible IO stalls.
    "kernel.hung_task_timeout_secs" = 60;
    "kernel.hung_task_panic" = 0;

    # Detect and act on true CPU lockups via the NMI/PMU watchdog.
    # hardlockup_panic = reboot on a hard lockup (kernel can still print via NMI).
    "kernel.hardlockup_panic" = 1;
    # soft lockups are logged, not panicked, so a slow-but-recovering system
    # keeps its logs. The hardware watchdog below handles a full hang.
    "kernel.softlockup_panic" = 0;
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 0;

    # Don't panic on OOM; let the OOM killer / oomd handle it.
    "vm.panic_on_oom" = 0;
  };

  # Ping the sp5100_tco hardware watchdog (uses /dev/watchdog). If PID 1 cannot
  # run for a full minute the machine auto-reboots instead of hanging forever.
  systemd.settings.Manager.RuntimeWatchdogSec = "1min";

  # Add a MemTest86+ entry to the systemd-boot menu for overnight RAM testing.
  boot.loader.systemd-boot.memtest86.enable = true;

  # Persist resource history so the run-up to the next freeze can be inspected
  # with `sar -f /var/log/sysstat/sa<DD>` (CPU, memory, IO, swap, network).
  services.sysstat.enable = true;

  # Proactively watch disk health (reallocated sectors, pending, temperature).
  services.smartd = {
    enable = true;
    defaults.monitored = "-a -o on -S on -s (S/../.././02|L/../../7/03) -n standby,q -W 4,45,55";
  };

  environment.systemPackages = with pkgs; [
    sysstat
    atop
    lm_sensors
    pciutils
    usbutils
    smartmontools
    nvme-cli
    dmidecode
  ];
}
