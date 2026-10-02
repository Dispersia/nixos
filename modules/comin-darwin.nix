{
  inputs,
  hostName,
  ...
}:
{
  imports = [ inputs.comin.darwinModules.comin ];

  services.comin = {
    enable = true;

    hostname = hostName;

    remotes = [
      {
        name = "origin";
        url = "https://github.com/Dispersia/nixos";

        branches.main.name = "master";
      }
    ];
  };
}
