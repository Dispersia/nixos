{
  boot.supportedFilesystems = [ "nfs" ];

  fileSystems."/mnt/media" = {
    device = "192.168.4.42:/volume1/media";
    fsType = "nfs";
    options = [
      "nfsvers=3"
      "noatime"
      "_netdev"
      "x-systemd.automount"
      "noauto"
    ];
  };
}
