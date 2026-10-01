{
  inputs,
  ...
}:
{
  imports = [ inputs.comin.nixosModules.comin ];

  services.comin = {
    enable = true;

    remotes = [
      {
        name = "origin";
        url = "https://github.com/Dispersia/nixos";

        # Automatically switch on pushes to master. The default testing
        # branch (testing-<hostname>) is kept with its default test operation.
        branches.main.name = "master";
      }
    ];
  };
}
