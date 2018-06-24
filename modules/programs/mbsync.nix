{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.mbsync;
  accountCfg = config.mail.accounts;

  genAccountConfig = name: account: ''
    IMAPAccount ${name}
    Host ${account.imap.host}
    User ${account.userName}
    PassCmd "${toString account.passwordCommand}"
    SSLType IMAPS

    IMAPStore ${name}-remote
    Account ${name}

    MaildirStore ${name}-local
    Path ${account.maildir.path}
    Inbox ${account.maildir.path}/Inbox
    Flatten .

    Channel ${name}
    Master :${name}-remote:
    Slave :${name}-local:
    Patterns ${toString account.mbsync.patterns}
    Create Both
    Expunge Both
    SyncState *
  '';

in

{
  options = {
    programs.mbsync = {
      enable = mkEnableOption "mbsync IMAP4 and Maildir mailbox synchronizer";
    };

    mail.accounts = mkOption {
      options = [
        {
          mbsync = {
            enable = mkEnableOption "synchronization using mbsync";

            patterns = mkOption {
              type = types.listOf types.str;
              default = [ "*" ];
              description = ''
                Pattern of mailboxes to synchronize.
              '';
            };
          };
        }
      ];
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.isync ];

    home.file."TST-mbsyncrc".text =
      concatStringsSep "\n\n"
      (mapAttrsToList genAccountConfig
      (filterAttrs (name: account: account.mbsync.enable) accountCfg));
  };
}
