# Chromium and its driver for the RSpec system specs (Capybara + Selenium), as the `browser` set.
# spec/support/system_spec_config.rb reads SPARC_TEST_CHROME_BIN; SE_CHROMEDRIVER stops Selenium
# downloading a driver of its own, which cannot run on NixOS.
_: {
  perSystem =
    { pkgs, lib, ... }:
    {
      sparc.sets.browser = {
        packages = [
          pkgs.chromium
          pkgs.chromedriver
        ];
        shellHook = ''
          export SPARC_TEST_CHROME_BIN="${lib.getExe pkgs.chromium}"
          export SE_CHROMEDRIVER="${lib.getExe pkgs.chromedriver}"
        '';
      };
    };
}
